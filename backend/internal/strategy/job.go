package strategy

import (
	"context"
	"time"

	"github.com/rs/zerolog"
)

// Job 周期抓取主策略快照。数据本身每天最多变一次（收盘后重算），
// 30 分钟一次的频率足够及时，也几乎不产生外部压力。
type Job struct {
	svc      *Service
	interval time.Duration
	logger   *zerolog.Logger
}

func NewJob(svc *Service, interval time.Duration, l *zerolog.Logger) *Job {
	if interval <= 0 {
		interval = 30 * time.Minute
	}
	return &Job{svc: svc, interval: interval, logger: l}
}

func (j *Job) Name() string            { return "strategy_sync" }
func (j *Job) Interval() time.Duration { return j.interval }

func (j *Job) Run(ctx context.Context) error {
	if _, err := j.svc.Sync(ctx); err != nil {
		// 抓不到不是致命的：库里还有上一次的快照，接口会照常返回并标记过期。
		j.logger.Warn().Err(err).Msg("strategy: sync failed, keep last snapshot")
		return err
	}
	// 新快照到了就顺手刷新实盘组合，不必等下一轮 live_portfolio_daily。
	if p, isNew, err := j.svc.MaterializeLivePortfolio(ctx); err != nil {
		j.logger.Warn().Err(err).Msg("live portfolio: materialize after sync failed")
	} else if p != nil && isNew {
		j.logger.Info().Str("as_of", p.AsOf).Int("holdings", len(p.Holdings)).
			Int("transactions", len(p.Transactions)).Bool("reconciled", p.Reconciled).
			Msg("live portfolio: materialized (after sync)")
	}
	return nil
}

// LivePortfolioJob 每天把实盘账户物化成「组合管理」里的系统组合。
//
// 跑得比一天一次勤（默认每小时），但按「数据截至日」幂等覆盖：上游当天
// 晚些时候重算了，也能在一小时内反映出来；日志里只在新的一天时打 Info。
type LivePortfolioJob struct {
	svc      *Service
	interval time.Duration
	logger   *zerolog.Logger
}

func NewLivePortfolioJob(svc *Service, interval time.Duration, l *zerolog.Logger) *LivePortfolioJob {
	if interval <= 0 {
		interval = time.Hour
	}
	return &LivePortfolioJob{svc: svc, interval: interval, logger: l}
}

func (j *LivePortfolioJob) Name() string            { return "live_portfolio_daily" }
func (j *LivePortfolioJob) Interval() time.Duration { return j.interval }

func (j *LivePortfolioJob) Run(ctx context.Context) error {
	p, isNew, err := j.svc.MaterializeLivePortfolio(ctx)
	if err != nil {
		j.logger.Warn().Err(err).Msg("live portfolio: materialize failed")
		return err
	}
	if p == nil {
		j.logger.Info().Msg("live portfolio: no live account in snapshot yet, skip")
		return nil
	}
	ev := j.logger.Debug()
	if isNew {
		ev = j.logger.Info()
	}
	ev.Str("as_of", p.AsOf).
		Int("holdings", len(p.Holdings)).
		Int("transactions", len(p.Transactions)).
		Bool("reconciled", p.Reconciled).
		Bool("stale", p.Stale).
		Float64("total", p.Total).
		Msg("live portfolio: materialized")
	return nil
}
