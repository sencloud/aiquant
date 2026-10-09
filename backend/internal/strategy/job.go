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
	return nil
}
