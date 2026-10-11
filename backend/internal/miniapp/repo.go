package miniapp

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"

	"github.com/jmoiron/sqlx"
)

type appRow struct {
	ID             int64          `db:"id"`
	UUID           string         `db:"uuid"`
	UserID         int64          `db:"user_id"`
	Topic          string         `db:"topic"`
	Title          string         `db:"title"`
	Icon           string         `db:"icon"`
	Summary        string         `db:"summary"`
	Status         string         `db:"status"`
	CurrentVersion int            `db:"current_version"`
	SessionID      string         `db:"session_id"`
	TemplateID     sql.NullString `db:"template_id"`
	CreatedAt      int64          `db:"created_at"`
	UpdatedAt      int64          `db:"updated_at"`
	DeletedAt      sql.NullInt64  `db:"deleted_at"`
}

type versionRow struct {
	ID            int64          `db:"id"`
	AppID         int64          `db:"app_id"`
	Version       int            `db:"version"`
	SchemaVer     string         `db:"schema_ver"`
	MinRenderer   int            `db:"min_renderer"`
	SpecJSON      string         `db:"spec_json"`
	SpecHash      string         `db:"spec_hash"`
	ChangeSummary string         `db:"change_summary"`
	Author        string         `db:"author"`
	GenID         sql.NullString `db:"gen_id"`
	CreatedAt     int64          `db:"created_at"`
}

type genRow struct {
	ID               int64          `db:"id"`
	RequestID        string         `db:"request_id"`
	UserID           int64          `db:"user_id"`
	Topic            string         `db:"topic"`
	SessionID        string         `db:"session_id"`
	AppID            sql.NullInt64  `db:"app_id"`
	Kind             string         `db:"kind"`
	Status           string         `db:"status"`
	Stage            string         `db:"stage"`
	Outcome          string         `db:"outcome"`
	Message          string         `db:"message"`
	ResultJSON       sql.NullString `db:"result_json"`
	Error            sql.NullString `db:"error"`
	Credits          int64          `db:"credits"`
	Refunded         bool           `db:"refunded"`
	Model            string         `db:"model"`
	PromptTokens     int64          `db:"prompt_tokens"`
	CompletionTokens int64          `db:"completion_tokens"`
	RepairRounds     int            `db:"repair_rounds"`
	LatencyMs        int64          `db:"latency_ms"`
	CreatedAt        int64          `db:"created_at"`
	UpdatedAt        int64          `db:"updated_at"`
}

func specHash(b []byte) string {
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:8])
}

func (s *Service) appByUUID(ctx context.Context, uid int64, uuid string) (*appRow, error) {
	var r appRow
	err := s.st.DB.GetContext(ctx, &r,
		"SELECT * FROM mini_apps WHERE uuid=? AND user_id=? AND deleted_at IS NULL", uuid, uid)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return &r, err
}

func (s *Service) versionOf(ctx context.Context, appID int64, v int) (*versionRow, error) {
	var r versionRow
	err := s.st.DB.GetContext(ctx, &r, "SELECT * FROM mini_app_versions WHERE app_id=? AND version=?", appID, v)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return &r, err
}

func (s *Service) countApps(ctx context.Context, q sqlx.QueryerContext, uid int64, topic string) (int, error) {
	var n int
	err := sqlx.GetContext(ctx, q, &n,
		"SELECT COUNT(*) FROM mini_apps WHERE user_id=? AND topic=? AND deleted_at IS NULL", uid, topic)
	return n, err
}

// insertVersionTx 写一个新版本，并把 app 指向它；超出保留数的旧版本删除。
func insertVersionTx(ctx context.Context, tx *sqlx.Tx, app *appRow, c *Compiled, summary, author, genID string, now int64) (int, []byte, error) {
	b, err := json.Marshal(c.Raw)
	if err != nil {
		return 0, nil, err
	}
	var maxV sql.NullInt64
	if err := tx.GetContext(ctx, &maxV, "SELECT MAX(version) FROM mini_app_versions WHERE app_id=?", app.ID); err != nil {
		return 0, nil, err
	}
	v := int(maxV.Int64) + 1
	if _, err := tx.ExecContext(ctx, `INSERT INTO mini_app_versions(app_id, version, schema_ver, min_renderer, spec_json, spec_hash,
		change_summary, author, gen_id, created_at) VALUES(?,?,?,?,?,?,?,?,?,?)`,
		app.ID, v, SchemaID, c.MinRenderer, string(b), specHash(b), summary, author, nullIfEmpty(genID), now); err != nil {
		return 0, nil, err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE mini_apps SET current_version=?, title=?, icon=?, summary=?, updated_at=? WHERE id=?`,
		v, c.Title, c.Icon, c.Summary, now, app.ID); err != nil {
		return 0, nil, err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM mini_app_versions WHERE app_id=? AND version<=?`, app.ID, v-MaxVersionsKept); err != nil {
		return 0, nil, err
	}
	app.CurrentVersion, app.Title, app.Icon, app.Summary, app.UpdatedAt = v, c.Title, c.Icon, c.Summary, now
	return v, b, nil
}

func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}
