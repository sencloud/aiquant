package auth

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"time"
)

// SMSProvider 抽象短信发送（mock / aliyun / tencent ...）
type SMSProvider interface {
	Send(ctx context.Context, phone, code string) error
	Name() string
}

// MockSMSProvider 把验证码打印到日志，dev/CI 用。
type MockSMSProvider struct {
	Out func(format string, args ...any)
}

func (m *MockSMSProvider) Name() string { return "mock" }

func (m *MockSMSProvider) Send(_ context.Context, phone, code string) error {
	if m.Out == nil {
		fmt.Printf("[sms-mock] phone=%s code=%s\n", phone, code)
	} else {
		m.Out("[sms-mock] phone=%s code=%s", phone, code)
	}
	return nil
}

// SMS 配额（粗粒度，进程内即可；持久化的精细限流后续接 ratelimit 模块）
const (
	smsCodeExpiry = 5 * time.Minute
	smsResendGap  = 60 * time.Second
	smsMaxAttempt = 3
)

// generateCode 6 位数字，零起始保留前导零。
func generateCode() string {
	n, _ := rand.Int(rand.Reader, big.NewInt(1_000_000))
	return fmt.Sprintf("%06d", n.Int64())
}

// 验证手机号格式（仅本期：中国大陆 11 位 + 1 开头）。
func validateChinaPhone(p string) error {
	if len(p) != 11 {
		return errors.New("phone must be 11 digits")
	}
	if p[0] != '1' {
		return errors.New("phone must start with 1")
	}
	for _, c := range p {
		if c < '0' || c > '9' {
			return errors.New("phone must be all digits")
		}
	}
	return nil
}
