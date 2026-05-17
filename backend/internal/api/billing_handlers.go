package api

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/platform"
)

// mountBilling 把 /v1/credits/* 挂到受保护路由组（除 SKU 公开外）。
//
// 注意：mountBilling 由 server.go 的两处分别调用：
//   - 公开路由：仅 GET /skus
//   - 受保护路由：其它接口
func mountBillingPublic(r chi.Router, d *Deps) {
	r.Get("/credits/skus", handleListSKUs(d))
}

func mountBillingPrivate(r chi.Router, d *Deps) {
	r.Get("/credits/balance", handleGetBalance(d))
	r.Post("/credits/orders", handleCreateOrder(d))
	r.Post("/credits/iap/verify", handleVerifyIAP(d))
	r.Get("/credits/ledger", handleListLedger(d))
	if d.Config.Env == "dev" {
		r.Post("/credits/dev/topup", handleDevTopup(d))
	}
}

// ── handlers ───────────────────────────────────────────────────────────

func handleListSKUs(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		skus, err := d.Billing.ListSKUs(r.Context())
		if err != nil {
			WriteError(w, r, platform.ErrInternal("BILLING.LIST_SKU", err))
			return
		}
		// 重新映射成给前端的形态（隐藏 active 字段，转成元单位）
		out := make([]map[string]any, 0, len(skus))
		for _, s := range skus {
			out = append(out, map[string]any{
				"code":             s.Code,
				"apple_product_id": s.AppleProductID,
				"base_credits":     s.BaseCredits,
				"bonus_credits":    s.BonusCredits,
				"total_credits":    s.TotalCredits(),
				"price_cents_cny":  s.PriceCentsCNY,
				"price_yuan":       s.PriceYuan(),
				"sort":             s.Sort,
			})
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": out})
	}
}

func handleGetBalance(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		bal, err := d.Billing.GetBalance(r.Context(), uc.UserID)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("BILLING.BALANCE", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"balance": bal})
	}
}

type createOrderReq struct {
	SKUCode         string `json:"sku_code"`
	Channel         string `json:"channel"`
	ClientRequestID string `json:"client_request_id"`
}

func handleCreateOrder(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		var in createOrderReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		if strings.TrimSpace(in.SKUCode) == "" {
			WriteError(w, r, platform.ErrBadRequest("BILLING.SKU_REQUIRED", "sku_code required", nil))
			return
		}
		if in.Channel == "" {
			in.Channel = billing.ChannelAppleIAP
		}
		order, err := d.Billing.CreateOrder(r.Context(), billing.CreateOrderInput2{
			UserID:          uc.UserID,
			SKUCode:         in.SKUCode,
			Channel:         in.Channel,
			ClientRequestID: in.ClientRequestID,
		})
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, order)
	}
}

type verifyIAPReq struct {
	OrderNo     string `json:"order_no"`
	JWSReceipt  string `json:"jws_receipt"`
}

func handleVerifyIAP(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		var in verifyIAPReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		if in.OrderNo == "" || in.JWSReceipt == "" {
			WriteError(w, r, platform.ErrBadRequest("BILLING.MISSING_FIELDS",
				"order_no and jws_receipt required", nil))
			return
		}
		order, balance, err := d.Billing.VerifyIAP(r.Context(), uc.UserID, in.OrderNo, in.JWSReceipt)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"order":   order,
			"balance": balance,
		})
	}
}

type devTopupReq struct {
	Credits int64  `json:"credits"`
	Remark  string `json:"remark"`
}

func handleDevTopup(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		var in devTopupReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		bal, err := d.Billing.DevTopup(r.Context(), uc.UserID, in.Credits, in.Remark)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"balance": bal})
	}
}

func handleListLedger(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		cursorStr := r.URL.Query().Get("cursor")
		limitStr := r.URL.Query().Get("limit")
		var cursor int64
		var limit int
		if cursorStr != "" {
			cursor, _ = strconv.ParseInt(cursorStr, 10, 64)
		}
		if limitStr != "" {
			n, _ := strconv.Atoi(limitStr)
			limit = n
		}
		items, next, err := d.Billing.ListLedger(r.Context(), uc.UserID, cursor, limit)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"items":       items,
			"next_cursor": next,
		})
	}
}
