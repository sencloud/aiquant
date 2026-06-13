package predict

import (
	"context"
	"fmt"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/ai/realtime"
	"github.com/sencloud/finme-backend/internal/ai/weather"
)

// AutoSettleJob 是 scheduler 的周期任务：
//  1. 把过了 close_at 的市场置为 closed（停止下注）；
//  2. 对到期的 resolve_kind='auto' 市场按 resolve_rule 取数判定赢方并结算。
//
// 支持金融(realtime 现价)与天气(Open-Meteo 实况)两类自动结算源；
// 天气实况尚未产出时本 tick 跳过，下个 tick 自动重试。
type AutoSettleJob struct {
	svc      *Service
	rt       *realtime.Client
	wx       *weather.Client
	logger   *zerolog.Logger
	interval time.Duration
}

func NewAutoSettleJob(svc *Service, rt *realtime.Client, wx *weather.Client, l *zerolog.Logger, interval time.Duration) *AutoSettleJob {
	if interval <= 0 {
		interval = time.Minute
	}
	return &AutoSettleJob{svc: svc, rt: rt, wx: wx, logger: l, interval: interval}
}

func (j *AutoSettleJob) Name() string            { return "predict_auto_settle" }
func (j *AutoSettleJob) Interval() time.Duration { return j.interval }

func (j *AutoSettleJob) Run(ctx context.Context) error {
	if n, err := j.svc.CloseDue(ctx); err != nil {
		j.logger.Error().Err(err).Msg("predict: close due markets failed")
	} else if n > 0 {
		j.logger.Info().Int64("count", n).Msg("predict: markets closed for betting")
	}

	due, err := j.svc.DueAutoMarkets(ctx)
	if err != nil {
		return err
	}
	for _, m := range due {
		if err := j.settleOne(ctx, m); err != nil {
			// 单个失败不阻塞其他市场；下个 tick 自动重试。
			j.logger.Error().Err(err).Int64("market_id", m.ID).
				Str("title", m.Title).Msg("predict: auto settle failed")
		}
	}
	return nil
}

func (j *AutoSettleJob) settleOne(ctx context.Context, m Market) error {
	rule, err := ParseResolveRule(m.ResolveRule)
	if err != nil {
		return fmt.Errorf("parse resolve_rule: %w", err)
	}
	value, ok, err := j.fetchValue(ctx, rule)
	if err != nil {
		return err
	}
	if !ok {
		// 数据暂未产出(如天气实况未出)，跳过等下个 tick 重试。
		j.logger.Debug().Int64("market_id", m.ID).Str("source", rule.Source).
			Msg("predict: resolve value not ready yet, will retry")
		return nil
	}

	hit, err := compare(value, rule.Op, rule.Value)
	if err != nil {
		return err
	}
	winIdx := rule.NoIdx
	if hit {
		winIdx = rule.YesIdx
	}

	view, err := j.svc.GetMarket(ctx, m.ID)
	if err != nil {
		return err
	}
	var winOptionID int64
	for _, o := range view.Options {
		if o.Idx == winIdx {
			winOptionID = o.ID
			break
		}
	}
	if winOptionID == 0 {
		return fmt.Errorf("winning option idx %d not found", winIdx)
	}
	if err := j.svc.Settle(ctx, m.ID, winOptionID); err != nil {
		return err
	}
	j.logger.Info().Int64("market_id", m.ID).Str("title", m.Title).
		Float64("value", value).Bool("yes", hit).
		Msg("predict: market auto settled")
	return nil
}

// fetchValue 取结算判定值；返回 (值, 是否就绪, 错误)。
// 天气实况尚未产出时返回 ok=false（不视作错误，下个 tick 重试）。
func (j *AutoSettleJob) fetchValue(ctx context.Context, rule *ResolveRule) (float64, bool, error) {
	if rule.Source == "weather" {
		if j.wx == nil {
			return 0, false, fmt.Errorf("weather client not configured")
		}
		city, ok := weather.CityByKey(rule.City)
		if !ok {
			return 0, false, fmt.Errorf("unknown weather city %q", rule.City)
		}
		return j.wx.MetricValue(ctx, city.Lat, city.Lon, rule.Date, rule.Metric)
	}

	price, err := j.fetchPrice(ctx, rule)
	if err != nil {
		return 0, false, err
	}
	if price <= 0 {
		return 0, false, fmt.Errorf("price unavailable for %s:%s", rule.Source, rule.Symbol)
	}
	return price, true, nil
}

func (j *AutoSettleJob) fetchPrice(ctx context.Context, rule *ResolveRule) (float64, error) {
	switch rule.Source {
	case "cn":
		q, err := j.rt.FetchSnapshot(ctx, rule.Symbol)
		if err != nil {
			return 0, err
		}
		return q.Last, nil
	case "us":
		q, err := j.rt.FetchUSStock(ctx, rule.Symbol)
		if err != nil {
			return 0, err
		}
		return q.Last, nil
	case "global_index":
		q, err := j.rt.FetchGlobalIndex(ctx, rule.Symbol)
		if err != nil {
			return 0, err
		}
		return q.Last, nil
	case "forex":
		q, err := j.rt.FetchForex(ctx, rule.Symbol)
		if err != nil {
			return 0, err
		}
		return q.Last, nil
	default:
		return 0, fmt.Errorf("unknown resolve source %q", rule.Source)
	}
}

func compare(price float64, op string, value float64) (bool, error) {
	switch op {
	case "gte":
		return price >= value, nil
	case "lte":
		return price <= value, nil
	case "gt":
		return price > value, nil
	case "lt":
		return price < value, nil
	default:
		return false, fmt.Errorf("unknown op %q", op)
	}
}
