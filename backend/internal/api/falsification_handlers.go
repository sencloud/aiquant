package api

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/falsification"
	"github.com/sencloud/finme-backend/internal/platform"
)

// mountFalsificationPublic 证伪档案公开接口（免登录）。
//
//	GET /v1/strategy/falsification[?include=insufficient]
//	GET /v1/strategy/falsification/run-options
//
// 档案是获客内容：不登录也能看结论、关键数字和闸门结果。带了有效 token 时，
// 已解锁条目直接带上付费字段（分年盈亏 / 失效机制 / 复现命令）。
// report_url 永远不出现在响应里。
func mountFalsificationPublic(r chi.Router, d *Deps) {
	r.Get("/strategy/falsification", handleFalsificationArchive(d))
	r.Get("/strategy/falsification/run-options", handleFalsificationRunOptions(d))
}

// mountFalsificationPrivate 证伪档案付费接口（需登录）。
func mountFalsificationPrivate(r chi.Router, d *Deps) {
	r.Get("/strategy/falsification/unlocks", handleFalsificationUnlocks(d))
	r.Get("/strategy/falsification/{id}/detail", handleFalsificationDetail(d))
	r.Post("/strategy/falsification/{id}/unlock", handleFalsificationUnlock(d))
	r.Get("/strategy/falsification/runs", handleFalsificationListRuns(d))
	r.Post("/strategy/falsification/runs", handleFalsificationCreateRun(d))
	r.Get("/strategy/falsification/runs/{id}", handleFalsificationGetRun(d))
}

// optionalUserID 解析可选的 Bearer token；无 / 无效都返回 0，不报错。
func optionalUserID(d *Deps, r *http.Request) int64 {
	if d.Auth == nil {
		return 0
	}
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, "Bearer ") {
		return 0
	}
	c, err := d.Auth.ParseAccess(strings.TrimPrefix(h, "Bearer "))
	if err != nil {
		return 0
	}
	return c.UserID
}

func handleFalsificationArchive(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if d.Falsification == nil {
			WriteError(w, r, platform.ErrUnavailable("FALSIFICATION.DISABLED", errors.New("falsification disabled")))
			return
		}
		ctx := r.Context()
		p, origin := d.Falsification.Current(ctx)
		var unlocked map[string]bool
		if uid := optionalUserID(d, r); uid > 0 {
			if ids, err := d.Falsification.UnlockedIDs(ctx, uid); err == nil {
				unlocked = ids
			}
		}
		include := r.URL.Query().Get("include") == "insufficient"
		out := falsification.PublicView(p, include, unlocked)
		out["origin"] = origin
		out["prices"] = d.Falsification.Prices()
		w.Header().Set("Cache-Control", "no-store")
		WriteJSON(w, http.StatusOK, out)
	}
}

func handleFalsificationRunOptions(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if d.Falsification == nil {
			WriteError(w, r, platform.ErrUnavailable("FALSIFICATION.DISABLED", errors.New("falsification disabled")))
			return
		}
		WriteJSON(w, http.StatusOK, d.Falsification.Options(r.Context()))
	}
}

func handleFalsificationUnlocks(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		ids, err := d.Falsification.UnlockedIDs(r.Context(), uc.UserID)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("FALSIFICATION.UNLOCKS", err))
			return
		}
		list := make([]string, 0, len(ids))
		for id := range ids {
			list = append(list, id)
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"ids":   list,
			"price": d.Falsification.Prices().Unlock,
		})
	}
}

func handleFalsificationDetail(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		e, err := d.Falsification.Detail(r.Context(), uc.UserID, chi.URLParam(r, "id"))
		if errors.Is(err, falsification.ErrEntryNotFound) {
			WriteError(w, r, platform.ErrNotFound("FALSIFICATION.NOT_FOUND", "档案不存在"))
			return
		}
		if err != nil {
			WriteError(w, r, platform.ErrInternal("FALSIFICATION.DETAIL", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"entry": e})
	}
}

func handleFalsificationUnlock(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		res, err := d.Falsification.Unlock(r.Context(), uc.UserID, chi.URLParam(r, "id"))
		switch {
		case errors.Is(err, falsification.ErrEntryNotFound):
			WriteError(w, r, platform.ErrNotFound("FALSIFICATION.NOT_FOUND", "档案不存在"))
			return
		case errors.Is(err, billing.ErrInsufficientBalance):
			WriteError(w, r, platform.ErrPaymentRequired("FALSIFICATION.INSUFFICIENT_BALANCE", "喜点不足，充值后再解锁"))
			return
		case err != nil:
			WriteError(w, r, platform.ErrInternal("FALSIFICATION.UNLOCK", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"entry":   res.Entry,
			"charged": res.Charged,
			"already": res.Already,
			"balance": creditBalance(r.Context(), d, uc.UserID),
		})
	}
}

func handleFalsificationCreateRun(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		var body struct {
			Strategy string `json:"strategy"`
			Symbol   string `json:"symbol"`
			Freq     string `json:"freq"`
		}
		if err := DecodeJSON(r, &body); err != nil {
			WriteError(w, r, err)
			return
		}
		run, err := d.Falsification.CreateRun(r.Context(), uc.UserID, body.Strategy, body.Symbol, body.Freq)
		switch {
		case errors.Is(err, falsification.ErrInvalidRunInput):
			WriteError(w, r, platform.ErrBadRequest("FALSIFICATION.RUN_INVALID", "请选择可用的策略、品种和周期", err))
			return
		case errors.Is(err, billing.ErrInsufficientBalance):
			WriteError(w, r, platform.ErrPaymentRequired("FALSIFICATION.INSUFFICIENT_BALANCE", "喜点不足，充值后再跑"))
			return
		case err != nil:
			WriteError(w, r, platform.ErrInternal("FALSIFICATION.RUN_CREATE", err))
			return
		}
		status := http.StatusCreated
		if run.Status == falsification.RunUnsupported {
			status = http.StatusAccepted
		}
		WriteJSON(w, status, map[string]any{
			"run":     run,
			"balance": creditBalance(r.Context(), d, uc.UserID),
		})
	}
}

func handleFalsificationGetRun(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		run, err := d.Falsification.GetRun(r.Context(), uc.UserID, chi.URLParam(r, "id"))
		if errors.Is(err, falsification.ErrRunNotFound) {
			WriteError(w, r, platform.ErrNotFound("FALSIFICATION.RUN_NOT_FOUND", "任务不存在"))
			return
		}
		if err != nil {
			WriteError(w, r, platform.ErrInternal("FALSIFICATION.RUN_GET", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"run": run})
	}
}

func handleFalsificationListRuns(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		runs, err := d.Falsification.ListRuns(r.Context(), uc.UserID)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("FALSIFICATION.RUN_LIST", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": runs})
	}
}

func creditBalance(ctx context.Context, d *Deps, userID int64) int64 {
	if d.Users == nil {
		return 0
	}
	b, _ := d.Users.CreditBalance(ctx, userID)
	return b
}
