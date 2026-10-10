package api

import (
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/invite"
	"github.com/sencloud/finme-backend/internal/platform"
)

// mountInvite 邀请好友（需登录）：填码双方各得喜点。
//
// 邀请原本挂在鹦鹉螺下（/v1/nautilus/invite），鹦鹉螺隐藏后独立出来；
// 旧路径仍然可用，指向同一个实现。
func mountInvite(r chi.Router, d *Deps) {
	r.Get("/invite", handleInviteInfo(d))
	r.Post("/invite/redeem", handleInviteRedeem(d))
}

// GET /v1/invite
func handleInviteInfo(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		info, err := d.Invite.GetInfo(r.Context(), uc.UserID)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("INVITE.INFO", err))
			return
		}
		WriteJSON(w, http.StatusOK, info)
	}
}

// POST /v1/invite/redeem {code}  → {info, balance}（balance 为喜点余额）
func handleInviteRedeem(d *Deps) http.HandlerFunc {
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
				WriteError(w, r, platform.ErrNotFound("INVITE.CODE_NOT_FOUND", "邀请码不存在"))
			case errors.Is(err, invite.ErrSelfInvite):
				WriteError(w, r, platform.ErrBadRequest("INVITE.SELF", "不能填写自己的邀请码", nil))
			case errors.Is(err, invite.ErrAlreadyRedeemed):
				WriteError(w, r, platform.ErrConflict("INVITE.REDEEMED", "你已经兑换过邀请码了"))
			case errors.Is(err, invite.ErrNotNewUser):
				WriteError(w, r, platform.ErrConflict("INVITE.NOT_NEW", "邀请码仅限新用户注册 72 小时内填写"))
			default:
				WriteError(w, r, platform.ErrInternal("INVITE.REDEEM", err))
			}
			return
		}
		var balance int64
		if d.Users != nil {
			balance, _ = d.Users.CreditBalance(r.Context(), uc.UserID)
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"info":    info,
			"balance": balance,
		})
	}
}
