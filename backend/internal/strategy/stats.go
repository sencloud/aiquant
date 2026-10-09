package strategy

import (
	"context"
	"encoding/json"
	"math"
	"sync"
	"time"
)

// maxSeriesPoints 是净值曲线降采样后的点数：够看趋势，又不至于让接口变大。
const maxSeriesPoints = 220

// shanghai 是策略口径使用的时间区（数据源全部按上海时间）。
var shanghai = func() *time.Location {
	loc, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		return time.FixedZone("CST", 8*3600)
	}
	return loc
}()

// calendarCache 缓存一段区间的交易日，避免每次刷新都打 Tushare。
type calendarCache struct {
	mu   sync.Mutex
	key  string
	at   time.Time
	open map[string]bool
}

func newCalendarCache() *calendarCache { return &calendarCache{} }

func (c *calendarCache) get(key string) (map[string]bool, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.open != nil && c.key == key && time.Since(c.at) < time.Hour {
		return c.open, true
	}
	return nil, false
}

func (c *calendarCache) put(key string, open map[string]bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.key, c.open, c.at = key, open, time.Now()
}

// staleness 判断 dataAsOf 是否落后于最近一个交易日，返回(是否过期, 落后几个交易日)。
//
// 用 Tushare 交易日历（缓存 1 小时）；日历取不到时退化为"数工作日"——宁可宽松，
// 也不要因为日历不可用就把新鲜数据误标成过期。
func (s *Service) staleness(ctx context.Context, dataAsOf string, now time.Time) (bool, int) {
	if dataAsOf == "" {
		return true, 0
	}
	day, err := time.ParseInLocation("2006-01-02", dataAsOf, shanghai)
	if err != nil {
		return true, 0
	}
	today := now.In(shanghai)
	end := time.Date(today.Year(), today.Month(), today.Day(), 0, 0, 0, 0, shanghai)
	// 当天 15:00 前，今天本来就不该有数据，不算落后。
	if isWeekday(end) && today.Hour() < 15 {
		end = end.AddDate(0, 0, -1)
	}
	if !end.After(day) {
		return false, 0
	}
	if open := s.openDays(ctx, day.AddDate(0, 0, 1), end); open != nil {
		return len(open) > 0, len(open)
	}
	n := 0
	for d := day.AddDate(0, 0, 1); !d.After(end); d = d.AddDate(0, 0, 1) {
		if isWeekday(d) {
			n++
		}
	}
	return n > 0, n
}

// openDays 返回 [from, to] 区间内的交易日日期；日历不可用时返回 nil。
func (s *Service) openDays(ctx context.Context, from, to time.Time) []string {
	if s.tu == nil || !s.tu.Configured() {
		return nil
	}
	startStr, endStr := from.Format("20060102"), to.Format("20060102")
	key := startStr + ":" + endStr
	if open, ok := s.cal.get(key); ok {
		return keysOf(open)
	}
	rows, err := s.tu.Query(ctx, "trade_cal", map[string]any{
		"exchange":   "SSE",
		"start_date": startStr,
		"end_date":   endStr,
		"is_open":    "1",
	}, []string{"cal_date"})
	if err != nil {
		s.logger.Debug().Err(err).Msg("strategy: trade_cal unavailable, fallback to weekday counting")
		return nil
	}
	open := map[string]bool{}
	for _, r := range rows {
		if v, ok := r["cal_date"].(string); ok && v != "" {
			open[v] = true
		}
	}
	s.cal.put(key, open)
	return keysOf(open)
}

func keysOf(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

func isWeekday(t time.Time) bool {
	wd := t.Weekday()
	return wd != time.Saturday && wd != time.Sunday
}

func laterDate(a, b string) string {
	if b > a {
		return b
	}
	return a
}

func sameCodeSet(a, b map[string]bool) bool {
	if len(a) != len(b) {
		return false
	}
	for k := range a {
		if !b[k] {
			return false
		}
	}
	return true
}

// toPair / pairDate 解析外部传的 [日期, 数值] 二元组。
func toPair(row []any) float64 {
	if len(row) < 2 {
		return 0
	}
	switch v := row[1].(type) {
	case float64:
		return v
	case json.Number:
		f, _ := v.Float64()
		return f
	}
	return 0
}

func pairDate(row []any) string {
	if len(row) < 1 {
		return ""
	}
	if s, ok := row[0].(string); ok {
		return s
	}
	return ""
}

// downsample 把净值序列按等间隔抽样到 maxSeriesPoints 个点，并带上同日基准值。
func downsample(equity, bench [][]any) []CurvePoint {
	if len(equity) == 0 {
		return nil
	}
	step := 1
	if len(equity) > maxSeriesPoints {
		step = len(equity) / maxSeriesPoints
	}
	benchByDate := map[string]float64{}
	for _, r := range bench {
		benchByDate[pairDate(r)] = toPair(r)
	}
	out := make([]CurvePoint, 0, maxSeriesPoints+2)
	for i := 0; i < len(equity); i += step {
		d := pairDate(equity[i])
		out = append(out, CurvePoint{Date: d, Equity: toPair(equity[i]), Bench: benchByDate[d]})
	}
	last := len(equity) - 1
	if out[len(out)-1].Date != pairDate(equity[last]) {
		d := pairDate(equity[last])
		out = append(out, CurvePoint{Date: d, Equity: toPair(equity[last]), Bench: benchByDate[d]})
	}
	return out
}

func yearsBetween(from, to string) float64 {
	f, err1 := time.ParseInLocation("2006-01-02", from, shanghai)
	t, err2 := time.ParseInLocation("2006-01-02", to, shanghai)
	if err1 != nil || err2 != nil {
		return 0
	}
	return t.Sub(f).Hours() / 24 / 365.25
}

func annualize(total, years float64) float64 {
	if years <= 0 || total <= -1 {
		return 0
	}
	return math.Pow(1+total, 1/years) - 1
}
