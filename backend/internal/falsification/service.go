package falsification

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
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
	list   ListOptions

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
	List   ListOptions // 通讯录列表收窄；零值取默认
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
		list:     opt.List.normalized(),
		cacheTTL: time.Minute,
	}
}

// Prices 返回当前价格表。
func (s *Service) Prices() Prices { return s.prices }

// ListOptions 返回列表收窄参数。
func (s *Service) ListOptions() ListOptions { return s.list }

// SnapshotRetention 是 falsification_snapshots 最多保留的份数。只有内容变化才
// 新增一行（见 Sync），10 份足够回答「最近几次变化是什么」。
const SnapshotRetention = 10

// SyncResult 是一次同步的结果。
type SyncResult struct {
	Entries     int  // 当前快照的条目数
	Stored      bool // 新增了一份快照（内容有变化）
	NotModified bool // 上游返回 304
	Unchanged   bool // 上游返回 200，但内容哈希与上一份相同
}

type latestSnapshot struct {
	ID           int64  `db:"id"`
	EntryCount   int    `db:"entry_count"`
	ContentHash  string `db:"content_hash"`
	ETag         string `db:"etag"`
	LastModified string `db:"last_modified"`
}

// Sync 从 alpha-radar 拉一份档案，脱敏后落库。返回条目数。
func (s *Service) Sync(ctx context.Context) (int, error) {
	r, err := s.SyncDetailed(ctx)
	return r.Entries, err
}

// SyncDetailed 同 Sync，但返回是否真的写了新快照。
//
// 去重：上游每小时重新生成一次导出，generated_at 和每条的 judged_at 每次都变，
// 但结论通常不变。这里
//  1. 带上一份的 ETag / Last-Modified 发条件请求，304 直接只刷新 checked_at；
//  2. 200 时对内容算哈希（去掉 generated_at 与 judged_at），和上一份相同也只刷新
//     checked_at / etag，不再插入一份 3 MB 的重复快照。
func (s *Service) SyncDetailed(ctx context.Context) (SyncResult, error) {
	var res SyncResult
	if s.url == "" {
		return res, errors.New("alpharadar url not configured")
	}
	last, hasLast, err := s.latest(ctx)
	if err != nil {
		return res, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, s.url+"/api/falsification?include=insufficient", nil)
	if err != nil {
		return res, err
	}
	req.Header.Set("User-Agent", "finme-backend")
	if hasLast {
		if last.ETag != "" {
			req.Header.Set("If-None-Match", last.ETag)
		}
		if last.LastModified != "" {
			req.Header.Set("If-Modified-Since", last.LastModified)
		}
	}
	resp, err := s.httpc.Do(req)
	if err != nil {
		return res, err
	}
	defer resp.Body.Close()
	now := time.Now().UnixMilli()
	if resp.StatusCode == http.StatusNotModified && hasLast {
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
		if _, err := s.st.DB.ExecContext(ctx,
			`UPDATE falsification_snapshots SET checked_at=? WHERE id=?`, now, last.ID); err != nil {
			return res, fmt.Errorf("touch snapshot: %w", err)
		}
		res.Entries, res.NotModified = last.EntryCount, true
		s.logger.Debug().Int("entries", last.EntryCount).Msg("falsification: upstream not modified")
		return res, nil
	}
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return res, fmt.Errorf("status %d: %s", resp.StatusCode, string(b))
	}
	// 上游是几千条结论，16MB 足够；异常响应不能把内存打满。
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 16<<20))
	if err != nil {
		return res, err
	}
	p, err := Decode(raw)
	if err != nil {
		return res, err
	}
	p = Sanitize(p)
	n := len(Archive(p))
	if n == 0 {
		// 空档案多半是上游出错：保留上一份，不覆盖。
		return res, errors.New("upstream archive empty, keep last snapshot")
	}
	hash, err := ContentHash(p)
	if err != nil {
		return res, err
	}
	etag := resp.Header.Get("ETag")
	lastMod := resp.Header.Get("Last-Modified")
	res.Entries = n

	if hasLast {
		prev := last.ContentHash
		if prev == "" {
			// 0020 之前写入的快照没有哈希：现算一次并回填。
			prev = s.hashOfRow(ctx, last.ID)
		}
		if prev == hash {
			if _, err := s.st.DB.ExecContext(ctx, `
				UPDATE falsification_snapshots
				SET checked_at=?, etag=?, last_modified=?, content_hash=?
				WHERE id=?`, now, etag, lastMod, hash, last.ID); err != nil {
				return res, fmt.Errorf("touch snapshot: %w", err)
			}
			res.Unchanged = true
			s.logger.Debug().Int("entries", n).Msg("falsification: upstream unchanged, snapshot kept")
			return res, nil
		}
	}

	payload, err := json.Marshal(p)
	if err != nil {
		return res, err
	}
	if _, err := s.st.DB.ExecContext(ctx, `
		INSERT INTO falsification_snapshots(generated_at, threshold_version, entry_count, payload_json,
			fetched_at, content_hash, etag, last_modified, checked_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		str(p["generated_at"]), str(p["threshold_version"]), n, string(payload), now,
		hash, etag, lastMod, now); err != nil {
		return res, fmt.Errorf("insert snapshot: %w", err)
	}
	res.Stored = true
	// 这张表回答「最近看到的是什么」，不是历史档案。
	_, _ = s.st.DB.ExecContext(ctx, `
		DELETE FROM falsification_snapshots WHERE id NOT IN (
			SELECT id FROM falsification_snapshots ORDER BY fetched_at DESC, id DESC LIMIT ?)`,
		SnapshotRetention)
	s.invalidate()
	s.logger.Info().Int("entries", n).
		Str("threshold_version", str(p["threshold_version"])).
		Str("hash", hash[:12]).
		Msg("falsification: snapshot synced")
	return res, nil
}

func (s *Service) latest(ctx context.Context) (latestSnapshot, bool, error) {
	var l latestSnapshot
	err := s.st.DB.GetContext(ctx, &l, `
		SELECT id, entry_count, content_hash, etag, last_modified FROM falsification_snapshots
		ORDER BY fetched_at DESC, id DESC LIMIT 1`)
	switch {
	case err == nil:
		return l, true, nil
	case errors.Is(err, sql.ErrNoRows):
		return l, false, nil
	default:
		return l, false, fmt.Errorf("read latest snapshot: %w", err)
	}
}

// hashOfRow 读出一份旧快照并算内容哈希；读不出来返回空串（视为不同）。
func (s *Service) hashOfRow(ctx context.Context, id int64) string {
	var raw string
	if err := s.st.DB.GetContext(ctx, &raw,
		`SELECT payload_json FROM falsification_snapshots WHERE id=?`, id); err != nil {
		return ""
	}
	p, err := Decode([]byte(raw))
	if err != nil {
		return ""
	}
	h, err := ContentHash(Sanitize(p))
	if err != nil {
		return ""
	}
	return h
}

// volatileTop / volatileEntry 是每次重新导出都会变、但不代表结论变化的字段。
var (
	volatileTop   = map[string]bool{"generated_at": true}
	volatileEntry = map[string]bool{"judged_at": true}
)

// ContentHash 对档案内容算 sha256（十六进制），忽略 generated_at 与条目的
// judged_at。encoding/json 对 map 的键排序，结果稳定。不修改入参。
func ContentHash(p Payload) (string, error) {
	top := make(map[string]any, len(p))
	for k, v := range p {
		if !volatileTop[k] {
			top[k] = v
		}
	}
	if raw, ok := p["archive"].([]any); ok {
		arch := make([]any, len(raw))
		for i, e := range raw {
			m, ok := e.(map[string]any)
			if !ok {
				arch[i] = e
				continue
			}
			c := make(map[string]any, len(m))
			for k, v := range m {
				if !volatileEntry[k] {
					c[k] = v
				}
			}
			arch[i] = c
		}
		top["archive"] = arch
	}
	b, err := json.Marshal(top)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:]), nil
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
