package billing

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jmoiron/sqlx"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

var jsonMarshal = json.Marshal

// 订单状态机。
const (
	OrderPending   = "pending"   // 创建后等待支付
	OrderPaid      = "paid"      // 支付通过（receipt 验签 OK）
	OrderCredited  = "credited"  // 已发币（流水写入完成）
	OrderRefunded  = "refunded"  // Apple 退款 / 客服处理
	OrderClosed    = "closed"    // 用户取消 / 超时
	OrderFailed    = "failed"    // 验签失败 / 业务异常
)

// 渠道。
const (
	ChannelAppleIAP = "apple_iap"
	ChannelWechat   = "wechat"
	ChannelAlipay   = "alipay"
)

type Order struct {
	ID              int64          `db:"id" json:"-"`
	OrderNo         string         `db:"order_no" json:"order_no"`
	UserID          int64          `db:"user_id" json:"-"`
	SKUCode         string         `db:"sku_code" json:"sku_code"`
	Credits         int64          `db:"credits" json:"credits"`
	AmountCents     int64          `db:"amount_cents" json:"amount_cents"`
	Channel         string         `db:"channel" json:"channel"`
	ChannelOrderID  sql.NullString `db:"channel_order_id" json:"-"`
	Status          string         `db:"status" json:"status"`
	PaidAt          sql.NullInt64  `db:"paid_at" json:"-"`
	CreditedAt      sql.NullInt64  `db:"credited_at" json:"-"`
	RefundedAt      sql.NullInt64  `db:"refunded_at" json:"-"`
	RawReceiptID    sql.NullInt64  `db:"raw_receipt_id" json:"-"`
	ClientRequestID sql.NullString `db:"client_request_id" json:"-"`
	CreatedAt       int64          `db:"created_at" json:"created_at"`
	UpdatedAt       int64          `db:"updated_at" json:"-"`
}

// MarshalJSON 把 sql.Null* 转成 *int64 / *string，前端拿到的就是 null 或值。
func (o Order) MarshalJSON() ([]byte, error) {
	dto := struct {
		OrderNo         string  `json:"order_no"`
		SKUCode         string  `json:"sku_code"`
		Credits         int64   `json:"credits"`
		AmountCents     int64   `json:"amount_cents"`
		Channel         string  `json:"channel"`
		Status          string  `json:"status"`
		PaidAt          *int64  `json:"paid_at,omitempty"`
		CreditedAt      *int64  `json:"credited_at,omitempty"`
		RefundedAt      *int64  `json:"refunded_at,omitempty"`
		ClientRequestID *string `json:"client_request_id,omitempty"`
		CreatedAt       int64   `json:"created_at"`
	}{
		OrderNo:     o.OrderNo,
		SKUCode:     o.SKUCode,
		Credits:     o.Credits,
		AmountCents: o.AmountCents,
		Channel:     o.Channel,
		Status:      o.Status,
		CreatedAt:   o.CreatedAt,
	}
	if o.PaidAt.Valid {
		v := o.PaidAt.Int64
		dto.PaidAt = &v
	}
	if o.CreditedAt.Valid {
		v := o.CreditedAt.Int64
		dto.CreditedAt = &v
	}
	if o.RefundedAt.Valid {
		v := o.RefundedAt.Int64
		dto.RefundedAt = &v
	}
	if o.ClientRequestID.Valid {
		v := o.ClientRequestID.String
		dto.ClientRequestID = &v
	}
	return jsonMarshal(dto)
}

type OrderRepo struct {
	st *store.Store
}

func NewOrderRepo(st *store.Store) *OrderRepo { return &OrderRepo{st: st} }

// Create 在用户发起购买时创建一个 pending 订单。
// 同 (user_id, client_request_id) 已存在时直接返回旧订单（幂等）。
func (r *OrderRepo) Create(ctx context.Context, in CreateOrderInput) (*Order, error) {
	now := time.Now().UnixMilli()
	if in.ClientRequestID != "" {
		var existing Order
		err := r.st.DB.GetContext(ctx, &existing,
			"SELECT * FROM orders WHERE user_id=? AND client_request_id=?",
			in.UserID, in.ClientRequestID)
		if err == nil {
			return &existing, nil
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, err
		}
	}

	orderNo := platform.NewOrderNo(time.Now())
	var id int64
	err := r.st.Tx(ctx, func(tx *sqlx.Tx) error {
		res, err := tx.ExecContext(ctx, `
			INSERT INTO orders(order_no, user_id, sku_code, credits, amount_cents, channel,
			                   status, client_request_id, created_at, updated_at)
			VALUES(?,?,?,?,?,?,?,?,?,?)`,
			orderNo, in.UserID, in.SKUCode, in.Credits, in.AmountCents,
			in.Channel, OrderPending, nullStr(in.ClientRequestID), now, now,
		)
		if err != nil {
			return err
		}
		id, _ = res.LastInsertId()
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("create order: %w", err)
	}
	return r.FindByID(ctx, id)
}

type CreateOrderInput struct {
	UserID          int64
	SKUCode         string
	Credits         int64
	AmountCents     int64
	Channel         string
	ClientRequestID string
}

func (r *OrderRepo) FindByID(ctx context.Context, id int64) (*Order, error) {
	var o Order
	err := r.st.DB.GetContext(ctx, &o, "SELECT * FROM orders WHERE id=?", id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &o, nil
}

func (r *OrderRepo) FindByOrderNo(ctx context.Context, orderNo string) (*Order, error) {
	var o Order
	err := r.st.DB.GetContext(ctx, &o, "SELECT * FROM orders WHERE order_no=?", orderNo)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &o, nil
}

// FindByChannelOrderID 用于 IAP / 微信回调按渠道 id 找订单（防重复发币）。
func (r *OrderRepo) FindByChannelOrderID(ctx context.Context, channel, channelOrderID string) (*Order, error) {
	var o Order
	err := r.st.DB.GetContext(ctx, &o,
		"SELECT * FROM orders WHERE channel=? AND channel_order_id=?",
		channel, channelOrderID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &o, nil
}

// MarkPaid 把 pending → paid，记录渠道流水号。
// 状态守卫：仅 pending 可以走到 paid；其它状态 → 返回当前订单不报错（幂等）。
func (r *OrderRepo) MarkPaid(ctx context.Context, id int64, channelOrderID string) error {
	now := time.Now().UnixMilli()
	res, err := r.st.DB.ExecContext(ctx, `
		UPDATE orders SET status=?, channel_order_id=?, paid_at=?, updated_at=?
		WHERE id=? AND status=?`,
		OrderPaid, channelOrderID, now, now, id, OrderPending)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		// 重复回调 / 已经更进一步状态。让上层去 Find 看真实状态。
		return nil
	}
	return nil
}

// MarkCredited 把 paid → credited（已发币）。
func (r *OrderRepo) MarkCredited(ctx context.Context, id int64) error {
	now := time.Now().UnixMilli()
	_, err := r.st.DB.ExecContext(ctx, `
		UPDATE orders SET status=?, credited_at=?, updated_at=?
		WHERE id=? AND status=?`,
		OrderCredited, now, now, id, OrderPaid)
	return err
}

// MarkFailed 把 pending → failed（验签失败 / IAP 错配 SKU 等）。
func (r *OrderRepo) MarkFailed(ctx context.Context, id int64) error {
	now := time.Now().UnixMilli()
	_, err := r.st.DB.ExecContext(ctx, `
		UPDATE orders SET status=?, updated_at=?
		WHERE id=? AND status=?`,
		OrderFailed, now, id, OrderPending)
	return err
}

// MarkRefunded 把 credited → refunded（Apple webhook / 客服）。
func (r *OrderRepo) MarkRefunded(ctx context.Context, id int64) error {
	now := time.Now().UnixMilli()
	_, err := r.st.DB.ExecContext(ctx, `
		UPDATE orders SET status=?, refunded_at=?, updated_at=?
		WHERE id=? AND status=?`,
		OrderRefunded, now, now, id, OrderCredited)
	return err
}

// SaveRawReceipt 把渠道发回的 receipt 落库到 receipts 表，便于事后审计。
func (r *OrderRepo) SaveRawReceipt(ctx context.Context, channel, payload string, ok bool) (int64, error) {
	now := time.Now().UnixMilli()
	res, err := r.st.DB.ExecContext(ctx, `
		INSERT INTO receipts(channel, payload, verified_at, verify_ok, created_at)
		VALUES(?, ?, ?, ?, ?)`,
		channel, payload, now, boolToInt(ok), now)
	if err != nil {
		return 0, err
	}
	id, _ := res.LastInsertId()
	return id, nil
}

func (r *OrderRepo) AttachReceiptID(ctx context.Context, orderID, receiptID int64) error {
	_, err := r.st.DB.ExecContext(ctx,
		"UPDATE orders SET raw_receipt_id=? WHERE id=?", receiptID, orderID)
	return err
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
