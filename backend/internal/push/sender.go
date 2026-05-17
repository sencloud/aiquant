// Package push 实现"通知 → APNs/FCM 推送"的发送端。
//
// 抽象 [PushSender] 使生产 / 开发环境可以切换：
//   - Mock：dev 直接成功（不真发）；
//   - Apple：APNs HTTP/2 Provider API；
//   - FCM：Firebase Cloud Messaging HTTP v1。
//
// 真实接入清单（生产前补齐）：
//   - APNs：App Store Connect → Keys → 申请 APNs Auth Key (.p8) + Key ID + Team ID
//   - FCM：Firebase Console → Service Account JSON
package push

import (
	"context"
	"errors"
	"fmt"
)

type Platform string

const (
	IOS     Platform = "ios"
	Android Platform = "android"
)

// Message 是要发出去的一次推送。
type Message struct {
	Token    string
	Platform Platform
	Title    string
	Body     string
	// 业务参数透传到 payload，客户端收到后路由到 inbox 详情。
	Topic string
	RefID string
}

// Result 是单次推送的回执。
type Result struct {
	Success      bool
	TokenInvalid bool   // 收到 410/Unregistered 等：上层要把该 token 标失效
	Detail       string // 可读消息（用于审计 / 排查）
}

// PushSender 把"按 token 发一条消息"封装为接口。
type PushSender interface {
	Name() string
	Send(ctx context.Context, msg Message) (*Result, error)
}

// MockPushSender — dev 模式：不真发，只在结构层面校验后返回成功。
type MockPushSender struct{}

func (MockPushSender) Name() string { return "mock" }

func (MockPushSender) Send(_ context.Context, msg Message) (*Result, error) {
	if msg.Token == "" {
		return &Result{Success: false, Detail: "empty token"}, errors.New("empty token")
	}
	if msg.Title == "" {
		return &Result{Success: false, Detail: "empty title"}, errors.New("empty title")
	}
	return &Result{
		Success: true,
		Detail:  fmt.Sprintf("[mock] sent to %s/%s: %s", msg.Platform, truncate(msg.Token, 8), msg.Title),
	}, nil
}

// AppleAPNsSender — APNs HTTP/2 Provider API（生产实现待接入）。
//
// 接入提示（代码中 TODO 标记的位置）：
//  1. 用 .p8 + KeyID + TeamID 自签 ES256 JWT；
//  2. POST https://api.push.apple.com/3/device/<token>
//     Headers: Authorization: Bearer <jwt> / apns-topic: <bundle_id> / apns-push-type: alert
//     Body: { "aps": { "alert": { "title": ..., "body": ... }, "sound": "default" }, "topic": ... }
//  3. 返回状态码：200 成功 / 410 token 失效 → Result.TokenInvalid=true
type AppleAPNsSender struct {
	BundleID string
	KeyID    string
	TeamID   string
	P8PEM    string
	UseSandbox bool
}

func (AppleAPNsSender) Name() string { return "apns" }

func (s AppleAPNsSender) Send(_ context.Context, _ Message) (*Result, error) {
	if s.KeyID == "" || s.TeamID == "" || s.P8PEM == "" {
		return nil, errors.New("apns key not configured")
	}
	return nil, errors.New("AppleAPNsSender not yet implemented; configure config.apns and replace this stub")
}

// FCMSender — Firebase Cloud Messaging HTTP v1（生产实现待接入）。
type FCMSender struct {
	ProjectID          string
	ServiceAccountJSON string
}

func (FCMSender) Name() string { return "fcm" }

func (s FCMSender) Send(_ context.Context, _ Message) (*Result, error) {
	if s.ProjectID == "" || s.ServiceAccountJSON == "" {
		return nil, errors.New("fcm not configured")
	}
	return nil, errors.New("FCMSender not yet implemented; configure config.fcm and replace this stub")
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
