// Package push 实现"通知 → APNs/FCM 推送"的发送端。
//
// 抽象 [PushSender] 使生产 / 开发环境可以切换：
//   - Mock：dev 直接成功（不真发）；
//   - Apple：APNs HTTP/2 Provider API；
//   - FCM：Firebase Cloud Messaging HTTP v1。
//
// 真实接入清单（生产前补齐）：
//   - APNs：Apple Developer → Keys → 申请 APNs Auth Key (.p8) + Key ID + Team ID
//   - FCM：Firebase Console → Service Account JSON
package push

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/net/http2"
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
	// Badge 是 iOS 桌面图标右上角红点数字。0 表示清零；
	// < 0 表示该字段不写入 payload（极少用到，目前不开放给上层）。
	Badge int
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

// AppleAPNsSender — APNs HTTP/2 Provider API。
//
// 启用条件：BundleID + KeyID + TeamID + .p8 PEM。
type AppleAPNsSender struct {
	BundleID   string
	KeyID      string
	TeamID     string
	UseSandbox bool

	signer *ecdsa.PrivateKey
	httpc  *http.Client

	mu  sync.Mutex
	tok string
	tAt time.Time
}

// NewAPNsSender 用 .p8 文本初始化。
func NewAPNsSender(bundleID, teamID, keyID, p8PEM string, useSandbox bool) (*AppleAPNsSender, error) {
	if bundleID == "" || teamID == "" || keyID == "" || p8PEM == "" {
		return nil, errors.New("apns key not fully configured")
	}
	priv, err := parseECPrivateKeyPEM([]byte(p8PEM))
	if err != nil {
		return nil, fmt.Errorf("apns parse .p8: %w", err)
	}
	tr := &http2.Transport{
		TLSClientConfig: &tls.Config{NextProtos: []string{"h2"}},
	}
	return &AppleAPNsSender{
		BundleID:   bundleID,
		KeyID:      keyID,
		TeamID:     teamID,
		UseSandbox: useSandbox,
		signer:     priv,
		httpc:      &http.Client{Transport: tr, Timeout: 15 * time.Second},
	}, nil
}

// LoadP8 读取 .p8 文件 → PEM 文本。
func LoadP8(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func (*AppleAPNsSender) Name() string { return "apns" }

func (s *AppleAPNsSender) Send(ctx context.Context, msg Message) (*Result, error) {
	if msg.Token == "" {
		return &Result{Detail: "empty token"}, errors.New("empty token")
	}
	tok, err := s.providerToken()
	if err != nil {
		return nil, err
	}
	host := "https://api.push.apple.com"
	if s.UseSandbox {
		host = "https://api.sandbox.push.apple.com"
	}
	body := apnsPayload(msg)
	url := host + "/3/device/" + msg.Token
	req, _ := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(body))
	req.Header.Set("authorization", "bearer "+tok)
	req.Header.Set("apns-topic", s.BundleID)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")
	req.Header.Set("content-type", "application/json")

	resp, err := s.httpc.Do(req)
	if err != nil {
		return &Result{Detail: err.Error()}, fmt.Errorf("apns http: %w", err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
	switch resp.StatusCode {
	case http.StatusOK:
		return &Result{Success: true, Detail: "apns ok"}, nil
	case http.StatusGone, http.StatusBadRequest, http.StatusForbidden:
		// 410 Gone => Unregistered；400/403 里 reason=BadDeviceToken/Unregistered
		reason := apnsReason(respBody)
		invalid := resp.StatusCode == http.StatusGone ||
			reason == "BadDeviceToken" || reason == "Unregistered" ||
			reason == "DeviceTokenNotForTopic"
		return &Result{
			TokenInvalid: invalid,
			Detail:       fmt.Sprintf("apns %d %s", resp.StatusCode, reason),
		}, nil
	default:
		return &Result{Detail: fmt.Sprintf("apns %d %s", resp.StatusCode, string(respBody))},
			fmt.Errorf("apns status %d", resp.StatusCode)
	}
}

func apnsReason(body []byte) string {
	var r struct {
		Reason string `json:"reason"`
	}
	_ = json.Unmarshal(body, &r)
	return r.Reason
}

func apnsPayload(m Message) []byte {
	aps := map[string]any{
		"alert": map[string]string{
			"title": m.Title,
			"body":  m.Body,
		},
		"sound": "default",
	}
	// 显式写入 badge：>=0 都写（0 用于清零角标）。<0 表示不写。
	if m.Badge >= 0 {
		aps["badge"] = m.Badge
	}
	out := map[string]any{"aps": aps}
	if m.Topic != "" {
		out["topic"] = m.Topic
	}
	if m.RefID != "" {
		out["ref_id"] = m.RefID
	}
	b, _ := json.Marshal(out)
	return b
}

// providerToken 自签 ES256 provider token，缓存 50 分钟。
func (s *AppleAPNsSender) providerToken() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.tok != "" && time.Since(s.tAt) < 50*time.Minute {
		return s.tok, nil
	}
	now := time.Now()
	tk := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.MapClaims{
		"iss": s.TeamID,
		"iat": now.Unix(),
	})
	tk.Header["kid"] = s.KeyID
	tk.Header["typ"] = "JWT"
	signed, err := tk.SignedString(s.signer)
	if err != nil {
		return "", fmt.Errorf("sign apns provider token: %w", err)
	}
	s.tok = signed
	s.tAt = now
	return signed, nil
}

// FCMSender — Firebase Cloud Messaging HTTP v1。
//
// 工作流：
//  1. 用 service account JSON 里的 RSA 私钥签 JWT；
//  2. POST https://oauth2.googleapis.com/token 换 access_token；
//  3. POST https://fcm.googleapis.com/v1/projects/{project_id}/messages:send。
type FCMSender struct {
	ProjectID  string
	ClientMail string
	signer     *rsa.PrivateKey

	httpc *http.Client

	mu     sync.Mutex
	access string
	expAt  time.Time
}

// NewFCMSender 解析 service account JSON 并初始化 sender。
func NewFCMSender(projectID, serviceAccountJSON string) (*FCMSender, error) {
	if projectID == "" || serviceAccountJSON == "" {
		return nil, errors.New("fcm not fully configured")
	}
	var sa struct {
		Type                    string `json:"type"`
		ProjectID               string `json:"project_id"`
		PrivateKey              string `json:"private_key"`
		PrivateKeyID            string `json:"private_key_id"`
		ClientEmail             string `json:"client_email"`
		TokenURI                string `json:"token_uri"`
		AuthProviderX509CertURL string `json:"auth_provider_x509_cert_url"`
	}
	if err := json.Unmarshal([]byte(serviceAccountJSON), &sa); err != nil {
		return nil, fmt.Errorf("fcm parse service account: %w", err)
	}
	if sa.PrivateKey == "" || sa.ClientEmail == "" {
		return nil, errors.New("fcm service account missing private_key or client_email")
	}
	priv, err := parseRSAPrivateKeyPEM([]byte(sa.PrivateKey))
	if err != nil {
		return nil, fmt.Errorf("fcm parse private key: %w", err)
	}
	return &FCMSender{
		ProjectID:  projectID,
		ClientMail: sa.ClientEmail,
		signer:     priv,
		httpc:      &http.Client{Timeout: 15 * time.Second},
	}, nil
}

// LoadServiceAccountJSON 读取 JSON 文件 → 文本。
func LoadServiceAccountJSON(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func (*FCMSender) Name() string { return "fcm" }

func (s *FCMSender) Send(ctx context.Context, msg Message) (*Result, error) {
	if msg.Token == "" {
		return &Result{Detail: "empty token"}, errors.New("empty token")
	}
	tok, err := s.accessToken(ctx)
	if err != nil {
		return nil, err
	}
	body := fcmPayload(msg)
	url := "https://fcm.googleapis.com/v1/projects/" + s.ProjectID + "/messages:send"
	req, _ := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(body))
	req.Header.Set("authorization", "Bearer "+tok)
	req.Header.Set("content-type", "application/json")

	resp, err := s.httpc.Do(req)
	if err != nil {
		return &Result{Detail: err.Error()}, fmt.Errorf("fcm http: %w", err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
	switch resp.StatusCode {
	case http.StatusOK:
		return &Result{Success: true, Detail: "fcm ok"}, nil
	case http.StatusNotFound, http.StatusBadRequest, http.StatusForbidden:
		errCode := fcmErrorCode(respBody)
		invalid := errCode == "UNREGISTERED" || errCode == "INVALID_ARGUMENT" || errCode == "NOT_FOUND"
		return &Result{
			TokenInvalid: invalid,
			Detail:       fmt.Sprintf("fcm %d %s", resp.StatusCode, errCode),
		}, nil
	default:
		return &Result{Detail: fmt.Sprintf("fcm %d %s", resp.StatusCode, string(respBody))},
			fmt.Errorf("fcm status %d", resp.StatusCode)
	}
}

func fcmErrorCode(body []byte) string {
	var r struct {
		Error struct {
			Status  string `json:"status"`
			Message string `json:"message"`
			Details []struct {
				ErrorCode string `json:"errorCode"`
			} `json:"details"`
		} `json:"error"`
	}
	_ = json.Unmarshal(body, &r)
	for _, d := range r.Error.Details {
		if d.ErrorCode != "" {
			return d.ErrorCode
		}
	}
	return r.Error.Status
}

func fcmPayload(m Message) []byte {
	data := map[string]string{}
	if m.Topic != "" {
		data["topic"] = m.Topic
	}
	if m.RefID != "" {
		data["ref_id"] = m.RefID
	}
	out := map[string]any{
		"message": map[string]any{
			"token": m.Token,
			"notification": map[string]string{
				"title": m.Title,
				"body":  m.Body,
			},
			"data": data,
		},
	}
	b, _ := json.Marshal(out)
	return b
}

// accessToken 用 service account 自签 JWT 换 OAuth2 access token，缓存 50 分钟。
func (s *FCMSender) accessToken(ctx context.Context) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.access != "" && time.Until(s.expAt) > 5*time.Minute {
		return s.access, nil
	}
	now := time.Now()
	claims := jwt.MapClaims{
		"iss":   s.ClientMail,
		"sub":   s.ClientMail,
		"scope": "https://www.googleapis.com/auth/firebase.messaging",
		"aud":   "https://oauth2.googleapis.com/token",
		"iat":   now.Unix(),
		"exp":   now.Add(60 * time.Minute).Unix(),
	}
	tk := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	tk.Header["typ"] = "JWT"
	signed, err := tk.SignedString(s.signer)
	if err != nil {
		return "", fmt.Errorf("sign fcm jwt: %w", err)
	}
	form := strings.NewReader(
		"grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=" + signed,
	)
	req, _ := http.NewRequestWithContext(ctx, "POST", "https://oauth2.googleapis.com/token", form)
	req.Header.Set("content-type", "application/x-www-form-urlencoded")
	resp, err := s.httpc.Do(req)
	if err != nil {
		return "", fmt.Errorf("fcm token http: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("fcm token status %d: %s", resp.StatusCode, string(body))
	}
	var r struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return "", fmt.Errorf("fcm token parse: %w", err)
	}
	s.access = r.AccessToken
	if r.ExpiresIn > 0 {
		s.expAt = now.Add(time.Duration(r.ExpiresIn) * time.Second)
	} else {
		s.expAt = now.Add(50 * time.Minute)
	}
	return s.access, nil
}

func parseECPrivateKeyPEM(b []byte) (*ecdsa.PrivateKey, error) {
	block, _ := pem.Decode(b)
	if block == nil {
		return nil, errors.New("not a PEM file")
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	priv, ok := key.(*ecdsa.PrivateKey)
	if !ok {
		return nil, errors.New("not an ECDSA private key")
	}
	return priv, nil
}

func parseRSAPrivateKeyPEM(b []byte) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode(b)
	if block == nil {
		return nil, errors.New("not a PEM file")
	}
	if k, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
		return k, nil
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	priv, ok := key.(*rsa.PrivateKey)
	if !ok {
		return nil, errors.New("not an RSA private key")
	}
	return priv, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
