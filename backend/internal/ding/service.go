package ding

import (
	"context"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

// Service 是 DING 模块对外的总入口。
//
// 当前阶段（W3 第一阶段）：
//   - Tasks 全 CRUD：客户端把本地任务同步到服务端；
//   - Runs：客户端在本地执行完后通过 ReportRun 上报；
//   - Notifications：服务端读 / 标读，是 inbox 的唯一真源。
//
// W3 第二阶段：服务端 scheduler + LLM 执行 + APNs 推送。
type Service struct {
	cfg *platform.Config

	tasks  *TaskRepo
	runs   *RunRepo
	notifs *NotificationRepo
}

func NewService(st *store.Store, cfg *platform.Config) *Service {
	return &Service{
		cfg:    cfg,
		tasks:  NewTaskRepo(st),
		runs:   NewRunRepo(st),
		notifs: NewNotificationRepo(st),
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
