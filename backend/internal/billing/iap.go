package billing

import (
	"context"
	"errors"
	"fmt"
	"strings"
)

// IAPResult 是 IAP receipt 验签后服务端关心的字段。
type IAPResult struct {
	TransactionID string // 苹果端原始 transaction_id（必须；用于幂等）
	ProductID     string // 用户购买的 product_id（与 SKU.AppleProductID 对齐）
	Quantity      int64  // 一般 1
	PurchasedAtMs int64  // 购买时间（unix ms）
}

// IAPVerifier 把 IAP 凭证验签的细节抽象到接口后面。
//
// 实现：
//   - MockIAPVerifier  ：dev 模式专用，只校验 receipt 格式
//   - AppleIAPVerifier ：生产模式，调 App Store Server API（待接入）
type IAPVerifier interface {
	Verify(ctx context.Context, jwsReceipt string) (*IAPResult, error)
	Name() string
}

// ErrIAPInvalid 表示 receipt 验签失败 / 非法。
var ErrIAPInvalid = errors.New("iap receipt invalid")

// MockIAPVerifier — dev 模式：直接接受 "mock_<txid>_<product_id>_<purchased_ms>" 的拼装。
//
// 生产环境必须切换到 AppleIAPVerifier；MockIAP 不能进 prod。
type MockIAPVerifier struct{}

func (MockIAPVerifier) Name() string { return "mock" }

func (MockIAPVerifier) Verify(_ context.Context, jws string) (*IAPResult, error) {
	if !strings.HasPrefix(jws, "mock_") {
		return nil, fmt.Errorf("%w: not a mock receipt", ErrIAPInvalid)
	}
	parts := strings.Split(strings.TrimPrefix(jws, "mock_"), "_")
	if len(parts) < 2 {
		return nil, fmt.Errorf("%w: malformed mock receipt", ErrIAPInvalid)
	}
	res := &IAPResult{
		TransactionID: parts[0],
		ProductID:     parts[1],
		Quantity:      1,
	}
	if len(parts) >= 3 {
		var ms int64
		_, _ = fmt.Sscanf(parts[2], "%d", &ms)
		res.PurchasedAtMs = ms
	}
	return res, nil
}

// AppleIAPVerifier — 调 App Store Server API。
//
// 接入要点（生产前完成）：
//  1. App Store Connect → Keys → 生成 In-App Purchase Key（.p8）+ Key ID + Issuer ID；
//  2. 服务端持有 .p8、KeyID、IssuerID、BundleID；
//  3. 用 ES256 自签 client JWT，调用：
//     POST https://api.storekit.itunes.apple.com/inApps/v1/transactions/{transactionId}
//     - 请求 header: Authorization: Bearer <client_jwt>
//     - 响应 signedTransactionInfo (JWS) → 用 Apple Root CA 校验签名 → 解析得到 ProductID 等
//  4. 校验 transactionInfo.bundleId == 我们的 bundleId、transactionInfo.appAccountToken
//     等字段。
//
// 当前阶段只留接口骨架，避免在没有 Key 的情况下编译失败。
type AppleIAPVerifier struct {
	BundleID string
	IssuerID string
	KeyID    string
	P8PEM    string // .p8 文件的 PEM 文本
}

func (AppleIAPVerifier) Name() string { return "apple" }

func (a AppleIAPVerifier) Verify(_ context.Context, _ string) (*IAPResult, error) {
	if a.IssuerID == "" || a.KeyID == "" || a.P8PEM == "" {
		return nil, errors.New("apple iap key not configured (set issuer_id / key_id / p8 in config.apple_iap)")
	}
	return nil, errors.New("AppleIAPVerifier not yet implemented; please switch to mock or wire up App Store Server API")
}
