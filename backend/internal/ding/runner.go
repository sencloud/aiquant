package ding

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/ai/chat"
	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/store"
)

// ChatExecutor 是 Runner 依赖的最小 chat 接口；当前实现就是 *chat.Service。
//
// 拆抽象的目的：
//   - DING runner 与 /v1/ai/chat 共享同一套 LLM + Tool calling loop + 扣费策略；
//   - 单元测试可以用桩替换；
//   - chat.Service 的 SSE Run 与 RunCollect 由 chat 内部维护，DING 不感知 emit。
type ChatExecutor interface {
	Configured() bool
	RunCollect(ctx context.Context, in chat.ChatInput) (*chat.CollectResult, error)
}

// Runner 是服务端定时执行 DING 任务的执行体。
//
// 单次 Run() 流程：
//  1. ListDue：取所有 enabled=1 且 next_run_at <= now 的任务；
//  2. 对每条 task：AdvanceNextRun 先占位（避免跑期间重复入选）；
//  3. ledger.Apply(-cost, consume_ding, ref_id=run_uuid)：扣费失败 → skipped_no_credit；
//  4. 调用 chat.Service.RunCollect（带 30 工具的 tool calling loop）；
//  5. 写一条 Run + Notification（push_status=pending），由 pusher 进程接力推送。
//
// 错误隔离：单个任务失败不影响下一个；scheduler 进程不会因此 panic。
type Runner struct {
	st        *store.Store
	tasks     *TaskRepo
	runs      *RunRepo
	notifs    *NotificationRepo
	ledger    *billing.LedgerRepo
	chat      ChatExecutor
	logger    *zerolog.Logger
	sysPrompt string
}

type RunnerConfig struct {
	SystemPrompt string
}

func NewRunner(st *store.Store, exec ChatExecutor, ledgerRepo *billing.LedgerRepo, l *zerolog.Logger, cfg RunnerConfig) *Runner {
	sys := strings.TrimSpace(cfg.SystemPrompt)
	if sys == "" {
		sys = "你是喜宽 AI 量化助理；当问题需要数据时优先调用工具拉真实行情/财务/事件，再给出结构化结论；用中文 markdown 输出。"
	}
	return &Runner{
		st:        st,
		tasks:     NewTaskRepo(st),
		runs:      NewRunRepo(st),
		notifs:    NewNotificationRepo(st),
		ledger:    ledgerRepo,
		chat:      exec,
		logger:    l,
		sysPrompt: sys,
	}
}

// Name / Interval / Run 实现 scheduler.Job。
func (r *Runner) Name() string                       { return "ding_runner" }
func (r *Runner) Interval() time.Duration            { return 30 * time.Second }

func (r *Runner) Run(ctx context.Context) error {
	now := time.Now()
	due, err := r.tasks.ListDue(ctx, now, 50)
	if err != nil {
		return err
	}
	for _, t := range due {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		task := t
		if err := r.runOne(ctx, &task); err != nil {
			r.logger.Error().Err(err).Str("task", task.UUID).Msg("ding_runner: run task failed")
		}
	}
	return nil
}

func (r *Runner) runOne(ctx context.Context, t *Task) error {
	startedAt := time.Now()
	if err := r.tasks.AdvanceNextRun(ctx, t, startedAt); err != nil {
		return fmt.Errorf("advance next: %w", err)
	}

	cost := t.CostCreditsPerRun
	if cost > 0 {
		runRef := fmt.Sprintf("ding/%s/%d", t.UUID, startedAt.UnixMilli())
		_, err := r.ledger.Apply(ctx, billing.ApplyParams{
			UserID:  t.UserID,
			Delta:   -cost,
			Reason:  billing.ReasonConsumeDing,
			RefType: "ding_run",
			RefID:   runRef,
			Remark:  "DING auto-run cost",
		})
		if err != nil {
			if errors.Is(err, billing.ErrInsufficientBalance) {
				return r.recordSkippedNoCredit(ctx, t, startedAt)
			}
			if !errors.Is(err, billing.ErrLedgerDuplicate) {
				return fmt.Errorf("ledger apply: %w", err)
			}
		}
	}

	res, err := r.chat.RunCollect(ctx, chat.ChatInput{
		UserID:     t.UserID,
		Persona:    t.PersonaID,
		UserText:   t.Prompt,
		SystemHint: r.sysPrompt,
		ClientReqID: fmt.Sprintf("ding/%s/%d", t.UUID, startedAt.UnixMilli()),
	})
	if err != nil {
		return r.recordFailure(ctx, t, startedAt, err.Error())
	}
	if res.ErrorCode != "" {
		return r.recordFailure(ctx, t, startedAt, fmt.Sprintf("%s: %s", res.ErrorCode, res.ErrorMessage))
	}
	if strings.TrimSpace(res.FinalText) == "" {
		return r.recordFailure(ctx, t, startedAt, "AI 返回为空")
	}
	return r.recordSuccess(ctx, t, startedAt, res.FinalText, res.ToolCalls, cost)
}

func (r *Runner) recordSuccess(ctx context.Context, t *Task, startedAt time.Time, content string, toolCalls int, cost int64) error {
	title := strings.TrimSpace(t.Title)
	if title == "" {
		title = "DING 任务结果"
	}
	body := briefOf(content, 80)
	notif, err := r.notifs.Create(ctx, CreateNotifInput{
		UserID:    t.UserID,
		Topic:     "ding",
		RefType:   "ding_task",
		RefID:     t.UUID,
		Title:     title,
		BodyBrief: body,
		Payload:   content,
	})
	if err != nil {
		return fmt.Errorf("create notif: %w", err)
	}
	_, err = r.runs.Insert(ctx, ReportRunInput{
		TaskID:         t.ID,
		Status:         RunStatusSuccess,
		DurationMs:     time.Since(startedAt).Milliseconds(),
		NotificationID: notif.ID,
		StartedAt:      startedAt,
	})
	if err != nil {
		return fmt.Errorf("insert run: %w", err)
	}
	if err := r.tasks.MarkRan(ctx, t, time.Now()); err != nil {
		return fmt.Errorf("mark ran: %w", err)
	}
	r.logger.Info().Str("task", t.UUID).Int64("user", t.UserID).
		Int64("cost", cost).Int("tools", toolCalls).
		Msg("ding_runner: success")
	return nil
}

func (r *Runner) recordFailure(ctx context.Context, t *Task, startedAt time.Time, errMsg string) error {
	title := strings.TrimSpace(t.Title) + "（失败）"
	body := briefOf(errMsg, 80)
	notif, err := r.notifs.Create(ctx, CreateNotifInput{
		UserID:    t.UserID,
		Topic:     "ding",
		RefType:   "ding_task",
		RefID:     t.UUID,
		Title:     title,
		BodyBrief: body,
		Payload:   errMsg,
	})
	if err != nil {
		return fmt.Errorf("create failure notif: %w", err)
	}
	_, err = r.runs.Insert(ctx, ReportRunInput{
		TaskID:         t.ID,
		Status:         RunStatusFailed,
		DurationMs:     time.Since(startedAt).Milliseconds(),
		Error:          errMsg,
		NotificationID: notif.ID,
		StartedAt:      startedAt,
	})
	if err != nil {
		return fmt.Errorf("insert failure run: %w", err)
	}
	if err := r.tasks.MarkRan(ctx, t, time.Now()); err != nil {
		return fmt.Errorf("mark ran: %w", err)
	}
	r.logger.Warn().Str("task", t.UUID).Int64("user", t.UserID).
		Str("err", errMsg).Msg("ding_runner: failed")
	return nil
}

func (r *Runner) recordSkippedNoCredit(ctx context.Context, t *Task, startedAt time.Time) error {
	title := strings.TrimSpace(t.Title) + "（喜点不足，已跳过）"
	body := "余额不足，本次任务未执行；请充值后重新触发。"
	notif, err := r.notifs.Create(ctx, CreateNotifInput{
		UserID:    t.UserID,
		Topic:     "ding",
		RefType:   "ding_task",
		RefID:     t.UUID,
		Title:     title,
		BodyBrief: body,
		Payload:   body,
	})
	if err != nil {
		return fmt.Errorf("create skipped notif: %w", err)
	}
	_, err = r.runs.Insert(ctx, ReportRunInput{
		TaskID:         t.ID,
		Status:         RunStatusSkippedNoCredit,
		DurationMs:     time.Since(startedAt).Milliseconds(),
		NotificationID: notif.ID,
		StartedAt:      startedAt,
	})
	if err != nil {
		return fmt.Errorf("insert skipped run: %w", err)
	}
	if err := r.tasks.MarkRan(ctx, t, time.Now()); err != nil {
		return fmt.Errorf("mark ran: %w", err)
	}
	r.logger.Info().Str("task", t.UUID).Int64("user", t.UserID).
		Msg("ding_runner: skipped no credit")
	return nil
}
