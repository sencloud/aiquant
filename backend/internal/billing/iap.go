package billing

import (
	"context"
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/base64"
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
)

// IAPResult 是 IAP receipt 验签后服务端关心的字段。
type IAPResult struct {
	TransactionID string // 苹果端原始 transaction_id（必须；用于幂等）
	ProductID     string // 用户购买的 product_id（与 SKU.AppleProductID 对齐）
	Quantity      int64  // 一般 1
	PurchasedAtMs int64  // 购买时间（unix ms）
	BundleID      string // 校验用：必须等于 SKU.BundleID
	Environment   string // Apple 返回的 "Sandbox" 或 "Production"
}

// IAPVerifier 把 IAP 凭证验签的细节抽象到接口后面。
//
// 实现：
//   - MockIAPVerifier  ：dev 模式专用，只校验 receipt 格式
//   - AppleIAPVerifier ：生产模式，调 App Store Server API
type IAPVerifier interface {
	Verify(ctx context.Context, jwsReceipt string) (*IAPResult, error)
	Name() string
}

// ErrIAPInvalid 表示 receipt 验签失败 / 非法。
var ErrIAPInvalid = errors.New("iap receipt invalid")

// DisabledIAPVerifier — prod 还没配齐 .p8 时的占位实现：服务能起来，但
// /v1/credits/iap/verify 一律拒绝。等 apple_iap 配置补全 + 重启即可切真实。
type DisabledIAPVerifier struct{}

func (DisabledIAPVerifier) Name() string { return "disabled" }

func (DisabledIAPVerifier) Verify(_ context.Context, _ string) (*IAPResult, error) {
	return nil, fmt.Errorf("%w: apple_iap not configured on server", ErrIAPInvalid)
}

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

// AppleIAPVerifier 通过 App Store Server API 校验客户端上送的 IAP 凭证。
//
// 客户端有两种上送形态：
//
//  1. **transactionId**（推荐 / 默认）：StoreKit 2 在 PurchaseDetails 里有
//     `Transaction.id`；服务端按 ID 调 GET /inApps/v1/transactions/{id}
//     获取权威 signedTransactionInfo（JWS），再解出 productId、bundleId、
//     purchaseDate、quantity 等字段。Apple 服务端是来源可信，因此 JWS 的
//     payload 直接 base64 解析；Apple Root CA 链验签暂不强制（HTTPS+JWT
//     已经是等价信任边界）。
//
//  2. **JWS receipt**（当客户端只有 verificationData.serverVerificationData
//     时也支持）：先解码 JWS payload 拿到 transactionId，再走形态 1 流程。
//
// 选用形态 1 是因为 Apple 服务端持有真实状态，可发现 refund、family-share、
// 撤销等本地解析看不到的事件。
type AppleIAPVerifier struct {
	BundleID string
	IssuerID string
	KeyID    string
	signer   *ecdsa.PrivateKey
	envMode  string // "production" / "sandbox" / "auto"

	httpc *http.Client

	mu    sync.Mutex
	jwt   string
	jwtAt time.Time
}

// NewAppleIAPVerifier 用 .p8 文本初始化 verifier。
func NewAppleIAPVerifier(bundleID, issuerID, keyID, p8PEM, env string) (*AppleIAPVerifier, error) {
	if bundleID == "" || issuerID == "" || keyID == "" || p8PEM == "" {
		return nil, errors.New("apple iap key not fully configured")
	}
	priv, err := parseECPrivateKeyPEM([]byte(p8PEM))
	if err != nil {
		return nil, fmt.Errorf("apple iap parse .p8: %w", err)
	}
	mode := strings.ToLower(strings.TrimSpace(env))
	if mode == "" {
		mode = "auto"
	}
	return &AppleIAPVerifier{
		BundleID: bundleID,
		IssuerID: issuerID,
		KeyID:    keyID,
		signer:   priv,
		envMode:  mode,
		httpc:    &http.Client{Timeout: 10 * time.Second},
	}, nil
}

// LoadAppleP8 读取 .p8 文件 → 直接返回 PEM 文本。
func LoadAppleP8(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func (*AppleIAPVerifier) Name() string { return "apple" }

// Verify 核心入口。
func (a *AppleIAPVerifier) Verify(ctx context.Context, receipt string) (*IAPResult, error) {
	receipt = strings.TrimSpace(receipt)
	if receipt == "" {
		return nil, fmt.Errorf("%w: empty receipt", ErrIAPInvalid)
	}
	txID := receipt
	// 如果客户端发的是 JWS（含两个 '.'），先解出 transactionId
	if strings.Count(receipt, ".") == 2 {
		extracted, err := extractTxIDFromJWS(receipt)
		if err != nil {
			return nil, fmt.Errorf("%w: parse jws: %v", ErrIAPInvalid, err)
		}
		txID = extracted
	}

	signedInfo, env, err := a.fetchTransaction(ctx, txID)
	if err != nil {
		return nil, err
	}
	payload, err := decodeJWSPayload(signedInfo)
	if err != nil {
		return nil, fmt.Errorf("%w: decode signedTransactionInfo: %v", ErrIAPInvalid, err)
	}

	if payload.BundleID != a.BundleID {
		return nil, fmt.Errorf("%w: bundleId mismatch (got %q, want %q)",
			ErrIAPInvalid, payload.BundleID, a.BundleID)
	}
	if payload.TransactionID == "" {
		payload.TransactionID = txID
	}
	if payload.ProductID == "" {
		return nil, fmt.Errorf("%w: empty productId", ErrIAPInvalid)
	}

	q := int64(1)
	if payload.Quantity > 0 {
		q = payload.Quantity
	}
	return &IAPResult{
		TransactionID: payload.TransactionID,
		ProductID:     payload.ProductID,
		Quantity:      q,
		PurchasedAtMs: payload.PurchaseDate,
		BundleID:      payload.BundleID,
		Environment:   env,
	}, nil
}

// fetchTransaction 调 App Store Server API；环境 auto 时先 production 后 sandbox。
//
// auto 触发 sandbox fallback 的两种情况：
//   - errAppStoreNotFound：production 上找不到这笔 txID（最常见）
//   - errAppStoreUnauthorized：production 上 401，通常是 key 是 Sandbox 专属
//     （TestFlight 阶段的开发 key 未授权 prod 调用），生产上线时再换 prod key。
func (a *AppleIAPVerifier) fetchTransaction(ctx context.Context, txID string) (string, string, error) {
	switch a.envMode {
	case "production":
		return a.callAPI(ctx, "https://api.storekit.itunes.apple.com", txID)
	case "sandbox":
		return a.callAPI(ctx, "https://api.storekit-sandbox.itunes.apple.com", txID)
	default:
		signed, env, err := a.callAPI(ctx, "https://api.storekit.itunes.apple.com", txID)
		if err == nil {
			return signed, env, nil
		}
		if errors.Is(err, errAppStoreNotFound) || errors.Is(err, errAppStoreUnauthorized) {
			return a.callAPI(ctx, "https://api.storekit-sandbox.itunes.apple.com", txID)
		}
		return "", "", err
	}
}

var (
	errAppStoreNotFound     = errors.New("apple iap transaction not found in this environment")
	errAppStoreUnauthorized = errors.New("apple iap key not authorized in this environment")
)

type asTransactionResp struct {
	SignedTransactionInfo string `json:"signedTransactionInfo"`
	Environment           string `json:"environment"`
}

func (a *AppleIAPVerifier) callAPI(ctx context.Context, base, txID string) (string, string, error) {
	tok, err := a.providerToken()
	if err != nil {
		return "", "", err
	}
	url := base + "/inApps/v1/transactions/" + txID
	req, _ := http.NewRequestWithContext(ctx, "GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	resp, err := a.httpc.Do(req)
	if err != nil {
		return "", "", fmt.Errorf("apple iap http: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode == http.StatusNotFound || resp.StatusCode == http.StatusGone {
		return "", "", errAppStoreNotFound
	}
	if resp.StatusCode == http.StatusUnauthorized {
		return "", "", errAppStoreUnauthorized
	}
	if resp.StatusCode != http.StatusOK {
		return "", "", fmt.Errorf("apple iap api status %d: %s", resp.StatusCode, string(body))
	}
	var r asTransactionResp
	if err := json.Unmarshal(body, &r); err != nil {
		return "", "", fmt.Errorf("apple iap parse resp: %w", err)
	}
	if r.SignedTransactionInfo == "" {
		return "", "", errors.New("apple iap empty signedTransactionInfo")
	}
	return r.SignedTransactionInfo, r.Environment, nil
}

// providerToken 自签 ES256 JWT，作为 App Store Server API 的访问凭证。
//
// 缓存 50 分钟（Apple 文档要求 <60 分钟）。
func (a *AppleIAPVerifier) providerToken() (string, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.jwt != "" && time.Since(a.jwtAt) < 50*time.Minute {
		return a.jwt, nil
	}
	now := time.Now()
	tk := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.MapClaims{
		"iss":   a.IssuerID,
		"iat":   now.Unix(),
		"exp":   now.Add(55 * time.Minute).Unix(),
		"aud":   "appstoreconnect-v1",
		"bid":   a.BundleID,
		"nonce": fmt.Sprintf("%d", now.UnixNano()),
	})
	tk.Header["kid"] = a.KeyID
	tk.Header["typ"] = "JWT"
	signed, err := tk.SignedString(a.signer)
	if err != nil {
		return "", fmt.Errorf("sign apple iap jwt: %w", err)
	}
	a.jwt = signed
	a.jwtAt = now
	return signed, nil
}

// signedTransactionPayload 是 JWS payload 中我们关心的字段。
//
// 完整字段见 Apple JWSTransactionDecodedPayload；这里取最常用的子集。
type signedTransactionPayload struct {
	TransactionID string `json:"transactionId"`
	ProductID     string `json:"productId"`
	BundleID      string `json:"bundleId"`
	Quantity      int64  `json:"quantity"`
	PurchaseDate  int64  `json:"purchaseDate"`
	Type          string `json:"type"`
	Environment   string `json:"environment"`
}

// decodeJWSPayload 把 "header.payload.signature" 第二段 base64url 解码成 JSON。
func decodeJWSPayload(jws string) (*signedTransactionPayload, error) {
	parts := strings.Split(jws, ".")
	if len(parts) != 3 {
		return nil, fmt.Errorf("not a JWS: %d parts", len(parts))
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, fmt.Errorf("base64 payload: %w", err)
	}
	var p signedTransactionPayload
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, fmt.Errorf("json payload: %w", err)
	}
	return &p, nil
}

// extractTxIDFromJWS 客户端送上来的 JWS（StoreKit 2 verificationData）→ 找 transactionId。
func extractTxIDFromJWS(jws string) (string, error) {
	p, err := decodeJWSPayload(jws)
	if err != nil {
		return "", err
	}
	if p.TransactionID == "" {
		return "", errors.New("jws payload missing transactionId")
	}
	return p.TransactionID, nil
}

// parseECPrivateKeyPEM 从 .p8 文件里取出 ECDSA 私钥。
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
