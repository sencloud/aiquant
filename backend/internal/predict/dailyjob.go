package predict

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"strconv"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/ai/realtime"
	"github.com/sencloud/finme-backend/internal/ai/weather"
)

// DailyConfig 每日出题参数。
type DailyConfig struct {
	Hour     int           // 每日出题触发的本地小时(到点后才生成当天盘口)
	Interval time.Duration // 调度周期(到点前空跑)
}

// DailyMarketJob 是 scheduler 的周期任务：每天在 Hour 后用模板 + 实时行情/天气
// 自动生成当天的新盘口，全部可自动结算，零人工成本。
//
// 幂等：每个模板按 dedup_key(daily:<cat>:<symbol>:<date>) 唯一约束，
// 同一天重复执行只会命中 ErrDuplicateMarket 而不会重复建市场。
type DailyMarketJob struct {
	svc    *Service
	rt     *realtime.Client
	wx     *weather.Client
	cfg    DailyConfig
	logger *zerolog.Logger
}

func NewDailyMarketJob(svc *Service, rt *realtime.Client, wx *weather.Client, cfg DailyConfig, l *zerolog.Logger) *DailyMarketJob {
	if cfg.Interval <= 0 {
		cfg.Interval = 30 * time.Minute
	}
	return &DailyMarketJob{svc: svc, rt: rt, wx: wx, cfg: cfg, logger: l}
}

func (j *DailyMarketJob) Name() string            { return "predict_daily_markets" }
func (j *DailyMarketJob) Interval() time.Duration { return j.cfg.Interval }

func (j *DailyMarketJob) Run(ctx context.Context) error {
	now := time.Now()
	if now.Hour() < j.cfg.Hour {
		return nil
	}
	created := 0
	created += j.genFinance(ctx, now)
	created += j.genWeather(ctx, now)
	if created > 0 {
		j.logger.Info().Int("created", created).Msg("predict daily: new markets created")
	}
	return nil
}

// ── 金融模板 ───────────────────────────────────────────────────────────

type finTemplate struct {
	Source string // cn / us / global_index / forex
	Symbol string
	Name   string
	Unit   string
	Sub    string // 子分类：index / stock / forex
}

var financeTemplates = []finTemplate{
	{"cn", "000300.SH", "沪深300指数", "点", SubFinIndex},
	{"cn", "000001.SH", "上证指数", "点", SubFinIndex},
	{"cn", "399006.SZ", "创业板指", "点", SubFinIndex},
	{"global_index", "纳斯达克", "纳斯达克100", "点", SubFinIndex},
	{"us", "AAPL", "苹果", "美元", SubFinStock},
	{"us", "NVDA", "英伟达", "美元", SubFinStock},
	{"forex", "USDCNH", "离岸人民币", "", SubFinForex},
}

func (j *DailyMarketJob) genFinance(ctx context.Context, now time.Time) int {
	date := now.Format("2006-01-02")
	closeAt := atOffset(now, 0, 20, 0)  // 今日 20:00 停止下注
	resolveAt := atOffset(now, 0, 23, 30) // 今日 23:30 取价结算
	if closeAt <= now.UnixMilli() {
		return 0 // 已过下注窗口(如进程晚上才启动)，留待次日
	}
	created := 0
	for _, t := range financeTemplates {
		price, err := j.fetchPrice(ctx, t.Source, t.Symbol)
		if err != nil || price <= 0 {
			j.logger.Debug().Err(err).Str("symbol", t.Symbol).Msg("predict daily: skip finance (no price)")
			continue
		}
		threshold := niceThreshold(price)
		rule := ResolveRule{
			Source: t.Source, Symbol: t.Symbol, Op: "gte", Value: threshold,
			YesIdx: 0, NoIdx: 1,
		}
		thStr := fmtNum(threshold)
		in := CreateMarketInput{
			Category:    CategoryFinance,
			SubCategory: t.Sub,
			Title:       fmt.Sprintf("今日%s能否突破 %s%s？", t.Name, thStr, t.Unit),
			Description: fmt.Sprintf("出题时现价约 %s%s。收盘后按实时行情自动结算。", fmtNum(price), t.Unit),
			CloseAt:     closeAt,
			ResolveAt:   resolveAt,
			ResolveKind: ResolveAuto,
			ResolveRule: mustJSON(rule),
			Options:     []string{"突破（≥" + thStr + "）", "不突破"},
			DedupKey:    "daily:finance:" + t.Symbol + ":" + date,
		}
		if j.create(ctx, in) {
			created++
		}
	}
	return created
}

// ── 天气模板 ───────────────────────────────────────────────────────────

// 每日出题的天气位置：以大宗商品产区为主（天气直接影响产量/期价），
// 末尾保留少量城市丰富玩法。子分类(city/grain/soft)取自 weather.City.Sub。
var weatherDailyKeys = []string{
	"us_corn_belt", "brazil_soy_mt", "us_wheat_kansas", // 谷物油籽
	"brazil_coffee_mg", "ivorycoast_cocoa", // 软商品
	"beijing", "shanghai", // 城市
}

func (j *DailyMarketJob) genWeather(ctx context.Context, now time.Time) int {
	if j.wx == nil {
		return 0
	}
	target := now.AddDate(0, 0, 1).Format("2006-01-02")
	closeAt := atOffset(now, 0, 22, 0)  // 今日 22:00 停止下注
	resolveAt := atOffset(now, 2, 1, 0) // 后天 01:00 取目标日实况结算
	if closeAt <= now.UnixMilli() {
		return 0
	}
	created := 0
	for _, key := range weatherDailyKeys {
		city, ok := weather.CityByKey(key)
		if !ok {
			continue
		}
		daily, err := j.wx.FetchDaily(ctx, city.Lat, city.Lon)
		if err != nil {
			j.logger.Debug().Err(err).Str("loc", key).Msg("predict daily: skip weather (no forecast)")
			continue
		}
		d, ok := daily[target]
		if !ok {
			continue
		}
		// 产区盘口在标题里点出关联作物，强化"天气→大宗商品"叙事。
		cropSuffix := ""
		if city.Crop != "" {
			cropSuffix = "（" + city.Crop + "产区）"
		}

		// 最高温盘口：阈值取预报值四舍五入，使结果接近 50/50。
		th := math.Round(d.TMax)
		tmaxRule := ResolveRule{
			Source: "weather", City: key, Date: target, Metric: weather.MetricTMax,
			Op: "gte", Value: th, YesIdx: 0, NoIdx: 1,
		}
		thStr := strconv.FormatFloat(th, 'f', 0, 64)
		j.create(ctx, CreateMarketInput{
			Category:    CategoryWeather,
			SubCategory: city.Sub,
			Title:       fmt.Sprintf("明日%s%s最高气温能否达到 %s℃？", city.Name, cropSuffix, thStr),
			Description: fmt.Sprintf("目标日 %s，最高气温实况由 Open-Meteo 自动判定。", target),
			CloseAt:     closeAt,
			ResolveAt:   resolveAt,
			ResolveKind: ResolveAuto,
			ResolveRule: mustJSON(tmaxRule),
			Options:     []string{"≥ " + thStr + "℃", "< " + thStr + "℃"},
			DedupKey:    "daily:weather:tmax:" + key + ":" + target,
		})
		created++

		// 降水盘口：日降水量 > 0.1mm 视为下雨。
		rainRule := ResolveRule{
			Source: "weather", City: key, Date: target, Metric: weather.MetricPrecip,
			Op: "gt", Value: 0.1, YesIdx: 0, NoIdx: 1,
		}
		j.create(ctx, CreateMarketInput{
			Category:    CategoryWeather,
			SubCategory: city.Sub,
			Title:       fmt.Sprintf("明日%s%s会下雨吗？", city.Name, cropSuffix),
			Description: fmt.Sprintf("目标日 %s，按 Open-Meteo 日降水量(>0.1mm 视为下雨)自动判定。", target),
			CloseAt:     closeAt,
			ResolveAt:   resolveAt,
			ResolveKind: ResolveAuto,
			ResolveRule: mustJSON(rainRule),
			Options:     []string{"会下雨", "不下雨"},
			DedupKey:    "daily:weather:rain:" + key + ":" + target,
		})
		created++
	}
	return created
}

// ── 公共 ───────────────────────────────────────────────────────────────

func (j *DailyMarketJob) create(ctx context.Context, in CreateMarketInput) bool {
	_, err := j.svc.CreateMarket(ctx, in)
	if err == nil {
		return true
	}
	if errors.Is(err, ErrDuplicateMarket) {
		return false // 今天已建过，正常幂等命中
	}
	j.logger.Error().Err(err).Str("title", in.Title).Msg("predict daily: create market failed")
	return false
}

func (j *DailyMarketJob) fetchPrice(ctx context.Context, source, symbol string) (float64, error) {
	switch source {
	case "cn":
		q, err := j.rt.FetchSnapshot(ctx, symbol)
		if err != nil {
			return 0, err
		}
		return q.Last, nil
	case "us":
		q, err := j.rt.FetchUSStock(ctx, symbol)
		if err != nil {
			return 0, err
		}
		return q.Last, nil
	case "global_index":
		q, err := j.rt.FetchGlobalIndex(ctx, symbol)
		if err != nil {
			return 0, err
		}
		return q.Last, nil
	case "forex":
		q, err := j.rt.FetchForex(ctx, symbol)
		if err != nil {
			return 0, err
		}
		return q.Last, nil
	default:
		return 0, fmt.Errorf("unknown source %q", source)
	}
}

// niceThreshold 取略高于现价的"整数档"阈值，让"能否突破"具备悬念。
func niceThreshold(p float64) float64 {
	step := thresholdStep(p)
	th := math.Ceil(p/step) * step
	if th-p < step*0.25 { // 距现价太近则再抬一档
		th += step
	}
	return th
}

func thresholdStep(p float64) float64 {
	switch {
	case p >= 5000:
		return 50
	case p >= 1000:
		return 20
	case p >= 100:
		return 5
	case p >= 10:
		return 1
	case p >= 1:
		return 0.1
	default:
		return 0.01
	}
}

func fmtNum(v float64) string {
	if v == math.Trunc(v) {
		return strconv.FormatFloat(v, 'f', 0, 64)
	}
	if v >= 10 {
		return strconv.FormatFloat(v, 'f', 1, 64)
	}
	return strconv.FormatFloat(v, 'f', 2, 64)
}

func mustJSON(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}

// atOffset 返回相对今天偏移 days 天、本地 hour:min 的毫秒时间戳。
func atOffset(now time.Time, days, hour, min int) int64 {
	d := time.Date(now.Year(), now.Month(), now.Day(), hour, min, 0, 0, now.Location()).
		AddDate(0, 0, days)
	return d.UnixMilli()
}
