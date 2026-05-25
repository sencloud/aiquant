package live

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/realtime"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// maxPickPerSession 一场直播最多分析多少只股票（成本上限：n × 6 personas）。
const maxPickPerSession = 5

// PickResult 是选股结果。Reason 写入 live_sessions.selection_reason 做审计。
type PickResult struct {
	Symbols []Picked
	Reason  string
}

// Picked 是一条入选股票（symbol = 600519.SH）。
type Picked struct {
	Symbol string
	Name   string
	Source string // "龙虎榜净流入" / "实时涨幅榜" / "用户关注"
}

// Picker 实现"选股"策略。
//
//   - 盘前 (PhasePre): 上一交易日龙虎榜净流入 Top3 + 用户关注热度 Top2
//   - 盘中 (PhaseIntraday): 实时涨幅榜 Top3 + 用户关注 Top2
//   - 盘后 (PhasePost): 当日龙虎榜净流入 Top3 + 用户关注 Top2
type Picker struct {
	tu *tushare.Client
	rt *realtime.Client
	wl *WatchlistRepo
}

func NewPicker(tu *tushare.Client, rt *realtime.Client, wl *WatchlistRepo) *Picker {
	return &Picker{tu: tu, rt: rt, wl: wl}
}

// Pick 返回 ≤ maxPickPerSession 个标的（去重，关注列表 cap 2 个）。
func (p *Picker) Pick(ctx context.Context, phase string, now time.Time) (*PickResult, error) {
	var (
		buckets []Picked
		notes   []string
	)

	// ── 1) 主选股池 ────────────────────────────────────────────────
	switch phase {
	case PhasePre:
		// 上一交易日龙虎榜
		d := lastTradeDay(now.AddDate(0, 0, -1))
		rows, err := p.pickTopList(ctx, d, 3)
		if err == nil && len(rows) > 0 {
			buckets = append(buckets, rows...)
			notes = append(notes, fmt.Sprintf("龙虎榜(%s)净流入 Top%d", d, len(rows)))
		}
	case PhasePost:
		d := now.Format("20060102")
		rows, err := p.pickTopList(ctx, d, 3)
		if err == nil && len(rows) > 0 {
			buckets = append(buckets, rows...)
			notes = append(notes, fmt.Sprintf("龙虎榜(%s)净流入 Top%d", d, len(rows)))
		} else {
			// 当日龙虎榜可能 16 点后才出，兜底用昨日
			d2 := lastTradeDay(now.AddDate(0, 0, -1))
			rows, err := p.pickTopList(ctx, d2, 3)
			if err == nil && len(rows) > 0 {
				buckets = append(buckets, rows...)
				notes = append(notes, fmt.Sprintf("龙虎榜(%s)净流入 Top%d", d2, len(rows)))
			}
		}
	default: // intraday
		rows, err := p.pickTopMovers(ctx, 3)
		if err == nil && len(rows) > 0 {
			buckets = append(buckets, rows...)
			notes = append(notes, fmt.Sprintf("实时涨幅榜 Top%d", len(rows)))
		}
	}

	// ── 2) 用户关注（最多 2 只，按关注人次降序） ─────────────────
	if p.wl != nil {
		watchRows, err := p.wl.DistinctSymbols(ctx, 10)
		if err == nil {
			added := 0
			for _, w := range watchRows {
				if added >= 2 {
					break
				}
				if containsSymbol(buckets, w.Symbol) {
					continue
				}
				name := w.SymbolName
				if name == "" {
					name = p.resolveName(ctx, w.Symbol)
				}
				buckets = append(buckets, Picked{Symbol: w.Symbol, Name: name, Source: "用户关注"})
				added++
			}
			if added > 0 {
				notes = append(notes, fmt.Sprintf("用户关注 %d 只", added))
			}
		}
	}

	// 名字兜底（pickTopList 可能拿不到中文名）
	for i := range buckets {
		if strings.TrimSpace(buckets[i].Name) == "" {
			buckets[i].Name = p.resolveName(ctx, buckets[i].Symbol)
		}
	}

	if len(buckets) > maxPickPerSession {
		buckets = buckets[:maxPickPerSession]
	}
	return &PickResult{Symbols: buckets, Reason: strings.Join(notes, " + ")}, nil
}

// PickedSymbolsJSON 把入选结果序列化进 live_sessions.picked_symbols。
func PickedSymbolsJSON(rows []Picked) string {
	type entry struct {
		Symbol string `json:"symbol"`
		Name   string `json:"name"`
		Source string `json:"source"`
	}
	out := make([]entry, 0, len(rows))
	for _, r := range rows {
		out = append(out, entry{Symbol: r.Symbol, Name: r.Name, Source: r.Source})
	}
	b, _ := json.Marshal(out)
	return string(b)
}

// pickTopList 调 Tushare top_list（日度龙虎榜），按 net_amount 降序取 Top n。
func (p *Picker) pickTopList(ctx context.Context, tradeDate string, n int) ([]Picked, error) {
	if p.tu == nil || !p.tu.Configured() {
		return nil, fmt.Errorf("tushare not configured")
	}
	rows, err := p.tu.Query(ctx, "top_list",
		map[string]any{"trade_date": tradeDate},
		[]string{"ts_code", "name", "net_amount", "amount", "reason"})
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, nil
	}
	type rowVal struct {
		ts, name string
		net      float64
	}
	bucket := map[string]*rowVal{} // 一只票多次上榜按净流入 SUM
	for _, r := range rows {
		ts := tushare.AsString(r["ts_code"])
		if ts == "" {
			continue
		}
		if _, ok := bucket[ts]; !ok {
			bucket[ts] = &rowVal{ts: ts, name: tushare.AsString(r["name"])}
		}
		bucket[ts].net += tushare.AsFloat(r["net_amount"])
	}
	vals := make([]*rowVal, 0, len(bucket))
	for _, v := range bucket {
		vals = append(vals, v)
	}
	sort.Slice(vals, func(i, j int) bool { return vals[i].net > vals[j].net })
	if len(vals) > n {
		vals = vals[:n]
	}
	out := make([]Picked, 0, len(vals))
	for _, v := range vals {
		out = append(out, Picked{
			Symbol: v.ts,
			Name:   v.name,
			Source: "龙虎榜净流入",
		})
	}
	return out, nil
}

// pickTopMovers 实时涨幅榜（盘中场次用）。
func (p *Picker) pickTopMovers(ctx context.Context, n int) ([]Picked, error) {
	if p.rt == nil {
		return nil, fmt.Errorf("realtime client nil")
	}
	rows, err := p.rt.FetchTopMovers(ctx, realtime.MoversOptions{
		Direction: "up",
		Scope:     "a",
		Limit:     n,
	})
	if err != nil {
		return nil, err
	}
	out := make([]Picked, 0, len(rows))
	for _, r := range rows {
		ts := strings.ToUpper(r.TsCode)
		if ts == "" {
			ts = r.Code
		}
		out = append(out, Picked{
			Symbol: ts,
			Name:   r.Name,
			Source: "实时涨幅榜",
		})
	}
	return out, nil
}

// resolveName 缓存查 stock_basic 拿中文名（容错：失败返回空）。
func (p *Picker) resolveName(ctx context.Context, symbol string) string {
	if p.tu == nil || !p.tu.Configured() {
		return ""
	}
	all, err := p.tu.StockBasic(ctx)
	if err != nil {
		return ""
	}
	target := strings.ToUpper(strings.TrimSpace(symbol))
	for _, ins := range all {
		if strings.ToUpper(ins.TsCode) == target {
			return ins.Name
		}
	}
	return ""
}

// containsSymbol 判断已选列表里是否已经有这只票（去重）。
func containsSymbol(picks []Picked, s string) bool {
	t := strings.ToUpper(strings.TrimSpace(s))
	for _, p := range picks {
		if strings.ToUpper(p.Symbol) == t {
			return true
		}
	}
	return false
}

// lastTradeDay 简化：直接返回 t 日期（"20060102"）；跳过周末（周六→周五，
// 周日→周五）。节假日通过 Tushare top_list 返回空数据兜底，不在此处理。
func lastTradeDay(t time.Time) string {
	switch t.Weekday() {
	case time.Sunday:
		t = t.AddDate(0, 0, -2)
	case time.Saturday:
		t = t.AddDate(0, 0, -1)
	}
	return t.Format("20060102")
}
