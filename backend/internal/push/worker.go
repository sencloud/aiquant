package push

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/devices"
	"github.com/sencloud/finme-backend/internal/store"
)

// Worker 是 finme-server pusher 子命令背后的核心 loop。
//
// 职责：
//   1. 每 [Interval] 秒扫一批 notifications.push_status='pending'；
//   2. 按 user_id 反查所有有 push_token 的设备；
//   3. 选对应 platform 的 sender 真发；
//   4. 全部成功 → 标 'pushed'；任一失败但仍可重试 → 增 push_attempts 后继续 pending；
//      达到 maxAttempts 仍失败 → 标 'failed'；
//   5. 收到 token 失效信号 → devices.InvalidateToken。
type Worker struct {
	store         *store.Store
	devices       *devices.Service
	logger        *zerolog.Logger
	apns          PushSender
	fcm           PushSender
	interval      time.Duration
	batchSize     int
	maxAttempts   int
}

type WorkerConfig struct {
	APNs        PushSender
	FCM         PushSender
	Interval    time.Duration
	BatchSize   int
	MaxAttempts int
}

func NewWorker(st *store.Store, dev *devices.Service, l *zerolog.Logger, cfg WorkerConfig) *Worker {
	if cfg.Interval <= 0 {
		cfg.Interval = 5 * time.Second
	}
	if cfg.BatchSize <= 0 {
		cfg.BatchSize = 50
	}
	if cfg.MaxAttempts <= 0 {
		cfg.MaxAttempts = 5
	}
	if cfg.APNs == nil {
		cfg.APNs = MockPushSender{}
	}
	if cfg.FCM == nil {
		cfg.FCM = MockPushSender{}
	}
	return &Worker{
		store:       st,
		devices:     dev,
		logger:      l,
		apns:        cfg.APNs,
		fcm:         cfg.FCM,
		interval:    cfg.Interval,
		batchSize:   cfg.BatchSize,
		maxAttempts: cfg.MaxAttempts,
	}
}

// Run 阻塞运行直到 ctx 被取消。
func (w *Worker) Run(ctx context.Context) error {
	w.logger.Info().
		Dur("interval", w.interval).
		Int("batch", w.batchSize).
		Str("apns", w.apns.Name()).
		Str("fcm", w.fcm.Name()).
		Msg("pusher worker starting")

	tick := time.NewTicker(w.interval)
	defer tick.Stop()
	// 启动后立刻处理一轮
	w.processOnce(ctx)
	for {
		select {
		case <-ctx.Done():
			w.logger.Info().Msg("pusher worker stopped")
			return ctx.Err()
		case <-tick.C:
			w.processOnce(ctx)
		}
	}
}

type pendingNotif struct {
	ID            int64          `db:"id"`
	UserID        int64          `db:"user_id"`
	Topic         string         `db:"topic"`
	RefID         sql.NullString `db:"ref_id"`
	Title         string         `db:"title"`
	BodyBrief     string         `db:"body_brief"`
	PushAttempts  int            `db:"push_attempts"`
}

func (w *Worker) processOnce(ctx context.Context) {
	rows := []pendingNotif{}
	err := w.store.DB.SelectContext(ctx, &rows, `
		SELECT id, user_id, topic, ref_id, title, body_brief, push_attempts
		FROM notifications
		WHERE push_status='pending'
		ORDER BY id ASC
		LIMIT ?`, w.batchSize)
	if err != nil {
		w.logger.Error().Err(err).Msg("pusher: list pending failed")
		return
	}
	if len(rows) == 0 {
		return
	}
	for _, n := range rows {
		w.handleOne(ctx, n)
	}
}

func (w *Worker) handleOne(ctx context.Context, n pendingNotif) {
	tokens, err := w.listTokens(ctx, n.UserID)
	if err != nil {
		w.logger.Error().Err(err).Int64("notif", n.ID).Msg("pusher: list tokens")
		w.bumpAttempts(ctx, n)
		return
	}
	if len(tokens) == 0 {
		// 没有 push_token 的用户 —— 直接标 suppressed，避免反复轮询
		w.markStatus(ctx, n.ID, "suppressed", n.PushAttempts+1)
		w.logger.Debug().Int64("notif", n.ID).Msg("pusher: no token, suppressed")
		return
	}

	// 计算 badge = 该用户当前未读通知数（含本条 pending）。
	// 失败 fallback 为 1，至少让用户看到有红点提示。
	badge, err := w.unreadCountForUser(ctx, n.UserID)
	if err != nil {
		w.logger.Warn().Err(err).Int64("user", n.UserID).Msg("pusher: read unread_count failed")
		badge = 1
	}

	allOK := true
	for _, t := range tokens {
		sender := w.pickSender(t.platform)
		msg := Message{
			Token:    t.token,
			Platform: Platform(t.platform),
			Title:    n.Title,
			Body:     n.BodyBrief,
			Badge:    badge,
			Topic:    n.Topic,
			RefID:    n.RefID.String,
		}
		res, err := sender.Send(ctx, msg)
		switch {
		case err == nil && res != nil && res.Success:
			w.logger.Debug().Int64("notif", n.ID).Str("plat", t.platform).
				Str("detail", res.Detail).Msg("pusher: sent")
		case res != nil && res.TokenInvalid:
			_ = w.devices.InvalidateToken(ctx, t.token)
			w.logger.Warn().Int64("notif", n.ID).Str("plat", t.platform).
				Msg("pusher: token invalid, cleared")
		default:
			allOK = false
			detail := ""
			if res != nil {
				detail = res.Detail
			}
			w.logger.Warn().Int64("notif", n.ID).Str("plat", t.platform).
				Err(err).Str("detail", detail).Msg("pusher: send failed")
		}
	}

	if allOK {
		w.markStatus(ctx, n.ID, "pushed", n.PushAttempts+1)
		_, _ = w.store.DB.ExecContext(ctx,
			"UPDATE notifications SET pushed_at=? WHERE id=?",
			time.Now().UnixMilli(), n.ID)
	} else if n.PushAttempts+1 >= w.maxAttempts {
		w.markStatus(ctx, n.ID, "failed", n.PushAttempts+1)
	} else {
		w.bumpAttempts(ctx, n)
	}
}

func (w *Worker) markStatus(ctx context.Context, id int64, status string, attempts int) {
	_, err := w.store.DB.ExecContext(ctx,
		"UPDATE notifications SET push_status=?, push_attempts=? WHERE id=?",
		status, attempts, id)
	if err != nil {
		w.logger.Error().Err(err).Int64("notif", id).Msg("pusher: mark status failed")
	}
}

func (w *Worker) bumpAttempts(_ context.Context, n pendingNotif) {
	_, err := w.store.DB.ExecContext(context.Background(),
		"UPDATE notifications SET push_attempts=push_attempts+1 WHERE id=?", n.ID)
	if err != nil {
		w.logger.Error().Err(err).Int64("notif", n.ID).Msg("pusher: bump attempts")
	}
}

type tokenRow struct {
	token    string
	platform string
}

func (w *Worker) listTokens(ctx context.Context, userID int64) ([]tokenRow, error) {
	rows, err := w.store.DB.QueryContext(ctx,
		"SELECT push_token, platform FROM devices WHERE user_id=? AND push_token IS NOT NULL",
		userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []tokenRow{}
	for rows.Next() {
		var t tokenRow
		if err := rows.Scan(&t.token, &t.platform); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, nil
}

func (w *Worker) unreadCountForUser(ctx context.Context, userID int64) (int, error) {
	var n int
	err := w.store.DB.GetContext(ctx, &n,
		"SELECT COUNT(1) FROM notifications WHERE user_id=? AND read_at IS NULL", userID)
	return n, err
}

func (w *Worker) pickSender(platform string) PushSender {
	switch platform {
	case "ios":
		return w.apns
	case "android":
		return w.fcm
	default:
		return MockPushSender{}
	}
}

// Errors （留备外部断言用）
var (
	ErrNoPending = errors.New("no pending notifications")
)
