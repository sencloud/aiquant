// Package devices 维护用户的设备 + 推送 token。
package devices

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/sencloud/finme-backend/internal/store"
)

type Platform string

const (
	IOS     Platform = "ios"
	Android Platform = "android"
)

// IsValid 防止客户端瞎传一个 platform 字符串。
func (p Platform) IsValid() bool {
	return p == IOS || p == Android
}

// Service 提供设备登记的接口。
type Service struct {
	st *store.Store
}

func NewService(st *store.Store) *Service {
	return &Service{st: st}
}

// UpsertInput 是 PUT /devices 的载荷。
type UpsertInput struct {
	UserID     int64
	DeviceID   string
	Platform   Platform
	PushToken  string
	AppVersion string
	IP         string
}

// Upsert 创建或更新一条设备记录（按 (user_id, device_id) 唯一）。
func (s *Service) Upsert(ctx context.Context, in UpsertInput) error {
	now := time.Now().UnixMilli()
	pushAt := sql.NullInt64{}
	if in.PushToken != "" {
		pushAt = sql.NullInt64{Int64: now, Valid: true}
	}
	_, err := s.st.DB.ExecContext(ctx, `
		INSERT INTO devices(user_id, device_id, platform, push_token, push_token_at, app_version, last_active_at)
		VALUES(?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(user_id, device_id) DO UPDATE SET
			platform = excluded.platform,
			push_token = excluded.push_token,
			push_token_at = excluded.push_token_at,
			app_version = excluded.app_version,
			last_active_at = excluded.last_active_at`,
		in.UserID, in.DeviceID, string(in.Platform),
		nullStr(in.PushToken), pushAt,
		nullStr(in.AppVersion), now,
	)
	return err
}

// InvalidateToken 推送时收到 410 Gone 等失效信号后调用，把对应 token 置空。
func (s *Service) InvalidateToken(ctx context.Context, pushToken string) error {
	if pushToken == "" {
		return errors.New("empty push token")
	}
	_, err := s.st.DB.ExecContext(ctx,
		"UPDATE devices SET push_token=NULL, push_token_at=NULL WHERE push_token=?",
		pushToken)
	return err
}

func nullStr(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: s, Valid: true}
}
