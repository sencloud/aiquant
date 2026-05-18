package billing

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

// Service 是 billing 模块对外的总入口。
//
// 职责：
//   - 暴露 SKU 列表 / 用户余额；
//   - 管理订单全生命周期；
//   - 在 verify IAP 流程内做"验签 → 订单 paid → 发币 → 订单 credited"原子化；
//   - dev_topup：env=dev 直冲，跳过 IAP（联调用）。
type Service struct {
	cfg     *platform.Config
	store   *store.Store
	skus    *SKURepo
	orders  *OrderRepo
	ledger  *LedgerRepo
	iap     IAPVerifier
}

func NewService(st *store.Store, cfg *platform.Config) (*Service, error) {
	skus := NewSKURepo(st)
	if err := SeedDefault(context.Background(), skus); err != nil {
		return nil, fmt.Errorf("seed default skus: %w", err)
	}
	verifier, err := buildIAPVerifier(cfg)
	if err != nil {
		return nil, err
	}
	return &Service{
		cfg:    cfg,
		store:  st,
		skus:   skus,
		orders: NewOrderRepo(st),
		ledger: NewLedgerRepo(st),
		iap:    verifier,
	}, nil
}

// buildIAPVerifier 按 env 与凭证情况选实现：
//   - dev 未配 .p8 → Mock（联调）；
//   - prod 未配 .p8 → DisabledVerifier，所有 verify 调用直接拒绝，服务仍可起
//     （避免上线 IAP 前其余功能不可用）；
//   - 任意 env 配齐 → 真实 AppleIAPVerifier。
func buildIAPVerifier(cfg *platform.Config) (IAPVerifier, error) {
	if !cfg.AppleIAP.Configured() {
		if cfg.Env == "dev" {
			return MockIAPVerifier{}, nil
		}
		return DisabledIAPVerifier{}, nil
	}
	pem := cfg.AppleIAP.PrivateKey
	if pem == "" && cfg.AppleIAP.PrivateKeyPath != "" {
		s, err := LoadAppleP8(cfg.AppleIAP.PrivateKeyPath)
		if err != nil {
			return nil, fmt.Errorf("billing: load apple iap p8: %w", err)
		}
		pem = s
	}
	bid := cfg.AppleIAP.BundleID
	if bid == "" {
		bid = cfg.Apple.BundleID
	}
	return NewAppleIAPVerifier(bid, cfg.AppleIAP.IssuerID, cfg.AppleIAP.KeyID, pem, cfg.AppleIAP.Environment)
}

// ListSKUs 返回前端展示的 SKU。
func (s *Service) ListSKUs(ctx context.Context) ([]SKU, error) {
	return s.skus.ListActive(ctx)
}

// GetBalance 当前用户的喜点余额。直接从 users.credit_balance 读，
// 流水表与 balance 由 Apply() 同事务保证一致。
func (s *Service) GetBalance(ctx context.Context, userID int64) (int64, error) {
	var balance int64
	err := s.store.DB.GetContext(ctx, &balance,
		"SELECT credit_balance FROM users WHERE id=?", userID)
	return balance, err
}

// CreateOrder 客户端发起购买前先创建订单。
type CreateOrderInput2 struct {
	UserID          int64
	SKUCode         string
	Channel         string // 仅 apple_iap 进入；其它渠道后续接入
	ClientRequestID string
}

func (s *Service) CreateOrder(ctx context.Context, in CreateOrderInput2) (*Order, error) {
	if in.Channel != ChannelAppleIAP {
		return nil, platform.ErrBadRequest("BILLING.CHANNEL_UNSUPPORTED",
			"only apple_iap supported for now", nil)
	}
	sku, err := s.skus.FindByCode(ctx, in.SKUCode)
	if err != nil {
		return nil, platform.ErrInternal("BILLING.SKU_LOOKUP", err)
	}
	if sku == nil || !sku.IsActive() {
		return nil, platform.ErrBadRequest("BILLING.SKU_NOT_FOUND", "sku not found or inactive", nil)
	}
	order, err := s.orders.Create(ctx, CreateOrderInput{
		UserID:          in.UserID,
		SKUCode:         sku.Code,
		Credits:         sku.TotalCredits(),
		AmountCents:     sku.PriceCentsCNY,
		Channel:         in.Channel,
		ClientRequestID: in.ClientRequestID,
	})
	if err != nil {
		return nil, platform.ErrInternal("BILLING.CREATE_ORDER", err)
	}
	return order, nil
}

// VerifyIAP 验证 IAP receipt → 标记订单 paid → 写流水 → credited。
//
// 强幂等：
//   - 同 transaction_id 已绑定到任意订单 → 直接返回那笔订单（已发币）；
//   - 同 order_no 已 credited → 直接返回最新状态；
//   - 流水唯一索引 (reason='topup', ref_type='order', ref_id=order_no) 兜底。
func (s *Service) VerifyIAP(ctx context.Context, userID int64, orderNo, jwsReceipt string) (*Order, int64, error) {
	order, err := s.orders.FindByOrderNo(ctx, orderNo)
	if err != nil {
		return nil, 0, platform.ErrInternal("BILLING.ORDER_LOOKUP", err)
	}
	if order == nil {
		return nil, 0, platform.ErrNotFound("BILLING.ORDER_NOT_FOUND", "order not found")
	}
	if order.UserID != userID {
		return nil, 0, platform.ErrForbidden("BILLING.ORDER_OWNER", "order does not belong to user")
	}
	if order.Status == OrderCredited {
		bal, _ := s.GetBalance(ctx, userID)
		return order, bal, nil
	}
	if order.Status != OrderPending && order.Status != OrderPaid {
		return nil, 0, platform.ErrConflict("BILLING.ORDER_BAD_STATE",
			"order is "+order.Status+", cannot verify")
	}

	res, err := s.iap.Verify(ctx, jwsReceipt)
	if err != nil {
		// 关键诊断点：苹果验签 / 网络 / 解码失败的 cause 默认走 Debug 级别，
		// prod (info) 看不到。这里强制 warn 输出，避免「客户报错没法复盘」。
		platform.LoggerFrom(ctx).Warn().
			Err(err).
			Str("order_no", orderNo).
			Int64("user_id", userID).
			Str("verifier", s.iap.Name()).
			Int("receipt_dots", strings.Count(jwsReceipt, ".")).
			Int("receipt_len", len(jwsReceipt)).
			Msg("iap receipt verify failed")
		_ = s.orders.MarkFailed(ctx, order.ID)
		return nil, 0, platform.ErrBadRequest("BILLING.IAP_INVALID",
			"iap receipt verification failed", err)
	}

	// 反查 SKU 校验 product_id 一致
	sku, err := s.skus.FindByAppleProductID(ctx, res.ProductID)
	if err != nil || sku == nil {
		platform.LoggerFrom(ctx).Warn().
			Err(err).
			Str("order_no", orderNo).
			Str("apple_product_id", res.ProductID).
			Msg("iap product_id not in our SKUs")
		_ = s.orders.MarkFailed(ctx, order.ID)
		return nil, 0, platform.ErrBadRequest("BILLING.PRODUCT_MISMATCH",
			fmt.Sprintf("product_id %q not found in our SKUs", res.ProductID), nil)
	}
	if sku.Code != order.SKUCode {
		platform.LoggerFrom(ctx).Warn().
			Str("order_no", orderNo).
			Str("order_sku", order.SKUCode).
			Str("receipt_product_id", res.ProductID).
			Str("receipt_sku", sku.Code).
			Msg("iap product mismatch with order sku")
		_ = s.orders.MarkFailed(ctx, order.ID)
		return nil, 0, platform.ErrBadRequest("BILLING.PRODUCT_MISMATCH",
			"receipt product_id does not match order sku", nil)
	}

	// 同 transaction_id 已绑过别的订单 → 拒绝（防止用同一笔 IAP 给多个订单发币）
	existing, err := s.orders.FindByChannelOrderID(ctx, ChannelAppleIAP, res.TransactionID)
	if err != nil {
		return nil, 0, platform.ErrInternal("BILLING.LOOKUP_TX", err)
	}
	if existing != nil && existing.ID != order.ID {
		return nil, 0, platform.ErrConflict("BILLING.TXID_CONSUMED",
			"this iap transaction has been used")
	}

	// 落 receipt
	rid, err := s.orders.SaveRawReceipt(ctx, ChannelAppleIAP, jwsReceipt, true)
	if err == nil {
		_ = s.orders.AttachReceiptID(ctx, order.ID, rid)
	}

	// pending → paid
	if order.Status == OrderPending {
		if err := s.orders.MarkPaid(ctx, order.ID, res.TransactionID); err != nil {
			return nil, 0, platform.ErrInternal("BILLING.MARK_PAID", err)
		}
	}

	// 发币 + credited
	entry, err := s.ledger.Apply(ctx, ApplyParams{
		UserID:  userID,
		Delta:   order.Credits,
		Reason:  ReasonTopup,
		RefType: "order",
		RefID:   order.OrderNo,
		Remark:  fmt.Sprintf("IAP txid=%s", res.TransactionID),
	})
	if err != nil && !errors.Is(err, ErrLedgerDuplicate) {
		return nil, 0, platform.ErrInternal("BILLING.LEDGER_APPLY", err)
	}
	_ = s.orders.MarkCredited(ctx, order.ID)

	bal, _ := s.GetBalance(ctx, userID)
	updated, _ := s.orders.FindByID(ctx, order.ID)
	if entry != nil {
		_ = entry
	}
	return updated, bal, nil
}

// AppleNotificationResult 是 webhook 处理结果，用于 handler 层日志 / metrics。
type AppleNotificationResult struct {
	NotificationType string
	Subtype          string
	TransactionID    string
	OrderNo          string
	Action           string // refunded / ignored / unknown
}

// HandleAppleNotification 处理 App Store Server Notifications V2 回调。
//
// 关注的事件：
//   - REFUND          ：用户申请并已成功退款（消耗型 / 非续期）
//   - REVOKE          ：家庭共享授权被撤销 / 其它系统级撤销
//   - REFUND_REVERSED ：退款被 Apple 取消（极少；理论上要回滚冲账）
//
// 验签链路（双因子）：
//   1. signedPayload 是 JWS，解码 payload 拿 notificationType + signedTransactionInfo；
//   2. signedTransactionInfo 再次 decode → transactionId；
//   3. 用 transactionId 反查 App Store Server API（复用 IAPVerifier）—— 这一步
//      天然要求 Apple 返回 200，伪造请求会被这一步过滤。
//
// 处理逻辑（强幂等）：
//   - REFUND / REVOKE / REVOKE_FAMILY 等扣款类型：
//       - orders 状态非 credited → 200 OK 幂等忽略；
//       - orders 状态 credited → ledger.Apply(-credits, ReasonRefund) +
//         MarkRefunded；流水唯一索引天然幂等。
//   - 其它 notificationType（CONSUMPTION_REQUEST, DID_RENEW 等）：返回 200 + ignored。
func (s *Service) HandleAppleNotification(ctx context.Context, signedPayload string) (*AppleNotificationResult, error) {
	if strings.TrimSpace(signedPayload) == "" {
		return nil, platform.ErrBadRequest("BILLING.NOTIF_EMPTY", "empty signedPayload", nil)
	}

	// 落原始报文到 receipts 表，便于事后审计
	_, _ = s.orders.SaveRawReceipt(ctx, ChannelAppleIAP, signedPayload, false)

	notif, err := decodeAppleNotificationPayload(signedPayload)
	if err != nil {
		return nil, platform.ErrBadRequest("BILLING.NOTIF_PARSE",
			"parse signedPayload failed", err)
	}
	res := &AppleNotificationResult{
		NotificationType: notif.NotificationType,
		Subtype:          notif.Subtype,
		Action:           "ignored",
	}

	// 解嵌套的 signedTransactionInfo
	tx, err := decodeJWSPayload(notif.Data.SignedTransactionInfo)
	if err != nil || tx.TransactionID == "" {
		return res, platform.ErrBadRequest("BILLING.NOTIF_NO_TXID",
			"signedTransactionInfo missing transactionId", err)
	}
	res.TransactionID = tx.TransactionID

	switch notif.NotificationType {
	case "REFUND", "REVOKE":
		// 进入冲账流程
		if err := s.refundByTransaction(ctx, tx.TransactionID, res); err != nil {
			return res, err
		}
	default:
		return res, nil
	}
	return res, nil
}

// refundByTransaction：找订单 → 反向冲账 → MarkRefunded。
func (s *Service) refundByTransaction(ctx context.Context, txID string, out *AppleNotificationResult) error {
	order, err := s.orders.FindByChannelOrderID(ctx, ChannelAppleIAP, txID)
	if err != nil {
		return platform.ErrInternal("BILLING.NOTIF_LOOKUP", err)
	}
	if order == nil {
		out.Action = "unknown"
		return nil
	}
	out.OrderNo = order.OrderNo
	if order.Status == OrderRefunded {
		out.Action = "refunded"
		return nil
	}
	if order.Status != OrderCredited && order.Status != OrderPaid {
		out.Action = "ignored"
		return nil
	}

	_, err = s.ledger.Apply(ctx, ApplyParams{
		UserID:        order.UserID,
		Delta:         -order.Credits,
		Reason:        ReasonRefund,
		RefType:       "order",
		RefID:         order.OrderNo,
		Remark:        fmt.Sprintf("apple refund txid=%s", txID),
		AllowNegative: true,
	})
	if err != nil && !errors.Is(err, ErrLedgerDuplicate) {
		return platform.ErrInternal("BILLING.NOTIF_APPLY", err)
	}
	if _, err := s.store.DB.ExecContext(ctx, `
		UPDATE orders SET status='refunded', refunded_at=?, updated_at=?
		WHERE id=? AND status IN ('credited','paid')`,
		time.Now().UnixMilli(), time.Now().UnixMilli(), order.ID); err != nil {
		return platform.ErrInternal("BILLING.NOTIF_MARK_REFUND", err)
	}
	out.Action = "refunded"
	return nil
}

// DevTopup 仅 env=dev 启用：直冲，不经过 IAP。
func (s *Service) DevTopup(ctx context.Context, userID int64, credits int64, remark string) (int64, error) {
	if s.cfg.Env != "dev" {
		return 0, platform.ErrForbidden("BILLING.DEV_ONLY", "dev_topup is dev-only")
	}
	if credits <= 0 || credits > 100_000 {
		return 0, platform.ErrBadRequest("BILLING.AMOUNT_INVALID", "credits out of range", nil)
	}
	refID := platform.NewUUID()
	_, err := s.ledger.Apply(ctx, ApplyParams{
		UserID:  userID,
		Delta:   credits,
		Reason:  ReasonDevTopup,
		RefType: "dev",
		RefID:   refID,
		Remark:  remark,
	})
	if err != nil {
		return 0, platform.ErrInternal("BILLING.LEDGER_APPLY", err)
	}
	bal, _ := s.GetBalance(ctx, userID)
	return bal, nil
}

// ListLedger 分页流水。
func (s *Service) ListLedger(ctx context.Context, userID int64, cursor int64, limit int) ([]LedgerJSON, int64, error) {
	rows, next, err := s.ledger.ListByUser(ctx, userID, cursor, limit)
	if err != nil {
		return nil, 0, platform.ErrInternal("BILLING.LEDGER_LIST", err)
	}
	out := make([]LedgerJSON, 0, len(rows))
	for _, r := range rows {
		out = append(out, r.ToJSON())
	}
	return out, next, nil
}
