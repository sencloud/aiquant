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
func Open(cfg platform.DBConfig) (*Store, error) {
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

	s := &Store{DB: db}
	if err := s.runMigrations(); err != nil {
		_ = db.Close()
		return nil, err
	}
	return s, nil
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

// runMigrations 顺序执行 migrations_embed 下所有 .sql。
// 首次运行会建 schema_migrations 表，记录已执行 filename。
func (s *Store) runMigrations() error {
	if _, err := s.DB.Exec(`
		CREATE TABLE IF NOT EXISTS schema_migrations (
			file TEXT PRIMARY KEY,
			applied_at INTEGER NOT NULL
		)`); err != nil {
		return fmt.Errorf("create schema_migrations: %w", err)
	}

	entries, err := embeddedFS.ReadDir("migrations")
	if err != nil {
		return fmt.Errorf("read migrations: %w", err)
	}
	files := make([]string, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".sql") {
			continue
		}
		files = append(files, e.Name())
	}
	sort.Strings(files)

	for _, f := range files {
		var dummy string
		err := s.DB.Get(&dummy, "SELECT file FROM schema_migrations WHERE file=?", f)
		if err == nil {
			continue
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return fmt.Errorf("check migration %s: %w", f, err)
		}
		raw, err := embeddedFS.ReadFile("migrations/" + f)
		if err != nil {
			return fmt.Errorf("read %s: %w", f, err)
		}
		// SQLite 驱动不支持多语句 — 用最朴素的 ; 切分（注释/字符串里的 ; 我们自己控制不出现）。
		stmts := splitSQL(string(raw))
		tx, err := s.DB.Beginx()
		if err != nil {
			return fmt.Errorf("begin migrate %s: %w", f, err)
		}
		for _, stmt := range stmts {
			stmt = strings.TrimSpace(stmt)
			if stmt == "" {
				continue
			}
			if _, err := tx.Exec(stmt); err != nil {
				_ = tx.Rollback()
				return fmt.Errorf("exec migrate %s: %w\n--\n%s", f, err, stmt)
			}
		}
		if _, err := tx.Exec(
			"INSERT INTO schema_migrations(file, applied_at) VALUES (?, ?)",
			f, time.Now().UnixMilli(),
		); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("record migration %s: %w", f, err)
		}
		if err := tx.Commit(); err != nil {
			return fmt.Errorf("commit migrate %s: %w", f, err)
		}
	}
	return nil
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
