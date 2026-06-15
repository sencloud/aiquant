package api

import (
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/auth"
	"github.com/sencloud/finme-backend/internal/devices"
	"github.com/sencloud/finme-backend/internal/platform"
)

func mountAuth(r chi.Router, d *Deps) {
	r.Route("/auth", func(r chi.Router) {
		r.Post("/sms/send", handleSMSSend(d))
		r.Post("/sms/verify", handleSMSVerify(d))
		r.Post("/email/send", handleEmailSend(d))
		r.Post("/email/verify", handleEmailVerify(d))
		r.Post("/apple", handleAppleLogin(d))
		r.Post("/refresh", handleRefresh(d))
		// 登出仍然需要 access token 才能锁定身份
		r.With(JWTMiddleware(d.Auth)).Post("/logout", handleLogout(d))
	})
}

func mountMe(r chi.Router, d *Deps) {
	r.Get("/me", handleMe(d))
	r.Patch("/me", handleUpdateMe(d))
	r.Delete("/me", handleDeleteMe(d))
}

func mountDevices(r chi.Router, d *Deps) {
	r.Post("/devices", handleUpsertDevice(d))
}

// ── handlers ──────────────────────────────────────────────────────────

type smsSendReq struct {
	Phone string `json:"phone"`
}

func handleSMSSend(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var in smsSendReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		if err := d.Auth.SendSMS(r.Context(), auth.SendSMSInput{
			Phone: strings.TrimSpace(in.Phone),
			IP:    r.RemoteAddr,
		}); err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

type smsVerifyReq struct {
	Phone    string `json:"phone"`
	Code     string `json:"code"`
	DeviceID string `json:"device_id,omitempty"`
}

func handleSMSVerify(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var in smsVerifyReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		pair, user, err := d.Auth.VerifySMS(r.Context(), auth.VerifySMSInput{
			Phone:    strings.TrimSpace(in.Phone),
			Code:     strings.TrimSpace(in.Code),
			DeviceID: in.DeviceID,
			IP:       r.RemoteAddr,
			UA:       r.UserAgent(),
		})
		if err != nil {
			WriteError(w, r, err)
			return
		}
		if d.Onboarding != nil {
			if oerr := d.Onboarding.OnboardIfNeeded(r.Context(), user); oerr != nil {
				platform.LoggerFrom(r.Context()).Warn().Err(oerr).Msg("onboarding failed (non-fatal)")
			}
			user, _ = d.Users.FindByID(r.Context(), user.ID)
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"tokens": pair,
			"user":   user.ToPublic(),
		})
	}
}

type emailSendReq struct {
	Email string `json:"email"`
}

func handleEmailSend(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var in emailSendReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		if err := d.Auth.SendEmailCode(r.Context(), auth.SendEmailCodeInput{
			Email: strings.TrimSpace(in.Email),
			IP:    r.RemoteAddr,
		}); err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

type emailVerifyReq struct {
	Email    string `json:"email"`
	Code     string `json:"code"`
	DeviceID string `json:"device_id,omitempty"`
}

func handleEmailVerify(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var in emailVerifyReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		pair, user, err := d.Auth.VerifyEmail(r.Context(), auth.VerifyEmailInput{
			Email:    strings.TrimSpace(in.Email),
			Code:     strings.TrimSpace(in.Code),
			DeviceID: in.DeviceID,
			IP:       r.RemoteAddr,
			UA:       r.UserAgent(),
		})
		if err != nil {
			WriteError(w, r, err)
			return
		}
		if d.Onboarding != nil {
			if oerr := d.Onboarding.OnboardIfNeeded(r.Context(), user); oerr != nil {
				platform.LoggerFrom(r.Context()).Warn().Err(oerr).Msg("onboarding failed (non-fatal)")
			}
			user, _ = d.Users.FindByID(r.Context(), user.ID)
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"tokens": pair,
			"user":   user.ToPublic(),
		})
	}
}

type appleLoginReq struct {
	IdentityToken string `json:"identity_token"`
	Nickname      string `json:"nickname,omitempty"`
	DeviceID      string `json:"device_id,omitempty"`
}

func handleAppleLogin(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var in appleLoginReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		if in.IdentityToken == "" {
			WriteError(w, r, platform.ErrBadRequest("AUTH.MISSING_TOKEN", "identity_token required", nil))
			return
		}
		pair, user, err := d.Auth.AppleLogin(r.Context(), auth.AppleLoginInput{
			IdentityToken: in.IdentityToken,
			Nickname:      strings.TrimSpace(in.Nickname),
			DeviceID:      in.DeviceID,
			IP:            r.RemoteAddr,
			UA:            r.UserAgent(),
		})
		if err != nil {
			WriteError(w, r, err)
			return
		}
		if d.Onboarding != nil {
			if oerr := d.Onboarding.OnboardIfNeeded(r.Context(), user); oerr != nil {
				platform.LoggerFrom(r.Context()).Warn().Err(oerr).Msg("onboarding failed (non-fatal)")
			}
			user, _ = d.Users.FindByID(r.Context(), user.ID)
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"tokens": pair,
			"user":   user.ToPublic(),
		})
	}
}

type refreshReq struct {
	RefreshToken string `json:"refresh_token"`
}

func handleRefresh(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var in refreshReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		if in.RefreshToken == "" {
			WriteError(w, r, platform.ErrBadRequest("AUTH.MISSING_REFRESH", "refresh_token required", nil))
			return
		}
		pair, user, err := d.Auth.Refresh(r.Context(), in.RefreshToken, r.RemoteAddr, r.UserAgent())
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"tokens": pair,
			"user":   user.ToPublic(),
		})
	}
}

func handleLogout(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		if err := d.Auth.Logout(r.Context(), uc.UserID); err != nil {
			WriteError(w, r, platform.ErrInternal("AUTH.LOGOUT_FAILED", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

// /me ────────────────────────────────────────────────────────────────

func handleMe(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		user, err := d.Users.FindByID(r.Context(), uc.UserID)
		if err != nil || user == nil {
			WriteError(w, r, platform.ErrUnauthorized("AUTH.USER_NOT_FOUND", "user not found"))
			return
		}
		WriteJSON(w, http.StatusOK, user.ToPublic())
	}
}

type updateMeReq struct {
	Nickname *string `json:"nickname,omitempty"`
}

func handleUpdateMe(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		var in updateMeReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		if in.Nickname != nil {
			nick := strings.TrimSpace(*in.Nickname)
			if len([]rune(nick)) > 32 {
				WriteError(w, r, platform.ErrBadRequest("USER.NICK_TOO_LONG", "nickname max 32 chars", nil))
				return
			}
			if err := d.Users.UpdateNickname(r.Context(), uc.UserID, nick); err != nil {
				WriteError(w, r, platform.ErrInternal("USER.UPDATE_FAILED", err))
				return
			}
		}
		user, _ := d.Users.FindByID(r.Context(), uc.UserID)
		WriteJSON(w, http.StatusOK, user.ToPublic())
	}
}

// 账户注销：抹除可识别身份字段、删设备 / DING / refresh_token，订单与
// 喜点流水保留（监管追溯）。客户端拿到 200 即可清本地登录态。
func handleDeleteMe(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		if err := d.Users.SoftDelete(r.Context(), uc.UserID); err != nil {
			WriteError(w, r, platform.ErrInternal("USER.DELETE_FAILED", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

// /devices ──────────────────────────────────────────────────────────

type upsertDeviceReq struct {
	DeviceID   string `json:"device_id"`
	Platform   string `json:"platform"`
	PushToken  string `json:"push_token,omitempty"`
	AppVersion string `json:"app_version,omitempty"`
}

func handleUpsertDevice(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		var in upsertDeviceReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		if in.DeviceID == "" {
			WriteError(w, r, platform.ErrBadRequest("DEVICE.ID_REQUIRED", "device_id required", nil))
			return
		}
		p := devices.Platform(in.Platform)
		if !p.IsValid() {
			WriteError(w, r, platform.ErrBadRequest("DEVICE.PLATFORM_INVALID", "platform must be ios|android", nil))
			return
		}
		err := d.Devices.Upsert(r.Context(), devices.UpsertInput{
			UserID:     uc.UserID,
			DeviceID:   in.DeviceID,
			Platform:   p,
			PushToken:  in.PushToken,
			AppVersion: in.AppVersion,
			IP:         r.RemoteAddr,
		})
		if err != nil {
			WriteError(w, r, platform.ErrInternal("DEVICE.UPSERT_FAILED", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}
