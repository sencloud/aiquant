package falsification

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/store"
)

// 数据来源标记（响应里的 origin 字段）。
const (
	OriginRemote = "remote" // 来自 alpha-radar 的快照
	OriginSeed   = "seed"   // 内置兜底
)

// Service 负责证伪档案的同步、读取、解锁和跑证伪任务。
type Service struct {
	st     *store.Store
	logger *zerolog.Logger
	url    string
	httpc  *http.Client

	runner Runner
	prices Prices

	mu       sync.Mutex
	cached   Payload
	origin   string
	cachedAt time.Time
	cacheTTL time.Duration
}

// Prices 是解锁 / 跑证伪的喜点价格（来自 config credits.*）。
type Prices struct {
	Unlock        int64 `json:"unlock"`
	FalsifyDaily  int64 `json:"falsify_daily"`
	FalsifyMinute int64 `json:"falsify_minute"`
}

// Options 构造参数。
type Options struct {
	URL    string // alpha-radar 根地址；空 = 只用 seed
	Runner Runner // nil = StubRunner
	Prices Prices
}

func NewService(st *store.Store, l *zerolog.Logger, opt Options) *Service {
	if l == nil {
		nop := zerolog.Nop()
		l = &nop
	}
	r := opt.Runner
	if r == nil {
		r = StubRunner{}
	}
	return &Service{
		st:       st,
		logger:   l,
		url:      strings.TrimRight(strings.TrimSpace(opt.URL), "/"),
		httpc:    &http.Client{Timeout: 30 * time.Second},
		runner:   r,
		prices:   opt.Prices,
		cacheTTL: time.Minute,
	}
}

// Prices 返回当前价格表。
func (s *Service) Prices() Prices { return s.prices }

// Sync 从 alpha-radar 拉一份档案，脱敏后落库。返回条目数。
func (s *Service) Sync(ctx context.Context) (int, error) {
	if s.url == "" {
		return 0, errors.New("alpharadar url not configured")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, s.url+"/api/falsification?include=insufficient", nil)
	if err != nil {
		return 0, err
	}
	req.Header.Set("User-Agent", "finme-backend")
	resp, err := s.httpc.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return 0, fmt.Errorf("status %d: %s", resp.StatusCode, string(b))
	}
	// 上游是几百条结论，16MB 足够；异常响应不能把内存打满。
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 16<<20))
	if err != nil {
		return 0, err
	}
	p, err := Decode(raw)
	if err != nil {
		return 0, err
	}
	p = Sanitize(p)
	n := len(Archive(p))
	if n == 0 {
		// 空档案多半是上游出错：保留上一份，不覆盖。
		return 0, errors.New("upstream archive empty, keep last snapshot")
	}
	payload, err := json.Marshal(p)
	if err != nil {
		return 0, err
	}
	now := time.Now().UnixMilli()
	if _, err := s.st.DB.ExecContext(ctx, `
		INSERT INTO falsification_snapshots(generated_at, threshold_version, entry_count, payload_json, fetched_at)
		VALUES(?, ?, ?, ?, ?)`,
		str(p["generated_at"]), str(p["threshold_version"]), n, string(payload), now); err != nil {
		return 0, fmt.Errorf("insert snapshot: %w", err)
	}
	// 只留最近 50 份：这张表回答「最近看到的是什么」，不是历史档案。
	_, _ = s.st.DB.ExecContext(ctx, `
		DELETE FROM falsification_snapshots WHERE id NOT IN (
			SELECT id FROM falsification_snapshots ORDER BY fetched_at DESC, id DESC LIMIT 50)`)
	s.invalidate()
	s.logger.Info().Int("entries", n).
		Str("threshold_version", str(p["threshold_version"])).
		Msg("falsification: snapshot synced")
	return n, nil
}

func (s *Service) invalidate() {
	s.mu.Lock()
	s.cached = nil
	s.mu.Unlock()
}

// Current 返回当前档案（只读，调用方不要修改）与来源。
// 读库失败或库里没有快照时回落 seed —— 档案页永远有内容。
func (s *Service) Current(ctx context.Context) (Payload, string) {
	s.mu.Lock()
	if s.cached != nil && time.Since(s.cachedAt) < s.cacheTTL {
		p, o := s.cached, s.origin
		s.mu.Unlock()
		return p, o
	}
	s.mu.Unlock()

	p, origin := s.load(ctx)

	s.mu.Lock()
	s.cached, s.origin, s.cachedAt = p, origin, time.Now()
	s.mu.Unlock()
	return p, origin
}

func (s *Service) load(ctx context.Context) (Payload, string) {
	seed, seedErr := Seed()
	if seedErr != nil {
		s.logger.Error().Err(seedErr).Msg("falsification: seed broken")
		seed = Payload{"archive": []any{}}
	}
	if s.st != nil {
		var raw string
		err := s.st.DB.GetContext(ctx, &raw, `
			SELECT payload_json FROM falsification_snapshots
			ORDER BY fetched_at DESC, id DESC LIMIT 1`)
		switch {
		case err == nil:
			if p, derr := Decode([]byte(raw)); derr == nil {
				return Merge(Sanitize(p), seed), OriginRemote
			} else {
				s.logger.Warn().Err(derr).Msg("falsification: bad snapshot, fallback to seed")
			}
		case errors.Is(err, sql.ErrNoRows):
		default:
			s.logger.Warn().Err(err).Msg("falsification: read snapshot failed, fallback to seed")
		}
	}
	return seed, OriginSeed
}
