package api

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/platform"
)

// mountLive 挂载 /v1/live/* 路由。读接口对全部已登录用户开放，写接口
// 只覆盖"我的关注"两条；直播本身由 scheduler 进程自动生成，HTTP 层不暴露
// 手动触发入口（避免被滥用）。
func mountLive(r chi.Router, d *Deps) {
	r.Route("/live", func(r chi.Router) {
		r.Get("/sessions", handleLiveListSessions(d))
		r.Get("/sessions/{uuid}", handleLiveGetSession(d))
		r.Get("/reports/{id}", handleLiveGetReport(d))
		r.Get("/symbols/{symbol}", handleLiveListSymbolReports(d))
		r.Get("/watchlist", handleLiveListWatch(d))
		r.Post("/watchlist", handleLiveAddWatch(d))
		r.Delete("/watchlist/{symbol}", handleLiveRemoveWatch(d))
	})
}

// GET /v1/live/sessions?limit=20
func handleLiveListSessions(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		limit := atoiOr(r.URL.Query().Get("limit"), 20)
		items, err := d.Live.ListSessions(r.Context(), limit)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("LIVE.LIST_SESSIONS", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": items})
	}
}

// GET /v1/live/sessions/{uuid}
func handleLiveGetSession(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uuid := strings.TrimSpace(chi.URLParam(r, "uuid"))
		if uuid == "" {
			WriteError(w, r, platform.ErrBadRequest("LIVE.UUID_REQUIRED", "uuid required", nil))
			return
		}
		detail, err := d.Live.GetSessionDetail(r.Context(), uuid)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("LIVE.GET_SESSION", err))
			return
		}
		if detail == nil {
			WriteError(w, r, platform.ErrNotFound("LIVE.SESSION_NOT_FOUND", "session not found"))
			return
		}
		WriteJSON(w, http.StatusOK, detail)
	}
}

// GET /v1/live/reports/{id}
func handleLiveGetReport(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		idStr := chi.URLParam(r, "id")
		id, err := strconv.ParseInt(idStr, 10, 64)
		if err != nil || id <= 0 {
			WriteError(w, r, platform.ErrBadRequest("LIVE.BAD_ID", "invalid report id", err))
			return
		}
		rp, err := d.Live.GetReport(r.Context(), id)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("LIVE.GET_REPORT", err))
			return
		}
		if rp == nil {
			WriteError(w, r, platform.ErrNotFound("LIVE.REPORT_NOT_FOUND", "report not found"))
			return
		}
		WriteJSON(w, http.StatusOK, rp)
	}
}

// GET /v1/live/symbols/{symbol}?limit=12
func handleLiveListSymbolReports(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sym := strings.TrimSpace(chi.URLParam(r, "symbol"))
		limit := atoiOr(r.URL.Query().Get("limit"), 12)
		rows, err := d.Live.ListReportsBySymbol(r.Context(), sym, limit)
		if err != nil {
			WriteError(w, r, platform.ErrBadRequest("LIVE.SYMBOL_QUERY", err.Error(), err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": rows, "symbol": strings.ToUpper(sym)})
	}
}

// GET /v1/live/watchlist
func handleLiveListWatch(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		rows, err := d.Live.ListWatch(r.Context(), uc.UserID)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("LIVE.LIST_WATCH", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": rows})
	}
}

// POST /v1/live/watchlist  {symbol, name}
func handleLiveAddWatch(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		var in struct {
			Symbol string `json:"symbol"`
			Name   string `json:"name"`
		}
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		if err := d.Live.AddWatch(r.Context(), uc.UserID, in.Symbol, in.Name); err != nil {
			WriteError(w, r, platform.ErrBadRequest("LIVE.ADD_WATCH", err.Error(), err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

// DELETE /v1/live/watchlist/{symbol}
func handleLiveRemoveWatch(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		sym := chi.URLParam(r, "symbol")
		if err := d.Live.RemoveWatch(r.Context(), uc.UserID, sym); err != nil {
			WriteError(w, r, platform.ErrBadRequest("LIVE.REMOVE_WATCH", err.Error(), err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

func atoiOr(s string, def int) int {
	n, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil || n <= 0 {
		return def
	}
	return n
}
