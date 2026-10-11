package fishing

import (
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/weather"
)

// 出钓指数（基础版）：五个因子线性相加，满分 100，公式全部公开。
//
//	气压趋势 30 + 风 20 + 气温 20 + 降水 20 + 月相 10
//
// 每个因子给出原始值、得分和一句解释，客户端原样展示，用户能看出分是怎么来的。
// 这是经验规则而不是预测模型：鱼口受水温、水色、钓点、钓法影响更大，指数只
// 回答「天气这关过不过得去」。
const (
	MaxPressure = 30
	MaxWind     = 20
	MaxTemp     = 20
	MaxPrecip   = 20
	MaxMoon     = 10
)

// FormulaText 给客户端 / AI 展示的计分说明。
const FormulaText = "出钓指数 = 气压趋势(30) + 风(20) + 气温(20) + 降水(20) + 月相(10)。" +
	"气压：24 小时变化 ≤2hPa 满分，缓升 24、缓降 18、剧变(>5hPa) 8，均值 <1000 或 >1028hPa 再扣分；" +
	"风：白天平均 1–5m/s 满分，<1 为 14，5–8 为 12，>8 为 4；" +
	"气温：白天平均 15–28℃ 满分，10–15/28–32℃ 14，5–10/32–35℃ 8，其余 3，较前一天骤变 >6℃ 扣 5；" +
	"降水：全天 0–2mm 小雨 20、无雨 16、2–10mm 12、10–25mm 5、>25mm 0；" +
	"月相：新月 / 满月前后 2 天 10，上下弦前后 2 天 6，其余 8（民间经验，权重最低）。" +
	"≥80 很适合，65–79 适合，50–64 一般，<50 不太适合。"

// Factor 是一个计分因子。
type Factor struct {
	Key   string `json:"key"`   // pressure / wind / temp / precip / moon
	Name  string `json:"name"`  // 中文名
	Value string `json:"value"` // 原始值摘要，例如「1016hPa，24h +1.2」
	Score int    `json:"score"`
	Max   int    `json:"max"`
	Note  string `json:"note"`
}

// Window 是推荐时段（当地时间）。
type Window struct {
	From  string `json:"from"` // HH:MM
	To    string `json:"to"`
	Label string `json:"label"` // 清晨 / 傍晚
}

// DayScore 是某一天的出钓指数。
type DayScore struct {
	Date      string   `json:"date"`
	Score     int      `json:"score"`
	Level     string   `json:"level"`
	Summary   string   `json:"summary"`
	Factors   []Factor `json:"factors"`
	Windows   []Window `json:"windows"`
	Warnings  []string `json:"warnings,omitempty"`
	Moon      MoonInfo `json:"moon"`
	Sunrise   string   `json:"sunrise,omitempty"`
	Sunset    string   `json:"sunset,omitempty"`
	TempMin   float64  `json:"temp_min"`
	TempMax   float64  `json:"temp_max"`
	PrecipSum float64  `json:"precip_sum"`
	WindMax   float64  `json:"wind_max"`
	Pressure  float64  `json:"pressure"` // 白天平均海平面气压（0 = 无数据）
}

// Level 把分数映射成档位。
func Level(score int) string {
	switch {
	case score >= 80:
		return "很适合"
	case score >= 65:
		return "适合"
	case score >= 50:
		return "一般"
	default:
		return "不太适合"
	}
}

type dayHours struct {
	date  string
	all   []weather.Hour
	light []weather.Hour // 05:00–19:59
}

func groupByDay(hrs []weather.Hour) (map[string]*dayHours, []string) {
	m := map[string]*dayHours{}
	var order []string
	for _, h := range hrs {
		if len(h.Time) < 13 {
			continue
		}
		d := h.Time[:10]
		g := m[d]
		if g == nil {
			g = &dayHours{date: d}
			m[d] = g
			order = append(order, d)
		}
		g.all = append(g.all, h)
		hh := atoi2(h.Time[11:13])
		if hh >= 5 && hh <= 19 {
			g.light = append(g.light, h)
		}
	}
	sort.Strings(order)
	return m, order
}

func atoi2(s string) int {
	if len(s) < 2 {
		return -1
	}
	return int(s[0]-'0')*10 + int(s[1]-'0')
}

func mean(hs []weather.Hour, f func(weather.Hour) float64, skipZero bool) (float64, bool) {
	sum, n := 0.0, 0
	for _, h := range hs {
		v := f(h)
		if skipZero && v == 0 {
			continue
		}
		sum += v
		n++
	}
	if n == 0 {
		return 0, false
	}
	return sum / float64(n), true
}

func hourAt(hs []weather.Hour, hh int) (weather.Hour, bool) {
	for _, h := range hs {
		if atoi2(h.Time[11:13]) == hh {
			return h, true
		}
	}
	return weather.Hour{}, false
}

// ScoreDays 对逐小时序列里「今天及以后」的每一天打分（最多 days 天）。
// lat/lon 用于日出日落；utcOffset 是当地时区偏移（秒）。
func ScoreDays(hr *weather.Hourly, lat, lon float64, days int) []DayScore {
	if hr == nil {
		return nil
	}
	byDay, order := groupByDay(hr.Hours)
	loc := time.FixedZone("local", hr.UTCOffset)
	var out []DayScore
	var prev *dayHours
	for _, d := range order {
		g := byDay[d]
		if d < hr.Today || len(g.light) < 6 {
			prev = g
			continue
		}
		if len(out) >= days {
			break
		}
		out = append(out, scoreDay(g, prev, lat, lon, loc))
		prev = g
	}
	return out
}

func scoreDay(g, prev *dayHours, lat, lon float64, loc *time.Location) DayScore {
	ds := DayScore{Date: g.date}
	var warnings []string

	// ── 气压趋势 ──
	pf := Factor{Key: "pressure", Name: "气压", Max: MaxPressure}
	pMean, pOK := mean(g.light, func(h weather.Hour) float64 { return h.Pressure }, true)
	if !pOK {
		pf.Score, pf.Value, pf.Note = MaxPressure/2, "无数据", "气压数据缺失，按中性计分"
	} else {
		ds.Pressure = math.Round(pMean*10) / 10
		var delta float64
		var haveDelta bool
		if prev != nil {
			a, okA := hourAt(prev.all, 12)
			b, okB := hourAt(g.all, 12)
			if okA && okB && a.Pressure > 0 && b.Pressure > 0 {
				delta, haveDelta = b.Pressure-a.Pressure, true
			}
		}
		if !haveDelta && len(g.all) >= 2 {
			first, last := g.all[0].Pressure, g.all[len(g.all)-1].Pressure
			if first > 0 && last > 0 {
				delta, haveDelta = last-first, true
			}
		}
		pf.Value = fmt.Sprintf("%.0fhPa", pMean)
		if haveDelta {
			pf.Value += fmt.Sprintf("，24h %+.1f", delta)
		}
		switch {
		case !haveDelta || math.Abs(delta) <= 2:
			pf.Score, pf.Note = 30, "气压平稳，鱼情稳定"
		case delta > 2 && delta <= 5:
			pf.Score, pf.Note = 24, "气压缓升，天气转好，鱼口逐步恢复"
		case delta < -2 && delta >= -5:
			pf.Score, pf.Note = 18, "气压缓降，变天前可能有一波口，之后转差"
		default:
			pf.Score, pf.Note = 8, "气压剧变，鱼不爱开口"
		}
		if pMean < 1000 {
			pf.Score -= 4
			pf.Note += "；低压偏闷，水中溶氧偏低"
		} else if pMean > 1028 {
			pf.Score -= 3
			pf.Note += "；高压偏高"
		}
		pf.Score = clamp(pf.Score, 0, MaxPressure)
	}

	// ── 风 ──
	wf := Factor{Key: "wind", Name: "风", Max: MaxWind}
	wMean, _ := mean(g.light, func(h weather.Hour) float64 { return h.Wind }, false)
	gustMax, windMax := 0.0, 0.0
	for _, h := range g.light {
		gustMax = math.Max(gustMax, h.Gust)
		windMax = math.Max(windMax, h.Wind)
	}
	ds.WindMax = math.Round(windMax*10) / 10
	wf.Value = fmt.Sprintf("白天平均 %.1fm/s", wMean)
	switch {
	case wMean < 1:
		wf.Score, wf.Note = 14, "几乎无风，水面如镜，鱼警惕"
	case wMean <= 5:
		wf.Score, wf.Note = 20, "微风起涟漪，增氧又遮光"
	case wMean <= 8:
		wf.Score, wf.Note = 12, "风偏大，抛投控漂吃力，可找背风处"
	default:
		wf.Score, wf.Note = 4, "大风，不建议出钓"
	}
	if gustMax >= 13.9 {
		warnings = append(warnings, fmt.Sprintf("阵风 %.0fm/s（7 级以上），注意安全，远离高处和水边陡坡", gustMax))
	}

	// ── 气温 ──
	tf := Factor{Key: "temp", Name: "气温", Max: MaxTemp}
	tMean, _ := mean(g.light, func(h weather.Hour) float64 { return h.Temp }, false)
	tMin, tMax := math.Inf(1), math.Inf(-1)
	for _, h := range g.all {
		tMin, tMax = math.Min(tMin, h.Temp), math.Max(tMax, h.Temp)
	}
	ds.TempMin, ds.TempMax = math.Round(tMin*10)/10, math.Round(tMax*10)/10
	tf.Value = fmt.Sprintf("白天平均 %.0f℃", tMean)
	switch {
	case tMean >= 15 && tMean <= 28:
		tf.Score, tf.Note = 20, "水温适宜，鱼活跃"
	case (tMean >= 10 && tMean < 15) || (tMean > 28 && tMean <= 32):
		tf.Score, tf.Note = 14, "温度偏离舒适区，鱼口一般"
	case (tMean >= 5 && tMean < 10) || (tMean > 32 && tMean <= 35):
		tf.Score, tf.Note = 8, "偏冷 / 偏热，找深水或阴凉处"
	default:
		tf.Score, tf.Note = 3, "极端温度，鱼基本不开口"
	}
	if prev != nil && len(prev.light) > 0 {
		if pt, ok := mean(prev.light, func(h weather.Hour) float64 { return h.Temp }, false); ok {
			if dt := tMean - pt; math.Abs(dt) > 6 {
				tf.Score -= 5
				tf.Value += fmt.Sprintf("，较前一天 %+.0f℃", dt)
				tf.Note += "；气温骤变，鱼需要时间适应"
			}
		}
	}
	tf.Score = clamp(tf.Score, 0, MaxTemp)

	// ── 降水 ──
	rf := Factor{Key: "precip", Name: "降水", Max: MaxPrecip}
	pSum, pHourMax := 0.0, 0.0
	for _, h := range g.all {
		pSum += h.Precip
		pHourMax = math.Max(pHourMax, h.Precip)
	}
	ds.PrecipSum = math.Round(pSum*10) / 10
	rf.Value = fmt.Sprintf("全天 %.1fmm", pSum)
	switch {
	case pSum < 0.1:
		rf.Score, rf.Note = 16, "无雨"
	case pSum <= 2:
		rf.Score, rf.Note = 20, "小雨增氧，常有好口"
	case pSum <= 10:
		rf.Score, rf.Note = 12, "中雨，注意避雨和路滑"
	case pSum <= 25:
		rf.Score, rf.Note = 5, "大雨，水浑、入水口可能有机会但不安全"
	default:
		rf.Score, rf.Note = 0, "暴雨，不建议出钓"
	}
	if pSum > 25 || pHourMax >= 8 {
		warnings = append(warnings, "强降水：远离河道、溪沟和水库泄洪区，雷雨天收竿")
	}

	// ── 月相 ──
	noonLocal, _ := time.ParseInLocation("2006-01-02 15:04", g.date+" 12:00", loc)
	mi := Moon(noonLocal)
	ds.Moon = mi
	mf := Factor{Key: "moon", Name: "月相", Max: MaxMoon,
		Value: fmt.Sprintf("%s（月龄 %.1f 天）", mi.Phase, mi.Age)}
	full := SynodicMonth / 2
	nearNewFull := mi.Age <= 2 || mi.Age >= SynodicMonth-2 || math.Abs(mi.Age-full) <= 2
	nearQuarter := math.Abs(mi.Age-SynodicMonth/4) <= 2 || math.Abs(mi.Age-3*SynodicMonth/4) <= 2
	switch {
	case nearNewFull:
		mf.Score, mf.Note = 10, "新月 / 满月前后，民间认为鱼索饵积极（参考权重低）"
	case nearQuarter:
		mf.Score, mf.Note = 6, "上下弦前后，民间认为鱼口偏弱（参考权重低）"
	default:
		mf.Score, mf.Note = 8, "月相中性（参考权重低）"
	}

	ds.Factors = []Factor{pf, wf, tf, rf, mf}
	for _, f := range ds.Factors {
		ds.Score += f.Score
	}
	ds.Level = Level(ds.Score)

	// ── 推荐时段：日出前后、日落前后，剔除大雨 / 大风的小时 ──
	if rise, set, ok := SunTimes(noonLocal, lat, lon); ok {
		r, s := rise.In(loc), set.In(loc)
		ds.Sunrise, ds.Sunset = r.Format("15:04"), s.Format("15:04")
		cand := []Window{
			{From: r.Add(-30 * time.Minute).Format("15:04"), To: r.Add(2 * time.Hour).Format("15:04"), Label: "清晨"},
			{From: s.Add(-2 * time.Hour).Format("15:04"), To: s.Add(30 * time.Minute).Format("15:04"), Label: "傍晚"},
		}
		for _, w := range cand {
			if windowBad(g.all, w) {
				continue
			}
			ds.Windows = append(ds.Windows, w)
		}
	}
	ds.Warnings = warnings
	ds.Summary = summarize(ds)
	return ds
}

// windowBad：时段内任一小时降水 >2mm 或风 >8m/s 就不推荐。
func windowBad(hs []weather.Hour, w Window) bool {
	from, to := atoi2(w.From[:2]), atoi2(w.To[:2])
	for _, h := range hs {
		hh := atoi2(h.Time[11:13])
		if hh < from || hh > to {
			continue
		}
		if h.Precip > 2 || h.Wind > 8 {
			return true
		}
	}
	return false
}

func summarize(ds DayScore) string {
	// 拿得分率最低和最高的因子各说一句。
	best, worst := ds.Factors[0], ds.Factors[0]
	for _, f := range ds.Factors[:4] { // 月相不参与总结
		if float64(f.Score)/float64(f.Max) > float64(best.Score)/float64(best.Max) {
			best = f
		}
		if float64(f.Score)/float64(f.Max) < float64(worst.Score)/float64(worst.Max) {
			worst = f
		}
	}
	parts := []string{ds.Level}
	if best.Key != worst.Key && float64(worst.Score)/float64(worst.Max) < 0.7 {
		parts = append(parts, firstClause(best.Note), "但"+firstClause(worst.Note))
	} else {
		parts = append(parts, firstClause(best.Note))
	}
	if len(ds.Windows) > 0 {
		var ls []string
		for _, w := range ds.Windows {
			ls = append(ls, w.Label)
		}
		parts = append(parts, strings.Join(ls, "和")+"是好时段")
	}
	return ds.Level + "：" + strings.Join(parts[1:], "，")
}

func firstClause(s string) string {
	for _, sep := range []string{"；", "，"} {
		if i := strings.Index(s, sep); i > 0 {
			return s[:i]
		}
	}
	return s
}

func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
