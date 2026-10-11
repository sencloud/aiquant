// Package store 封装 SQLite 连接、迁移与事务工具。
//
// SQLite 的并发模型：单写多读 + WAL。我们用一个写连接（max 1 写）+ N 个
// 读连接来贴合这个模型，但实测 sqlx + busy_timeout 已能在 10k 用户场景下
// 自动排队不出错，所以我们这里采用最简单的"单 *sqlx.DB 池"模式 + 显式
// 长事务封装。
package store

import (
	"context"
	"database/sql"
	"embed"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jmoiron/sqlx"
	_ "modernc.org/sqlite"

	"github.com/sencloud/finme-backend/internal/platform"
)

//go:embed migrations/*.sql
var embeddedFS embed.FS

// Store 是上层对 DB 的访问句柄。
type Store struct {
	DB *sqlx.DB
}

// Open 打开 SQLite，应用 PRAGMA，运行内嵌迁移。
// 只有 api 进程（以及测试、一次性工具）应该用它；scheduler / pusher 用
// OpenNoMigrate + WaitForSchema，避免多个进程同时跑迁移互相冲突。
func Open(cfg platform.DBConfig) (*Store, error) {
	s, err := OpenNoMigrate(cfg)
	if err != nil {
		return nil, err
	}
	if _, err := s.Migrate(); err != nil {
		_ = s.DB.Close()
		return nil, err
	}
	return s, nil
}

// OpenNoMigrate 打开 SQLite 并应用 PRAGMA，但不执行任何迁移。
func OpenNoMigrate(cfg platform.DBConfig) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(cfg.Path), 0o750); err != nil {
		return nil, fmt.Errorf("mkdir db dir: %w", err)
	}

	q := url.Values{}
	q.Set("_pragma", "journal_mode(WAL)")
	q.Add("_pragma", "synchronous(NORMAL)")
	q.Add("_pragma", fmt.Sprintf("busy_timeout(%d)", cfg.BusyTimeoutMs))
	q.Add("_pragma", fmt.Sprintf("cache_size(-%d)", cfg.CacheKB))
	q.Add("_pragma", "foreign_keys(ON)")
	q.Add("_pragma", "temp_store(MEMORY)")
	dsn := fmt.Sprintf("file:%s?%s", cfg.Path, q.Encode())

	db, err := sqlx.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("open sqlite: %w", err)
	}
	db.SetMaxOpenConns(cfg.MaxOpenConns)
	db.SetMaxIdleConns(cfg.MaxIdleConns)
	db.SetConnMaxLifetime(time.Hour)

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping sqlite: %w", err)
	}

	return &Store{DB: db}, nil
}

func (s *Store) Close() error {
	return s.DB.Close()
}

// Tx 在事务中运行 fn，自动 commit/rollback。
// 嵌套事务直接复用外层 tx（通过 ctx 传播）。
func (s *Store) Tx(ctx context.Context, fn func(tx *sqlx.Tx) error) error {
	if tx := txFromCtx(ctx); tx != nil {
		return fn(tx)
	}
	tx, err := s.DB.BeginTxx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() {
		if p := recover(); p != nil {
			_ = tx.Rollback()
			panic(p)
		}
	}()
	if err := fn(tx); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

type txCtxKey struct{}

func WithTx(ctx context.Context, tx *sqlx.Tx) context.Context {
	return context.WithValue(ctx, txCtxKey{}, tx)
}
func txFromCtx(ctx context.Context) *sqlx.Tx {
	if v, ok := ctx.Value(txCtxKey{}).(*sqlx.Tx); ok {
		return v
	}
	return nil
}

// EmbeddedMigrations 返回本二进制内嵌的全部迁移文件名（已排序）。
func EmbeddedMigrations() ([]string, error) {
	entries, err := embeddedFS.ReadDir("migrations")
	if err != nil {
		return nil, fmt.Errorf("read migrations: %w", err)
	}
	files := make([]string, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".sql") {
			continue
		}
		files = append(files, e.Name())
	}
	sort.Strings(files)
	return files, nil
}

// PendingMigrations 返回内嵌但尚未记录在 schema_migrations 里的迁移。
// schema_migrations 表不存在时视为全部未执行。只读，不建表。
func (s *Store) PendingMigrations(ctx context.Context) ([]string, error) {
	files, err := EmbeddedMigrations()
	if err != nil {
		return nil, err
	}
	var n int
	if err := s.DB.GetContext(ctx, &n,
		`SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='schema_migrations'`); err != nil {
		return nil, fmt.Errorf("check schema_migrations: %w", err)
	}
	if n == 0 {
		return files, nil
	}
	var applied []string
	if err := s.DB.SelectContext(ctx, &applied, "SELECT file FROM schema_migrations"); err != nil {
		return nil, fmt.Errorf("list schema_migrations: %w", err)
	}
	done := make(map[string]bool, len(applied))
	for _, f := range applied {
		done[f] = true
	}
	pending := []string{}
	for _, f := range files {
		if !done[f] {
			pending = append(pending, f)
		}
	}
	return pending, nil
}

// ErrSchemaNotReady 表示等待超时后库里仍有未执行的迁移。
var ErrSchemaNotReady = errors.New("database schema not ready")

// WaitForSchema 供不执行迁移的进程（scheduler / pusher）使用：每 poll
// 检查一次，直到内嵌的迁移全部被 api 进程执行完；timeout 内没完成返回
// ErrSchemaNotReady（带未执行列表），调用方应退出，由 systemd 重启重试。
// onWait 在每次仍未就绪时被调用（可为 nil），用于打日志。
func (s *Store) WaitForSchema(ctx context.Context, timeout, poll time.Duration, onWait func(pending []string)) error {
	if poll <= 0 {
		poll = time.Second
	}
	deadline := time.Now().Add(timeout)
	for {
		pending, err := s.PendingMigrations(ctx)
		if err == nil && len(pending) == 0 {
			return nil
		}
		if time.Now().After(deadline) {
			if err != nil {
				return fmt.Errorf("%w: %v", ErrSchemaNotReady, err)
			}
			return fmt.Errorf("%w: pending %s", ErrSchemaNotReady, strings.Join(pending, ", "))
		}
		if onWait != nil && err == nil {
			onWait(pending)
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(poll):
		}
	}
}

// Migrate 顺序执行 migrations 下所有尚未执行的 .sql，返回本次执行的文件。
// 首次运行会建 schema_migrations 表，记录已执行 filename。
// 只应由 api 进程调用（见 Open）。
func (s *Store) Migrate() ([]string, error) {
	if _, err := s.DB.Exec(`
		CREATE TABLE IF NOT EXISTS schema_migrations (
			file TEXT PRIMARY KEY,
			applied_at INTEGER NOT NULL
		)`); err != nil {
		return nil, fmt.Errorf("create schema_migrations: %w", err)
	}

	files, err := EmbeddedMigrations()
	if err != nil {
		return nil, err
	}

	ran := []string{}
	for _, f := range files {
		var dummy string
		err := s.DB.Get(&dummy, "SELECT file FROM schema_migrations WHERE file=?", f)
		if err == nil {
			continue
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return ran, fmt.Errorf("check migration %s: %w", f, err)
		}
		raw, err := embeddedFS.ReadFile("migrations/" + f)
		if err != nil {
			return ran, fmt.Errorf("read %s: %w", f, err)
		}
		// SQLite 驱动不支持多语句 — 用最朴素的 ; 切分（注释/字符串里的 ; 我们自己控制不出现）。
		stmts := splitSQL(string(raw))
		tx, err := s.DB.Beginx()
		if err != nil {
			return ran, fmt.Errorf("begin migrate %s: %w", f, err)
		}
		for _, stmt := range stmts {
			stmt = strings.TrimSpace(stmt)
			if stmt == "" {
				continue
			}
			if _, err := tx.Exec(stmt); err != nil {
				_ = tx.Rollback()
				return ran, fmt.Errorf("exec migrate %s: %w\n--\n%s", f, err, stmt)
			}
		}
		if _, err := tx.Exec(
			"INSERT INTO schema_migrations(file, applied_at) VALUES (?, ?)",
			f, time.Now().UnixMilli(),
		); err != nil {
			_ = tx.Rollback()
			return ran, fmt.Errorf("record migration %s: %w", f, err)
		}
		if err := tx.Commit(); err != nil {
			return ran, fmt.Errorf("commit migrate %s: %w", f, err)
		}
		ran = append(ran, f)
	}
	return ran, nil
}

// splitSQL 用最朴素的分号切割。我们的 migration 都是简单 DDL，
// 不涉及 trigger/begin..end 这种内部带分号的复杂语法。
func splitSQL(in string) []string {
	out := []string{}
	cur := strings.Builder{}
	for _, line := range strings.Split(in, "\n") {
		// 行注释整行去掉
		trim := strings.TrimSpace(line)
		if strings.HasPrefix(trim, "--") {
			continue
		}
		cur.WriteString(line)
		cur.WriteByte('\n')
		if strings.HasSuffix(trim, ";") {
			out = append(out, cur.String())
			cur.Reset()
		}
	}
	if strings.TrimSpace(cur.String()) != "" {
		out = append(out, cur.String())
	}
	return out
}
