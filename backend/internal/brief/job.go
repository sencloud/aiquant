package brief

import (
	"context"
	"time"

	"github.com/rs/zerolog"
)

// Job 是 scheduler 的周期任务：非交易日空跑；交易日内检测到「当前时段还没有
// 生成过」就生成一条并落库。
//
// 一天会命中 5 个时段（盘前/早盘/午间/午后/收盘），其余 tick 直接返回，
// 因此额外的开销只有一次 COUNT 查询。
type Job struct {
	svc      *Service
	interval time.Duration
	logger   *zerolog.Logger
}

func NewJob(svc *Service, interval time.Duration, l *zerolog.Logger) *Job {
	if interval <= 0 {
		interval = 10 * time.Minute
	}
	return &Job{svc: svc, interval: interval, logger: l}
}

func (j *Job) Name() string            { return "ai_home_suggestions" }
func (j *Job) Interval() time.Duration { return j.interval }

func (j *Job) Run(ctx context.Context) error {
	now := time.Now()
	if !IsTradingDay(now) {
		return nil
	}
	created, err := j.svc.EnsureSlot(ctx, now)
	if err != nil {
		return err
	}
	if created {
		j.logger.Info().Str("slot", SlotKey(now)).Msg("brief: slot generated")
	}
	return nil
}
