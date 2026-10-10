package falsification

import (
	"context"
	"time"

	"github.com/rs/zerolog"
)

// Job 周期从 alpha-radar 拉档案。判定结果每天最多变几次，30 分钟足够及时。
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

func (j *Job) Name() string            { return "falsification_sync" }
func (j *Job) Interval() time.Duration { return j.interval }

func (j *Job) Run(ctx context.Context) error {
	if _, err := j.svc.Sync(ctx); err != nil {
		// 拉不到不致命：库里还有上一份，再不行还有内置 seed。
		j.logger.Warn().Err(err).Msg("falsification: sync failed, keep last snapshot")
		return err
	}
	return nil
}
