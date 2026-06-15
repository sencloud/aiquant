package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"
)

// EmailProvider 抽象验证码邮件发送（mock / resend ...）。
type EmailProvider interface {
	Send(ctx context.Context, toEmail, code string) error
	Name() string
}

// 邮箱验证码配额（与短信一致）。
const (
	emailCodeExpiry = 5 * time.Minute
	emailResendGap  = 60 * time.Second
	emailMaxAttempt = 3
)

// emailRegex 宽松校验（够用即可，真实有效性靠能否收到验证码）。
var emailRegex = regexp.MustCompile(`^[^@\s]+@[^@\s]+\.[^@\s]+$`)

// validateEmail 校验邮箱格式。
func validateEmail(e string) error {
	if len(e) == 0 || len(e) > 254 {
		return errors.New("email length invalid")
	}
	if !emailRegex.MatchString(e) {
		return errors.New("email format invalid")
	}
	return nil
}

// MockEmailProvider 把验证码打印到日志，dev/CI 用。
type MockEmailProvider struct {
	Out func(format string, args ...any)
}

func (m *MockEmailProvider) Name() string { return "mock" }

func (m *MockEmailProvider) Send(_ context.Context, toEmail, code string) error {
	if m.Out == nil {
		fmt.Printf("[email-mock] to=%s code=%s\n", toEmail, code)
	} else {
		m.Out("[email-mock] to=%s code=%s", toEmail, code)
	}
	return nil
}

// ResendProvider 通过 Resend API 发送验证码邮件。
//
// 文档：https://resend.com/docs/api-reference/emails/send-email
type ResendProvider struct {
	APIKey   string
	From     string // 发件地址，如 "喜宽 <no-reply@yourdomain.com>"
	FromName string
	httpc    *http.Client
}

// NewResendProvider 构造 Resend 发送器；缺 APIKey / From 直接报错。
func NewResendProvider(apiKey, from, fromName string) (*ResendProvider, error) {
	if strings.TrimSpace(apiKey) == "" || strings.TrimSpace(from) == "" {
		return nil, errors.New("resend email not fully configured (need api_key + from)")
	}
	return &ResendProvider{
		APIKey:   apiKey,
		From:     from,
		FromName: fromName,
		httpc:    &http.Client{Timeout: 10 * time.Second},
	}, nil
}

func (*ResendProvider) Name() string { return "resend" }

func (r *ResendProvider) Send(ctx context.Context, toEmail, code string) error {
	from := r.From
	if r.FromName != "" && !strings.Contains(from, "<") {
		from = fmt.Sprintf("%s <%s>", r.FromName, r.From)
	}
	body := map[string]any{
		"from":    from,
		"to":      []string{toEmail},
		"subject": fmt.Sprintf("【喜宽】登录验证码：%s", code),
		"html": fmt.Sprintf(
			`<div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;font-size:15px;color:#1f2937;line-height:1.7">`+
				`<p>你正在登录<strong>喜宽</strong>，验证码为：</p>`+
				`<p style="font-size:28px;font-weight:800;letter-spacing:6px;color:#D97706;margin:16px 0">%s</p>`+
				`<p style="color:#6b7280;font-size:13px">验证码 5 分钟内有效，请勿向他人泄露。若非本人操作请忽略本邮件。</p>`+
				`</div>`, code),
		"text": fmt.Sprintf("你的喜宽登录验证码：%s（5 分钟内有效，请勿泄露）。", code),
	}
	raw, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://api.resend.com/emails", bytes.NewReader(raw))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+r.APIKey)
	req.Header.Set("Content-Type", "application/json")
	resp, err := r.httpc.Do(req)
	if err != nil {
		return fmt.Errorf("resend http: %w", err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("resend api status %d: %s", resp.StatusCode, string(respBody))
	}
	return nil
}
