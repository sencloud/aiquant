package strategy

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/ai/tushare"
	"github.com/sencloud/finme-backend/internal/store"
)

// Service 负责抓取、归一化、落库与读取主策略快照。
type Service struct {
	st      *store.Store
	tu      *tushare.Client
	logger  *zerolog.Logger
	baseURL string
	httpc   *http.Client
	cal     *calendarCache
}

func NewService(st *store.Store, l *zerolog.Logger, tu *tushare.Client, baseURL string) *Service {
	if baseURL == "" {
		baseURL = "https://x.singzquant.com"
	}
	return &Service{
		st:      st,
		tu:      tu,
		logger:  l,
		baseURL: strings.TrimRight(baseURL, "/"),
		httpc:   &http.Client{Timeout: 30 * time.Second},
		cal:     newCalendarCache(),
	}
}

// Sync 拉一次外部数据并落库。dashboard 失败即整体失败；live 失败只降级。
func (s *Service) Sync(ctx context.Context) (*Snapshot, error) {
	var dash dashResp
	if err := s.getJSON(ctx, "/api/dashboard", &dash); err != nil {
		return nil, fmt.Errorf("fetch dashboard: %w", err)
	}
	snap := normalize(&dash)

	var live liveResp
	liveOK := false
	if err := s.getJSON(ctx, "/api/live", &live); err != nil {
		// 实盘接口挂掉不该让整张策略卡消失，只降级为没有实盘段。
		s.logger.Warn().Err(err).Msg("strategy: fetch live failed, degrade")
	} else {
		liveOK = true
		snap.Live = normalizeLive(&live, snap.Action.Target)
	}

	// 数据截至：回测截止日与实盘最新日取较新者。
	if liveOK {
		snap.DataAsOf = laterDate(snap.DataAsOf, live.AsOf)
	}
	payload, err := json.Marshal(snap)
	if err != nil {
		return nil, err
	}
	now := time.Now().UnixMilli()
	if _, err := s.st.DB.ExecContext(ctx, `
		INSERT INTO strategy_snapshots(strategy_id, data_as_of, payload_json, fetched_at)
		VALUES(?, ?, ?, ?)`, PrimaryID, snap.DataAsOf, string(payload), now); err != nil {
		return nil, fmt.Errorf("insert snapshot: %w", err)
	}
	// 只留最近 200 条：这张表回答的是"最近看到的是什么"，不是历史档案。
	_, _ = s.st.DB.ExecContext(ctx, `
		DELETE FROM strategy_snapshots
		WHERE strategy_id=? AND id NOT IN (
			SELECT id FROM strategy_snapshots WHERE strategy_id=?
			ORDER BY fetched_at DESC LIMIT 200)`, PrimaryID, PrimaryID)

	snap.SyncedAt = now
	// 断更告警：策略唯一的可执行输出是调仓指令，数据一旦落后，界面上的指令就是
	// 旧的。这里每次都打一条 WARN（带落后交易日数），运维可以直接对这条日志告警。
	stale, days := s.staleness(ctx, snap.DataAsOf, time.Now())
	if stale {
		s.logger.Warn().
			Str("data_as_of", snap.DataAsOf).
			Int("stale_days", days).
			Msg("strategy: DATA STALE — 上游发布管线可能没跑，界面会提示用户数据已过期")
	}
	s.logger.Info().
		Str("data_as_of", snap.DataAsOf).
		Bool("stale", stale).
		Int("stale_days", days).
		Bool("has_live", snap.Live != nil).
		Str("signal", snap.Action.SignalDate).
		Str("exec", snap.Action.ExecDate).
		Msg("strategy: snapshot synced")
	return snap, nil
}

// Latest 读最近一份快照，并现算「是否落后于最近一个交易日」。
func (s *Service) Latest(ctx context.Context) (*Snapshot, error) {
	var row struct {
		Payload   string `db:"payload_json"`
		FetchedAt int64  `db:"fetched_at"`
	}
	err := s.st.DB.GetContext(ctx, &row, `
		SELECT payload_json, fetched_at FROM strategy_snapshots
		WHERE strategy_id=? ORDER BY fetched_at DESC, id DESC LIMIT 1`, PrimaryID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var snap Snapshot
	if err := json.Unmarshal([]byte(row.Payload), &snap); err != nil {
		return nil, fmt.Errorf("decode snapshot: %w", err)
	}
	snap.SyncedAt = row.FetchedAt
	snap.Stale, snap.StaleDays = s.staleness(ctx, snap.DataAsOf, time.Now())
	return &snap, nil
}

// getJSON 拉一个外部接口并解码。外部响应体上限 8MB——这是别人的看板，
// 不该让一个异常响应把内存打满。
func (s *Service) getJSON(ctx context.Context, path string, dst any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, s.baseURL+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "finme-backend")
	resp, err := s.httpc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return fmt.Errorf("status %d: %s", resp.StatusCode, string(b))
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 8<<20)).Decode(dst)
}
