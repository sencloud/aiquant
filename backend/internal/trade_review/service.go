// Package trade_review 保存登录用户的成交复盘，并提供可复现的 FIFO 分析。
package trade_review

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/sencloud/finme-backend/internal/store"
)

// ErrNotFound 表示该账号下不存在指定复盘。
var ErrNotFound = errors.New("trade review not found")

// MaxReportsPerAccount 是服务端强制保留的最近复盘数量。
const MaxReportsPerAccount = 20

// ContextEnricher 为已解析成交补充成交日附近的行情、宏观和新闻背景。
// 单个数据源失败时应返回缺口，而不是阻断成交本身的 FIFO 分析。
type ContextEnricher interface {
	Enrich(
		ctx context.Context,
		report Report,
	) (MarketContext, []Perspective, []string)
}

// Service 是成交复盘的账号级存储。
type Service struct {
	st       *store.Store
	enricher ContextEnricher
}

func NewService(st *store.Store, enrichers ...ContextEnricher) *Service {
	var enricher ContextEnricher
	if len(enrichers) > 0 {
		enricher = enrichers[0]
	}
	return &Service{st: st, enricher: enricher}
}

// Analyze 先完成可复算的成交分析，再补充市场背景。
// 背景查询受独立超时约束，任何上游失败都不会吞掉已经算出的成交指标。
func (s *Service) Analyze(
	ctx context.Context,
	in AnalyzeInput,
	now time.Time,
) Report {
	report := Analyze(in, now)
	report.Perspectives = append(
		report.Perspectives,
		buildBehaviorPerspective(report),
	)
	if s == nil || s.enricher == nil {
		return report
	}

	enrichCtx, cancel := context.WithTimeout(ctx, 32*time.Second)
	defer cancel()
	marketContext, perspectives, warnings := s.enricher.Enrich(enrichCtx, report)
	report.MarketContext = marketContext
	if report.MarketContext.Events == nil {
		report.MarketContext.Events = []ContextEvent{}
	}
	if report.MarketContext.Coverage == nil {
		report.MarketContext.Coverage = []ContextCoverage{}
	}
	if report.MarketContext.Gaps == nil {
		report.MarketContext.Gaps = []string{}
	}
	if len(perspectives) > 0 {
		report.Perspectives = append(report.Perspectives, perspectives...)
	}
	for _, warning := range warnings {
		report.Warnings = append(report.Warnings, warning)
	}
	report.Warnings = unique(report.Warnings)
	return report
}

// List 返回该账号按更新时间倒序排列的复盘 JSON。
func (s *Service) List(ctx context.Context, userID int64) ([]json.RawMessage, error) {
	rows, err := s.st.DB.QueryContext(ctx,
		`SELECT report_json FROM trade_reviews
		 WHERE user_id=? ORDER BY updated_at DESC, created_at DESC, id DESC`,
		userID)
	if err != nil {
		return nil, fmt.Errorf("list trade reviews: %w", err)
	}
	defer rows.Close()

	out := make([]json.RawMessage, 0)
	for rows.Next() {
		var raw []byte
		if err := rows.Scan(&raw); err != nil {
			return nil, fmt.Errorf("scan trade review: %w", err)
		}
		if json.Valid(raw) {
			out = append(out, json.RawMessage(raw))
		}
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate trade reviews: %w", err)
	}
	return out, nil
}

// Save 新建或更新一份复盘。所有写入都以 user_id 为约束。
func (s *Service) Save(
	ctx context.Context,
	userID int64,
	id string,
	report json.RawMessage,
	createdAt time.Time,
) error {
	if id == "" {
		return errors.New("empty report id")
	}
	if len(report) == 0 || !json.Valid(report) {
		return errors.New("invalid report json")
	}
	now := time.Now().UnixMilli()
	created := now
	if createdAt.IsZero() {
		createdAt = time.UnixMilli(created)
	}
	created = createdAt.UnixMilli()
	tx, err := s.st.DB.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin trade review save: %w", err)
	}
	defer tx.Rollback()

	_, err = tx.ExecContext(ctx, `
		INSERT INTO trade_reviews(user_id, id, report_json, created_at, updated_at)
		VALUES(?, ?, ?, ?, ?)
		ON CONFLICT(user_id, id) DO UPDATE SET
			report_json=excluded.report_json,
			updated_at=excluded.updated_at`,
		userID, id, string(report), created, now)
	if err != nil {
		return fmt.Errorf("save trade review: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM trade_reviews
		WHERE user_id=? AND id NOT IN (
			SELECT id FROM trade_reviews
			WHERE user_id=?
			ORDER BY updated_at DESC, created_at DESC, id DESC
			LIMIT ?
		)`, userID, userID, MaxReportsPerAccount); err != nil {
		return fmt.Errorf("prune trade reviews: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit trade review save: %w", err)
	}
	return nil
}

// Delete 只删除当前账号下的复盘。
func (s *Service) Delete(ctx context.Context, userID int64, id string) error {
	res, err := s.st.DB.ExecContext(ctx,
		"DELETE FROM trade_reviews WHERE user_id=? AND id=?", userID, id)
	if err != nil {
		return fmt.Errorf("delete trade review: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("delete trade review rows: %w", err)
	}
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}
