package predict

import (
	"context"
	"fmt"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/ai/realtime"
)

// AutoSettleJob 是 scheduler 的周期任务：
//  1. 把过了 close_at 的市场置为 closed（停止下注）；
//  2. 对到期的 resolve_kind='auto' 市场按 resolve_rule 取现价判定赢方并结算。
//
// 天气等 manual 市场不在此处理，等管理端录入结果。
type AutoSettleJob struct {
	svc      *Service
	rt       *realtime.Client
	logger   *zerolog.Logger
	interval time.Duration
}

func NewAutoSettleJob(svc *Service, rt *realtime.Client, l *zerolog.Logger, interval time.Duration) *AutoSettleJob {
	if interval <= 0 {
		interval = time.Minute
	}
	return &AutoSettleJob{svc: svc, rt: rt, logger: l, interval: interval}
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
	price, err := j.fetchPrice(ctx, rule)
	if err != nil {
		return err
	}
	if price <= 0 {
		return fmt.Errorf("price unavailable for %s:%s", rule.Source, rule.Symbol)
	}

	hit, err := compare(price, rule.Op, rule.Value)
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
		Float64("price", price).Bool("yes", hit).
		Msg("predict: market auto settled")
	return nil
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
