package api

import (
	"crypto/subtle"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/invite"
	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/predict"
	"github.com/sencloud/finme-backend/internal/shell"
)

// mountNautilusPublic 挂载无需登录的市场浏览接口。
//
// 鹦鹉螺 tab 对未登录用户开放浏览（App-first 策略），
// 下注 / 钱包 / 邀请等带用户态的操作在 mountNautilus(JWT 组)。
// 注意：公开组和 JWT 组都在 /nautilus 下注册端点，必须平铺 r.Get/r.Post
// （不能两边都 r.Route("/nautilus")，chi 不允许同一路径挂两个子路由）。
func mountNautilusPublic(r chi.Router, d *Deps) {
	r.Get("/nautilus/markets", handleNautilusListMarkets(d))
	r.Get("/nautilus/markets/{id}", handleNautilusGetMarket(d))
}

// mountNautilus 挂载需要登录的下注 / 钱包 / 邀请接口。
func mountNautilus(r chi.Router, d *Deps) {
	r.Post("/nautilus/markets/{id}/bet", handleNautilusBet(d))
	r.Get("/nautilus/markets/{id}/my-bets", handleNautilusMyMarketBets(d))
	r.Get("/nautilus/shells", handleNautilusShells(d))
	r.Get("/nautilus/bets", handleNautilusMyBets(d))
	r.Get("/nautilus/invite", handleNautilusInviteInfo(d))
	r.Post("/nautilus/invite/redeem", handleNautilusInviteRedeem(d))
}

// mountNautilusAdmin 管理端：建市场 / 录结果 / 取消。
//
// 用 X-Admin-Key 头校验（config nautilus.admin_key），不走 JWT —— 运营直接
// curl 即可操作；key 未配置时全部 503。
func mountNautilusAdmin(r chi.Router, d *Deps) {
	r.Route("/admin/nautilus", func(r chi.Router) {
		r.Use(adminKeyMiddleware(d))
		r.Post("/markets", handleNautilusAdminCreate(d))
		r.Post("/markets/{id}/settle", handleNautilusAdminSettle(d))
		r.Post("/markets/{id}/cancel", handleNautilusAdminCancel(d))
	})
}

func adminKeyMiddleware(d *Deps) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := d.Config.Nautilus.AdminKey
			if key == "" {
				WriteError(w, r, platform.ErrUnavailable("NAUTILUS.ADMIN_DISABLED",
					errors.New("nautilus admin_key not configured")))
				return
			}
			got := r.Header.Get("X-Admin-Key")
			if subtle.ConstantTimeCompare([]byte(got), []byte(key)) != 1 {
				WriteError(w, r, platform.ErrUnauthorized("NAUTILUS.ADMIN_KEY_INVALID",
					"invalid admin key"))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// ---------- 公开浏览 ----------

// GET /v1/nautilus/markets?category=weather|finance&limit=50
func handleNautilusListMarkets(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		category := strings.TrimSpace(r.URL.Query().Get("category"))
		if category != "" && category != predict.CategoryWeather && category != predict.CategoryFinance {
			WriteError(w, r, platform.ErrBadRequest("NAUTILUS.CATEGORY_INVALID",
				"category must be weather|finance", nil))
			return
		}
		limit := atoiOr(r.URL.Query().Get("limit"), 50)
		items, err := d.Predict.ListMarkets(r.Context(), category, limit)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("NAUTILUS.LIST_MARKETS", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"items":   items,
			"min_bet": d.Predict.MinBet(),
		})
	}
}

// GET /v1/nautilus/markets/{id}
func handleNautilusGetMarket(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
		if err != nil {
			WriteError(w, r, platform.ErrBadRequest("NAUTILUS.ID_INVALID", "invalid market id", err))
			return
		}
		view, err := d.Predict.GetMarket(r.Context(), id)
		if errors.Is(err, predict.ErrMarketNotFound) {
			WriteError(w, r, platform.ErrNotFound("NAUTILUS.MARKET_NOT_FOUND", "market not found"))
			return
		}
		if err != nil {
			WriteError(w, r, platform.ErrInternal("NAUTILUS.GET_MARKET", err))
			return
		}
		WriteJSON(w, http.StatusOK, view)
	}
}

// ---------- 登录态 ----------

// POST /v1/nautilus/markets/{id}/bet  {option_id, amount}
func handleNautilusBet(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		marketID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
		if err != nil {
			WriteError(w, r, platform.ErrBadRequest("NAUTILUS.ID_INVALID", "invalid market id", err))
			return
		}
		var body struct {
			OptionID int64 `json:"option_id"`
			Amount   int64 `json:"amount"`
		}
		if err := DecodeJSON(r, &body); err != nil {
			WriteError(w, r, err)
			return
		}
		bet, err := d.Predict.PlaceBet(r.Context(), uc.UserID, marketID, body.OptionID, body.Amount)
		if err != nil {
			switch {
			case errors.Is(err, predict.ErrMarketNotFound):
				WriteError(w, r, platform.ErrNotFound("NAUTILUS.MARKET_NOT_FOUND", "market not found"))
			case errors.Is(err, predict.ErrMarketNotOpen):
				WriteError(w, r, platform.ErrConflict("NAUTILUS.MARKET_CLOSED", "该市场已停止下注"))
			case errors.Is(err, predict.ErrOptionInvalid):
				WriteError(w, r, platform.ErrBadRequest("NAUTILUS.OPTION_INVALID", "选项不存在", nil))
			case errors.Is(err, predict.ErrBetTooSmall):
				WriteError(w, r, platform.ErrBadRequest("NAUTILUS.BET_TOO_SMALL",
					"单笔下注不能低于 "+strconv.FormatInt(d.Predict.MinBet(), 10)+" 螺壳", nil))
			case errors.Is(err, shell.ErrInsufficient):
				WriteError(w, r, platform.ErrPaymentRequired("NAUTILUS.INSUFFICIENT_SHELLS",
					"螺壳不足，邀请好友可获得更多螺壳"))
			default:
				WriteError(w, r, platform.ErrInternal("NAUTILUS.PLACE_BET", err))
			}
			return
		}
		// 返回最新市场快照，前端直接刷新赔率。
		view, _ := d.Predict.GetMarket(r.Context(), marketID)
		balance, _ := d.Shell.Balance(r.Context(), uc.UserID)
		WriteJSON(w, http.StatusCreated, map[string]any{
			"bet":     bet,
			"market":  view,
			"balance": balance,
		})
	}
}

// GET /v1/nautilus/markets/{id}/my-bets
func handleNautilusMyMarketBets(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		marketID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
		if err != nil {
			WriteError(w, r, platform.ErrBadRequest("NAUTILUS.ID_INVALID", "invalid market id", err))
			return
		}
		bets, err := d.Predict.UserBets(r.Context(), uc.UserID, marketID)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("NAUTILUS.MY_BETS", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": bets})
	}
}

// GET /v1/nautilus/shells?cursor=0&limit=30 —— 余额 + 流水。
func handleNautilusShells(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		balance, err := d.Shell.Balance(r.Context(), uc.UserID)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("NAUTILUS.BALANCE", err))
			return
		}
		cursor, _ := strconv.ParseInt(r.URL.Query().Get("cursor"), 10, 64)
		limit := atoiOr(r.URL.Query().Get("limit"), 30)
		entries, next, err := d.Shell.ListByUser(r.Context(), uc.UserID, cursor, limit)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("NAUTILUS.LEDGER", err))
			return
		}
		out := make([]shell.EntryJSON, 0, len(entries))
		for _, e := range entries {
			out = append(out, e.ToJSON())
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"balance":     balance,
			"items":       out,
			"next_cursor": next,
		})
	}
}

// GET /v1/nautilus/bets —— 我的全部下注（带市场信息）。
func handleNautilusMyBets(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		limit := atoiOr(r.URL.Query().Get("limit"), 50)
		items, err := d.Predict.ListUserBets(r.Context(), uc.UserID, limit)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("NAUTILUS.LIST_BETS", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": items})
	}
}

// GET /v1/nautilus/invite
func handleNautilusInviteInfo(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		info, err := d.Invite.GetInfo(r.Context(), uc.UserID)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("NAUTILUS.INVITE_INFO", err))
			return
		}
		WriteJSON(w, http.StatusOK, info)
	}
}

// POST /v1/nautilus/invite/redeem {code}
func handleNautilusInviteRedeem(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		var body struct {
			Code string `json:"code"`
		}
		if err := DecodeJSON(r, &body); err != nil {
			WriteError(w, r, err)
			return
		}
		info, err := d.Invite.Redeem(r.Context(), uc.UserID, body.Code)
		if err != nil {
			switch {
			case errors.Is(err, invite.ErrCodeNotFound):
				WriteError(w, r, platform.ErrNotFound("NAUTILUS.INVITE_CODE_NOT_FOUND", "邀请码不存在"))
			case errors.Is(err, invite.ErrSelfInvite):
				WriteError(w, r, platform.ErrBadRequest("NAUTILUS.INVITE_SELF", "不能填写自己的邀请码", nil))
			case errors.Is(err, invite.ErrAlreadyRedeemed):
				WriteError(w, r, platform.ErrConflict("NAUTILUS.INVITE_REDEEMED", "你已经兑换过邀请码了"))
			case errors.Is(err, invite.ErrNotNewUser):
				WriteError(w, r, platform.ErrConflict("NAUTILUS.INVITE_NOT_NEW", "邀请码仅限新用户注册 72 小时内填写"))
			default:
				WriteError(w, r, platform.ErrInternal("NAUTILUS.INVITE_REDEEM", err))
			}
			return
		}
		balance, _ := d.Shell.Balance(r.Context(), uc.UserID)
		WriteJSON(w, http.StatusOK, map[string]any{
			"info":    info,
			"balance": balance,
		})
	}
}

// ---------- 管理端 ----------

// POST /v1/admin/nautilus/markets
func handleNautilusAdminCreate(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var in predict.CreateMarketInput
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		view, err := d.Predict.CreateMarket(r.Context(), in)
		if err != nil {
			WriteError(w, r, platform.ErrBadRequest("NAUTILUS.CREATE_MARKET", err.Error(), err))
			return
		}
		WriteJSON(w, http.StatusCreated, view)
	}
}

// POST /v1/admin/nautilus/markets/{id}/settle {option_id}
func handleNautilusAdminSettle(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		marketID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
		if err != nil {
			WriteError(w, r, platform.ErrBadRequest("NAUTILUS.ID_INVALID", "invalid market id", err))
			return
		}
		var body struct {
			OptionID int64 `json:"option_id"`
		}
		if err := DecodeJSON(r, &body); err != nil {
			WriteError(w, r, err)
			return
		}
		if err := d.Predict.Settle(r.Context(), marketID, body.OptionID); err != nil {
			switch {
			case errors.Is(err, predict.ErrMarketNotFound):
				WriteError(w, r, platform.ErrNotFound("NAUTILUS.MARKET_NOT_FOUND", "market not found"))
			case errors.Is(err, predict.ErrOptionInvalid):
				WriteError(w, r, platform.ErrBadRequest("NAUTILUS.OPTION_INVALID", "option invalid", nil))
			case errors.Is(err, predict.ErrAlreadyFinal):
				WriteError(w, r, platform.ErrConflict("NAUTILUS.ALREADY_FINAL", "market already settled/cancelled"))
			default:
				WriteError(w, r, platform.ErrInternal("NAUTILUS.SETTLE", err))
			}
			return
		}
		view, _ := d.Predict.GetMarket(r.Context(), marketID)
		WriteJSON(w, http.StatusOK, view)
	}
}

// POST /v1/admin/nautilus/markets/{id}/cancel
func handleNautilusAdminCancel(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		marketID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
		if err != nil {
			WriteError(w, r, platform.ErrBadRequest("NAUTILUS.ID_INVALID", "invalid market id", err))
			return
		}
		if err := d.Predict.Cancel(r.Context(), marketID); err != nil {
			switch {
			case errors.Is(err, predict.ErrMarketNotFound):
				WriteError(w, r, platform.ErrNotFound("NAUTILUS.MARKET_NOT_FOUND", "market not found"))
			case errors.Is(err, predict.ErrAlreadyFinal):
				WriteError(w, r, platform.ErrConflict("NAUTILUS.ALREADY_FINAL", "market already settled/cancelled"))
			default:
				WriteError(w, r, platform.ErrInternal("NAUTILUS.CANCEL", err))
			}
			return
		}
		view, _ := d.Predict.GetMarket(r.Context(), marketID)
		WriteJSON(w, http.StatusOK, view)
	}
}
