package billing

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

// appleNotificationPayload 是 App Store Server Notifications V2 的最外层
// signedPayload 解出来的 JSON 形态。
//
// Apple 文档参考：https://developer.apple.com/documentation/appstoreservernotifications
type appleNotificationPayload struct {
	NotificationType string                  `json:"notificationType"`
	Subtype          string                  `json:"subtype,omitempty"`
	NotificationUUID string                  `json:"notificationUUID,omitempty"`
	Data             appleNotificationData   `json:"data,omitempty"`
	Version          string                  `json:"version,omitempty"`
	SignedDate       int64                   `json:"signedDate,omitempty"`
}

type appleNotificationData struct {
	AppAppleID            int64  `json:"appAppleId,omitempty"`
	BundleID              string `json:"bundleId,omitempty"`
	Environment           string `json:"environment,omitempty"`
	SignedTransactionInfo string `json:"signedTransactionInfo,omitempty"`
	SignedRenewalInfo     string `json:"signedRenewalInfo,omitempty"`
}

// decodeAppleNotificationPayload 解析 signedPayload（JWS）的 payload 段。
//
// 签名校验：因为我们紧接着会用 transactionId 调 App Store Server API 反查，
// 攻击者无法伪造一个 Apple 服务端真实存在的 transactionId，构成天然的
// 第二因子校验。如未来引入 Apple Root CA 链验签，再补 jwt.Parse + 自带 cert 链。
func decodeAppleNotificationPayload(signedPayload string) (*appleNotificationPayload, error) {
	parts := strings.Split(strings.TrimSpace(signedPayload), ".")
	if len(parts) != 3 {
		return nil, fmt.Errorf("not a JWS: %d parts", len(parts))
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, fmt.Errorf("base64 payload: %w", err)
	}
	var p appleNotificationPayload
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, fmt.Errorf("json payload: %w", err)
	}
	if p.NotificationType == "" {
		return nil, errors.New("notificationType missing")
	}
	return &p, nil
}
