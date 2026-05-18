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
	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

// Service 是 DING 模块对外的总入口。
//
// 服务端为唯一执行路径：所有 LLM 工具 loop 都走 chat.Service，
// 客户端只触发 run-now 或等待 scheduler 自动跑。
//
// DING 自身不再扣费 —— 扣费在 chat.Service.Run 内统一以 reason=consume_ding
// 的方式完成（幂等键 = ClientReqID）。
type Service struct {
	cfg *platform.Config

	tasks  *TaskRepo
	runs   *RunRepo
	notifs *NotificationRepo

	chat   *chat.Service
	logger *zerolog.Logger
}

// NewService 构造 DING service。ledgerRepo 暂未使用（DING 不直接扣费），
// 但保留参数以便后续接入"任务级单次预算 / 月度配额"等扩展。
func NewService(
	st *store.Store,
	cfg *platform.Config,
	chatSvc *chat.Service,
	_ *billing.LedgerRepo,
	logger *zerolog.Logger,
) *Service {
	return &Service{
		cfg:    cfg,
		tasks:  NewTaskRepo(st),
		runs:   NewRunRepo(st),
		notifs: NewNotificationRepo(st),
		chat:   chatSvc,
		logger: logger,
	}
}

// ── Tasks ──────────────────────────────────────────────────────────────

func (s *Service) ListTasks(ctx context.Context, userID int64) ([]Task, error) {
	rows, err := s.tasks.ListByUser(ctx, userID)
	if err != nil {
		return nil, platform.ErrInternal("DING.LIST_TASKS", err)
	}
	return rows, nil
}

type CreateTaskReq struct {
	Title             string `json:"title"`
	Prompt            string `json:"prompt"`
	PersonaID         string `json:"persona_id"`
	Schedule          string `json:"schedule"`
	Enabled           bool   `json:"enabled"`
	CostCreditsPerRun int64  `json:"cost_credits_per_run"`
}

func (s *Service) CreateTask(ctx context.Context, userID int64, in CreateTaskReq) (*Task, error) {
	if err := validateTaskReq(in.Title, in.Prompt, in.Schedule); err != nil {
		return nil, err
	}
	persona := strings.TrimSpace(in.PersonaID)
	if persona == "" {
		persona = "default"
	}
	cost := in.CostCreditsPerRun
	if cost <= 0 {
		cost = 5
	}
	t, err := s.tasks.Create(ctx, CreateTaskInput{
		UserID:            userID,
		Title:             in.Title,
		Prompt:            in.Prompt,
		PersonaID:         persona,
		Schedule:          in.Schedule,
		Enabled:           in.Enabled,
		CostCreditsPerRun: cost,
	})
	if err != nil {
		return nil, platform.ErrInternal("DING.CREATE_TASK", err)
	}
	return t, nil
}

type UpdateTaskReq struct {
	Title    *string `json:"title,omitempty"`
	Prompt   *string `json:"prompt,omitempty"`
	Schedule *string `json:"schedule,omitempty"`
	Persona  *string `json:"persona_id,omitempty"`
	Enabled  *bool   `json:"enabled,omitempty"`
}

func (s *Service) UpdateTask(ctx context.Context, userID int64, uuid string, in UpdateTaskReq) (*Task, error) {
	if in.Schedule != nil {
		if err := ValidateSchedule(*in.Schedule); err != nil {
			return nil, platform.ErrBadRequest("DING.SCHEDULE_INVALID", err.Error(), nil)
		}
	}
	t, err := s.tasks.Update(ctx, userID, uuid, UpdateTaskInput{
		Title: in.Title, Prompt: in.Prompt, Schedule: in.Schedule,
		Persona: in.Persona, Enabled: in.Enabled,
	})
	if err != nil {
		return nil, platform.ErrInternal("DING.UPDATE_TASK", err)
	}
	if t == nil {
		return nil, platform.ErrNotFound("DING.TASK_NOT_FOUND", "task not found")
	}
	return t, nil
}

func (s *Service) DeleteTask(ctx context.Context, userID int64, uuid string) error {
	if err := s.tasks.Delete(ctx, userID, uuid); err != nil {
		return platform.ErrInternal("DING.DELETE_TASK", err)
	}
	return nil
}

// ── Run Now（服务端唯一执行路径） ──────────────────────────────────────

// RunNow 由客户端 POST /v1/ding/tasks/{uuid}/run-now 触发：
//
// 1. 查找 task；
// 2. 通过 chat.Service.RunCollect 跑一遍带 30 工具的 LLM loop；
//    扣费由 chat.Service 以 reason=consume_ding + ref=ding_run/<uuid>/<ts>
//    统一完成（幂等键）；DING 自身不再额外扣费，避免与 chat 双重扣。
// 3. 把结果落库为 Run + Notification（push_status=pending）；
// 4. 同步返回结果给客户端，便于立即在 inbox 渲染。
//
// 任何错误都会写一条失败 notification + status=failed 的 run，
// 同时把 error 透传给上层 HTTP（统一通过 platform.ErrXxx 包装）。
func (s *Service) RunNow(ctx context.Context, userID int64, taskUUID string) (*Run, *Notification, error) {
	if s.chat == nil || !s.chat.Configured() {
		return nil, nil, platform.ErrUnavailable("DING.AI_NOT_CONFIGURED",
			errors.New("ai chat service not configured"))
	}
	t, err := s.tasks.FindByUUID(ctx, userID, taskUUID)
	if err != nil {
		return nil, nil, platform.ErrInternal("DING.TASK_LOOKUP", err)
	}
	if t == nil {
		return nil, nil, platform.ErrNotFound("DING.TASK_NOT_FOUND", "task not found")
	}

	startedAt := time.Now()

	res, cerr := s.chat.RunCollect(ctx, chat.ChatInput{
		UserID:        t.UserID,
		Persona:       t.PersonaID,
		UserText:      t.Prompt,
		ClientReqID:   fmt.Sprintf("ding/%s/%d", t.UUID, startedAt.UnixMilli()),
		BillingReason: billing.ReasonConsumeDing,
	})
	if cerr != nil {
		if errors.Is(cerr, chat.ErrInsufficientBalance) {
			run, notif, ferr := s.recordSkippedNoCredit(ctx, t, startedAt)
			if ferr != nil {
				return nil, nil, platform.ErrInternal("DING.RECORD_SKIPPED", ferr)
			}
			return run, notif, nil
		}
		run, notif, _ := s.recordFailure(ctx, t, startedAt, cerr.Error())
		return run, notif, platform.ErrInternal("DING.CHAT", cerr)
	}
	if res.ErrorCode == "AI.INSUFFICIENT_BALANCE" {
		run, notif, ferr := s.recordSkippedNoCredit(ctx, t, startedAt)
		if ferr != nil {
			return nil, nil, platform.ErrInternal("DING.RECORD_SKIPPED", ferr)
		}
		return run, notif, nil
	}
	if res.ErrorCode != "" {
		msg := fmt.Sprintf("%s: %s", res.ErrorCode, res.ErrorMessage)
		run, notif, _ := s.recordFailure(ctx, t, startedAt, msg)
		return run, notif, platform.ErrInternal("DING.CHAT_ERROR", errors.New(msg))
	}
	if strings.TrimSpace(res.FinalText) == "" {
		run, notif, _ := s.recordFailure(ctx, t, startedAt, "AI 返回为空")
		return run, notif, nil
	}
	return s.recordSuccess(ctx, t, startedAt, res.FinalText)
}

func (s *Service) recordSuccess(ctx context.Context, t *Task, startedAt time.Time, content string) (*Run, *Notification, error) {
	title := strings.TrimSpace(t.Title)
	if title == "" {
		title = "DING 任务结果"
	}
	body := briefOf(content, 80)
	notif, err := s.notifs.Create(ctx, CreateNotifInput{
		UserID:    t.UserID,
		Topic:     "ding",
		RefType:   "ding_task",
		RefID:     t.UUID,
		Title:     title,
		BodyBrief: body,
		Payload:   content,
	})
	if err != nil {
		return nil, nil, err
	}
	run, err := s.runs.Insert(ctx, ReportRunInput{
		TaskID:         t.ID,
		Status:         RunStatusSuccess,
		DurationMs:     time.Since(startedAt).Milliseconds(),
		NotificationID: notif.ID,
		StartedAt:      startedAt,
	})
	if err != nil {
		return nil, nil, err
	}
	if err := s.tasks.MarkRan(ctx, t, time.Now()); err != nil {
		return nil, nil, err
	}
	return run, notif, nil
}

func (s *Service) recordFailure(ctx context.Context, t *Task, startedAt time.Time, errMsg string) (*Run, *Notification, error) {
	title := strings.TrimSpace(t.Title) + "（失败）"
	body := briefOf(errMsg, 80)
	notif, err := s.notifs.Create(ctx, CreateNotifInput{
		UserID:    t.UserID,
		Topic:     "ding",
		RefType:   "ding_task",
		RefID:     t.UUID,
		Title:     title,
		BodyBrief: body,
		Payload:   errMsg,
	})
	if err != nil {
		return nil, nil, err
	}
	run, err := s.runs.Insert(ctx, ReportRunInput{
		TaskID:         t.ID,
		Status:         RunStatusFailed,
		DurationMs:     time.Since(startedAt).Milliseconds(),
		Error:          errMsg,
		NotificationID: notif.ID,
		StartedAt:      startedAt,
	})
	if err != nil {
		return nil, nil, err
	}
	if err := s.tasks.MarkRan(ctx, t, time.Now()); err != nil {
		return nil, nil, err
	}
	return run, notif, nil
}

func (s *Service) recordSkippedNoCredit(ctx context.Context, t *Task, startedAt time.Time) (*Run, *Notification, error) {
	title := strings.TrimSpace(t.Title) + "（喜点不足，已跳过）"
	body := "余额不足，本次任务未执行；请充值后重新触发。"
	notif, err := s.notifs.Create(ctx, CreateNotifInput{
		UserID:    t.UserID,
		Topic:     "ding",
		RefType:   "ding_task",
		RefID:     t.UUID,
		Title:     title,
		BodyBrief: body,
		Payload:   body,
	})
	if err != nil {
		return nil, nil, err
	}
	run, err := s.runs.Insert(ctx, ReportRunInput{
		TaskID:         t.ID,
		Status:         RunStatusSkippedNoCredit,
		DurationMs:     time.Since(startedAt).Milliseconds(),
		NotificationID: notif.ID,
		StartedAt:      startedAt,
	})
	if err != nil {
		return nil, nil, err
	}
	if err := s.tasks.MarkRan(ctx, t, time.Now()); err != nil {
		return nil, nil, err
	}
	return run, notif, nil
}

// ── Runs + Notifications ──────────────────────────────────────────────

type ReportRunReq struct {
	TaskUUID    string `json:"task_uuid"`
	Status      string `json:"status"` // success / failed
	Title       string `json:"title"`
	BodyBrief   string `json:"body_brief"`
	Content     string `json:"content"` // 完整 markdown，存到 payload_json
	Error       string `json:"error,omitempty"`
	TotalTokens int64  `json:"total_tokens,omitempty"`
	DurationMs  int64  `json:"duration_ms,omitempty"`
	StartedAtMs int64  `json:"started_at_ms,omitempty"`
}

// ReportRun 客户端本地执行完后调用：记录 run，写一条 notification。
func (s *Service) ReportRun(ctx context.Context, userID int64, in ReportRunReq) (*Run, *Notification, error) {
	t, err := s.tasks.FindByUUID(ctx, userID, in.TaskUUID)
	if err != nil {
		return nil, nil, platform.ErrInternal("DING.TASK_LOOKUP", err)
	}
	if t == nil {
		return nil, nil, platform.ErrNotFound("DING.TASK_NOT_FOUND", "task not found")
	}
	if in.Status == "" {
		in.Status = RunStatusSuccess
	}
	if in.Status != RunStatusSuccess && in.Status != RunStatusFailed && in.Status != RunStatusSkippedNoCredit {
		return nil, nil, platform.ErrBadRequest("DING.RUN_STATUS_INVALID", "invalid status", nil)
	}

	title := strings.TrimSpace(in.Title)
	if title == "" {
		title = t.Title
	}
	body := strings.TrimSpace(in.BodyBrief)
	if body == "" {
		body = briefOf(in.Content, 80)
	}

	var notif *Notification
	if in.Status == RunStatusSuccess && in.Content != "" {
		n, err := s.notifs.Create(ctx, CreateNotifInput{
			UserID:    userID,
			Topic:     "ding",
			RefType:   "ding_task",
			RefID:     t.UUID,
			Title:     title,
			BodyBrief: body,
			Payload:   in.Content,
		})
		if err != nil {
			return nil, nil, platform.ErrInternal("DING.CREATE_NOTIF", err)
		}
		notif = n
	} else if in.Status == RunStatusFailed && in.Error != "" {
		// 失败也通知一条，方便用户看
		n, err := s.notifs.Create(ctx, CreateNotifInput{
			UserID:    userID,
			Topic:     "ding",
			RefType:   "ding_task",
			RefID:     t.UUID,
			Title:     title + "（失败）",
			BodyBrief: briefOf(in.Error, 80),
			Payload:   in.Error,
		})
		if err != nil {
			return nil, nil, platform.ErrInternal("DING.CREATE_NOTIF", err)
		}
		notif = n
	}

	startedAt := time.UnixMilli(in.StartedAtMs)
	var notifID int64
	if notif != nil {
		notifID = notif.ID
	}
	run, err := s.runs.Insert(ctx, ReportRunInput{
		TaskID:         t.ID,
		Status:         in.Status,
		TotalTokens:    in.TotalTokens,
		DurationMs:     in.DurationMs,
		Error:          in.Error,
		NotificationID: notifID,
		StartedAt:      startedAt,
	})
	if err != nil {
		return nil, nil, platform.ErrInternal("DING.INSERT_RUN", err)
	}

	if err := s.tasks.MarkRan(ctx, t, time.Now()); err != nil {
		return nil, nil, platform.ErrInternal("DING.MARK_RAN", err)
	}

	return run, notif, nil
}

// ── Notifications ─────────────────────────────────────────────────────

func (s *Service) ListNotifications(ctx context.Context, userID int64, cursor int64, limit int, unreadOnly bool) ([]Notification, int64, error) {
	rows, next, err := s.notifs.List(ctx, userID, cursor, limit, unreadOnly)
	if err != nil {
		return nil, 0, platform.ErrInternal("DING.LIST_NOTIF", err)
	}
	return rows, next, nil
}

func (s *Service) GetNotification(ctx context.Context, userID int64, uuid string) (*Notification, error) {
	n, err := s.notifs.FindByUUID(ctx, userID, uuid)
	if err != nil {
		return nil, platform.ErrInternal("DING.FIND_NOTIF", err)
	}
	if n == nil {
		return nil, platform.ErrNotFound("DING.NOTIF_NOT_FOUND", "notification not found")
	}
	return n, nil
}

func (s *Service) MarkRead(ctx context.Context, userID int64, uuid string) error {
	if err := s.notifs.MarkRead(ctx, userID, uuid); err != nil {
		return platform.ErrInternal("DING.MARK_READ", err)
	}
	return nil
}

func (s *Service) MarkAllRead(ctx context.Context, userID int64) (int64, error) {
	n, err := s.notifs.MarkAllRead(ctx, userID)
	if err != nil {
		return 0, platform.ErrInternal("DING.MARK_ALL_READ", err)
	}
	return n, nil
}

func (s *Service) UnreadCount(ctx context.Context, userID int64) (int, error) {
	n, err := s.notifs.UnreadCount(ctx, userID)
	if err != nil {
		return 0, platform.ErrInternal("DING.UNREAD_COUNT", err)
	}
	return n, nil
}

func (s *Service) DeleteNotification(ctx context.Context, userID int64, uuid string) error {
	if err := s.notifs.Delete(ctx, userID, uuid); err != nil {
		return platform.ErrInternal("DING.DELETE_NOTIF", err)
	}
	return nil
}

// ── helpers ───────────────────────────────────────────────────────────

func validateTaskReq(title, prompt, schedule string) error {
	title = strings.TrimSpace(title)
	prompt = strings.TrimSpace(prompt)
	if title == "" {
		return platform.ErrBadRequest("DING.TITLE_REQUIRED", "title required", nil)
	}
	if prompt == "" {
		return platform.ErrBadRequest("DING.PROMPT_REQUIRED", "prompt required", nil)
	}
	if err := ValidateSchedule(schedule); err != nil {
		return platform.ErrBadRequest("DING.SCHEDULE_INVALID", err.Error(), nil)
	}
	return nil
}

func briefOf(s string, max int) string {
	s = strings.TrimSpace(s)
	if len([]rune(s)) <= max {
		return s
	}
	rs := []rune(s)
	return string(rs[:max]) + "…"
}
