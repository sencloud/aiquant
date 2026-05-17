// Package scheduler 是 finme-server scheduler 子命令的实现。
//
// 当前阶段（W6 minimal）：
//   - 每 5 分钟跑一次余额对账（reconcile_balance），不一致则记审计 log + zerolog WARN；
//   - 暂未实现服务端 LLM 调度执行 DING（W3 第二阶段会接入）。
package scheduler

import (
	"context"
	"sync"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/store"
)

// Job 是一个定时任务的最小协议。
type Job interface {
	Name() string
	Interval() time.Duration
	Run(ctx context.Context) error
}

// Scheduler 是一个最小化的内存 cron。
//
// 不依赖外部 cron 库；启动后每个 Job 单独 goroutine 跑 ticker。
type Scheduler struct {
	logger *zerolog.Logger
	jobs   []Job
	wg     sync.WaitGroup
}

func New(l *zerolog.Logger) *Scheduler {
	return &Scheduler{logger: l}
}

func (s *Scheduler) Register(j Job) {
	s.jobs = append(s.jobs, j)
}

// Run 阻塞直到 ctx 取消。
func (s *Scheduler) Run(ctx context.Context) error {
	s.logger.Info().Int("jobs", len(s.jobs)).Msg("scheduler starting")
	for _, j := range s.jobs {
		j := j
		s.wg.Add(1)
		go func() {
			defer s.wg.Done()
			s.runJob(ctx, j)
		}()
	}
	<-ctx.Done()
	s.wg.Wait()
	s.logger.Info().Msg("scheduler stopped")
	return ctx.Err()
}

func (s *Scheduler) runJob(ctx context.Context, j Job) {
	tick := time.NewTicker(j.Interval())
	defer tick.Stop()
	// 启动后立刻跑一次（便于联调验证）
	s.runOnce(ctx, j)
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			s.runOnce(ctx, j)
		}
	}
}

func (s *Scheduler) runOnce(ctx context.Context, j Job) {
	start := time.Now()
	if err := j.Run(ctx); err != nil {
		s.logger.Error().Err(err).Str("job", j.Name()).
			Dur("dur", time.Since(start)).Msg("scheduler: job failed")
		return
	}
	s.logger.Debug().Str("job", j.Name()).
		Dur("dur", time.Since(start)).Msg("scheduler: job ok")
}

// ReconcileBalance 每 5 分钟跑一次：
// 比对每个用户的 users.credit_balance 与 sum(credit_ledger.delta)；
// 不一致 → 记 audit_log + WARN。
//
// 这是"事后告警"机制，不会自动修；不一致一般意味着代码 bug，需要人工处理。
type ReconcileBalance struct {
	store    *store.Store
	logger   *zerolog.Logger
	interval time.Duration
}

func NewReconcileBalance(st *store.Store, l *zerolog.Logger, interval time.Duration) *ReconcileBalance {
	if interval <= 0 {
		interval = 5 * time.Minute
	}
	return &ReconcileBalance{store: st, logger: l, interval: interval}
}

func (r *ReconcileBalance) Name() string             { return "reconcile_balance" }
func (r *ReconcileBalance) Interval() time.Duration  { return r.interval }

func (r *ReconcileBalance) Run(ctx context.Context) error {
	type mismatch struct {
		UserID  int64 `db:"user_id"`
		Balance int64 `db:"balance"`
		LedSum  int64 `db:"led_sum"`
	}
	rows := []mismatch{}
	err := r.store.DB.SelectContext(ctx, &rows, `
		SELECT u.id AS user_id,
		       u.credit_balance AS balance,
		       COALESCE((SELECT SUM(delta) FROM credit_ledger l WHERE l.user_id=u.id), 0) AS led_sum
		FROM users u
		WHERE u.credit_balance <>
		      COALESCE((SELECT SUM(delta) FROM credit_ledger l WHERE l.user_id=u.id), 0)`)
	if err != nil {
		return err
	}
	if len(rows) == 0 {
		r.logger.Info().Msg("reconcile_balance: all balances consistent")
		return nil
	}
	for _, m := range rows {
		r.logger.Warn().
			Int64("user_id", m.UserID).
			Int64("balance", m.Balance).
			Int64("ledger_sum", m.LedSum).
			Int64("delta", m.Balance-m.LedSum).
			Msg("reconcile_balance: MISMATCH (manual fix required)")
		_, _ = r.store.DB.ExecContext(ctx, `
			INSERT INTO audit_log(user_id, action, detail_json, created_at)
			VALUES(?, 'reconcile_balance.mismatch', ?, ?)`,
			m.UserID,
			detailJSON(map[string]any{"balance": m.Balance, "led_sum": m.LedSum}),
			time.Now().UnixMilli(),
		)
	}
	return nil
}

func detailJSON(v map[string]any) string {
	if v == nil {
		return ""
	}
	// 极简 JSON 序列化：避免依赖 reflect 包外的 marshal
	b, _ := jsonMarshalSafe(v)
	return string(b)
}
