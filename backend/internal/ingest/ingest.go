// Package ingest 接收「本机采集端」推上来的行情。
//
// 为什么需要它：阿里云出口拿不到内盘期货实时（东财 push2 系 TLS unexpected eof、
// 新浪 hq.sinajs.cn 对数据中心 IP 返回 403、腾讯/雪球/金十都不提供内盘期货）。
// 而用户本机可以直连新浪拿到主力连续合约的实时价（实测 nf_RB0 / nf_I0 / nf_M0 等
// 12 个品种全部可用）。所以做法是：本机跑一个小采集端，定时把行情推给服务端，
// 服务端缓存最新一份并让工具优先读它——这是标准的 RPA 中转，不依赖本机开公网端口。
package ingest

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"sync"
	"time"

	"github.com/jmoiron/sqlx"

	"github.com/sencloud/finme-backend/internal/store"
)

// Quote 是采集端推上来的一条行情。字段与工具输出保持同构，便于直接透传。
type Quote struct {
	Symbol   string  `json:"symbol"` // 规范代码，如 RB2601.SHF / RB.SHF（主力连续）
	Name     string  `json:"name"`   // 中文名（螺纹钢连续）
	Last     float64 `json:"last"`
	PctChg   float64 `json:"pct_chg"`
	Change   float64 `json:"change"`
	Open     float64 `json:"open"`
	High     float64 `json:"high"`
	Low      float64 `json:"low"`
	PreClose float64 `json:"pre_close"`
	Volume   float64 `json:"volume,omitempty"`
	OI       float64 `json:"oi,omitempty"`
	// Ts 是采集端看到这条行情的时间（unix ms，采集端本地时钟）。
	Ts int64 `json:"ts"`
}

// Entry 是缓存里的一条记录：行情 + 服务端收到的时刻。
type Entry struct {
	Quote      Quote
	ReceivedAt time.Time
}

// Registry 是「本机采集端」推上来的行情缓存。单进程内存态即可：
// 采集端每 15 秒推一次，进程重启后几秒内就会重新填满。
type Registry struct {
	mu   sync.RWMutex
	data map[string]Entry
	st   *store.Store
}

// NewRegistry 构造缓存。st 为 nil 时退化为纯内存（测试用）；生产传 store，
// 这样 api 与 scheduler 两个进程能读到同一份行情。
func NewRegistry(st *store.Store) *Registry {
	return &Registry{data: map[string]Entry{}, st: st}
}

// 进程内默认实例：工具层与 HTTP 层共用同一个缓存，避免各处各建一份。
var def = NewRegistry(nil)

// SetDefault 在启动装配阶段注入带 store 的实例。
func SetDefault(r *Registry) {
	if r != nil {
		def = r
	}
}

// Default 返回进程内共用的缓存。
func Default() *Registry { return def }

// Put 写入一批行情；返回接受条数（空 symbol 会被丢弃）。
func (r *Registry) Put(quotes []Quote) int {
	now := time.Now()
	r.mu.Lock()
	defer r.mu.Unlock()
	n := 0
	var rows [][3]any
	for _, q := range quotes {
		if q.Symbol == "" {
			continue
		}
		r.data[q.Symbol] = Entry{Quote: q, ReceivedAt: now}
		if raw, err := json.Marshal(q); err == nil {
			rows = append(rows, [3]any{q.Symbol, string(raw), now.UnixMilli()})
		}
		n++
	}
	// 落库失败不影响本次推送的可用性：内存里已经有了。
	if r.st != nil && len(rows) > 0 {
		_ = r.st.Tx(context.Background(), func(tx *sqlx.Tx) error {
			for _, row := range rows {
				if _, err := tx.ExecContext(context.Background(), `
					INSERT INTO ingest_quotes(symbol, payload_json, received_at)
					VALUES(?, ?, ?)
					ON CONFLICT(symbol) DO UPDATE SET
						payload_json=excluded.payload_json,
						received_at=excluded.received_at`,
					row[0], row[1], row[2]); err != nil {
					return err
				}
			}
			return nil
		})
	}
	return n
}

// Get 取一条新鲜行情；超过 maxAge 视为过期（宁可回退到别的源，也别把几分钟前的
// 价格当实时价发给模型）。
func (r *Registry) Get(symbol string, maxAge time.Duration) (Entry, bool) {
	r.mu.RLock()
	e, ok := r.data[symbol]
	r.mu.RUnlock()
	if ok && (maxAge <= 0 || time.Since(e.ReceivedAt) <= maxAge) {
		return e, true
	}
	// 内存里没有（例如 scheduler 进程）→ 读库。
	if r.st == nil {
		return Entry{}, false
	}
	var raw string
	var at int64
	err := r.st.DB.QueryRowContext(context.Background(),
		`SELECT payload_json, received_at FROM ingest_quotes WHERE symbol=?`, symbol).
		Scan(&raw, &at)
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return Entry{}, false
		}
		return Entry{}, false
	}
	received := time.UnixMilli(at)
	if maxAge > 0 && time.Since(received) > maxAge {
		return Entry{}, false
	}
	var q Quote
	if err := json.Unmarshal([]byte(raw), &q); err != nil {
		return Entry{}, false
	}
	// 回填内存，避免每次查询都打库。
	r.mu.Lock()
	r.data[symbol] = Entry{Quote: q, ReceivedAt: received}
	r.mu.Unlock()
	return Entry{Quote: q, ReceivedAt: received}, true
}

// Stats 返回缓存规模与最新一条的接收时刻，供运维查看采集端是否还活着。
func (r *Registry) Stats() (int, time.Time) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	var latest time.Time
	for _, e := range r.data {
		if e.ReceivedAt.After(latest) {
			latest = e.ReceivedAt
		}
	}
	return len(r.data), latest
}
