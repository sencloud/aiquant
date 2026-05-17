package platform

import (
	"crypto/rand"
	"encoding/hex"
	"time"

	"github.com/google/uuid"
)

// NewUUID 返回 RFC4122 v4 字符串 — 用于业务实体外部 id（user.uuid 等）。
func NewUUID() string {
	return uuid.NewString()
}

// NewOrderNo 生成订单号：YYYYMMDDHHmmss + 8 字节随机十六进制。
func NewOrderNo(now time.Time) string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return now.UTC().Format("20060102150405") + hex.EncodeToString(b)
}

// NewRequestID 生成 8 字节请求 id（日志关联用，足够了）。
func NewRequestID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
