package api

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/platform"
)

// mountLive 挂载 /v1/live/* 路由(v2 直播间形态)。
//
// 全部为读接口,且对全部登录用户开放;直播由 scheduler 进程自动生成,
// HTTP 层不暴露手动触发入口(避免被滥用 / 浪费 LLM 配额)。
func mountLive(r chi.Router, d *Deps) {
	r.Route("/live", func(r chi.Router) {
		r.Get("/rooms", handleLiveListRooms(d))
		r.Get("/rooms/{uuid}", handleLiveGetRoom(d))
		r.Get("/rooms/{uuid}/messages", handleLiveListMessages(d))
		r.Get("/kline", handleLiveKline(d))
	})
}

// GET /v1/live/rooms?limit=20
func handleLiveListRooms(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		limit := atoiOr(r.URL.Query().Get("limit"), 20)
		items, err := d.Live.ListRooms(r.Context(), limit)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("LIVE.LIST_ROOMS", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": items})
	}
}

// GET /v1/live/rooms/{uuid}?recent=30
//
// 进入房间时一次性拉房间元信息 + 最近 recent 条消息(用于首屏渲染)。
// 后续增量用 /messages?since_idx=N。
func handleLiveGetRoom(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uuid := strings.TrimSpace(chi.URLParam(r, "uuid"))
		if uuid == "" {
			WriteError(w, r, platform.ErrBadRequest("LIVE.UUID_REQUIRED", "uuid required", nil))
			return
		}
		recent := atoiOr(r.URL.Query().Get("recent"), 30)
		detail, err := d.Live.GetRoomDetail(r.Context(), uuid, recent)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("LIVE.GET_ROOM", err))
			return
		}
		if detail == nil {
			WriteError(w, r, platform.ErrNotFound("LIVE.ROOM_NOT_FOUND", "room not found"))
			return
		}
		WriteJSON(w, http.StatusOK, detail)
	}
}

// GET /v1/live/rooms/{uuid}/messages?since_idx=N
//
// 增量轮询接口。客户端每 2-3 秒调一次,since_idx 传上一次返回的 latest_idx。
func handleLiveListMessages(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uuid := strings.TrimSpace(chi.URLParam(r, "uuid"))
		if uuid == "" {
			WriteError(w, r, platform.ErrBadRequest("LIVE.UUID_REQUIRED", "uuid required", nil))
			return
		}
		sinceIdx := atoiOr(r.URL.Query().Get("since_idx"), 0) - 1
		if sinceIdx < 0 {
			sinceIdx = 0
		}
		resp, err := d.Live.MessagesSince(r.Context(), uuid, sinceIdx)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("LIVE.MESSAGES_SINCE", err))
			return
		}
		if resp == nil {
			WriteError(w, r, platform.ErrNotFound("LIVE.ROOM_NOT_FOUND", "room not found"))
			return
		}
		WriteJSON(w, http.StatusOK, resp)
	}
}

// GET /v1/live/kline?symbol=600519.SH
//
// 返回 text/html(self-contained ECharts HTML),给 Flutter webview 直接 loadHtmlString。
func handleLiveKline(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sym := strings.TrimSpace(r.URL.Query().Get("symbol"))
		if sym == "" {
			WriteError(w, r, platform.ErrBadRequest("LIVE.SYMBOL_REQUIRED", "symbol required", nil))
			return
		}
		html, err := d.Live.KlineHTML(r.Context(), sym)
		if err != nil {
			WriteError(w, r, platform.ErrBadRequest("LIVE.KLINE", err.Error(), err))
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		_, _ = w.Write([]byte(html))
	}
}

func atoiOr(s string, def int) int {
	n, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil || n <= 0 {
		return def
	}
	return n
}
