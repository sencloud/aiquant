package api

import (
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/live"
	"github.com/sencloud/finme-backend/internal/platform"
)

// mountLive 挂载 /v1/live/* 路由(v2 直播间形态)。
//
// 读接口由 scheduler 进程持续生成的房间/消息提供;
// POST /v1/live/rooms 在 api 进程内嵌的 mini-runner 上即时启动一个 origin='manual'
// 房间(全局任一时刻最多 1 个 status='live',15 分钟硬截止自动进入历史)。
func mountLive(r chi.Router, d *Deps) {
	r.Route("/live", func(r chi.Router) {
		r.Get("/rooms", handleLiveListRooms(d))
		r.Post("/rooms", handleLiveCreateRoom(d))
		r.Get("/rooms/{uuid}", handleLiveGetRoom(d))
		r.Delete("/rooms/{uuid}", handleLiveDeleteRoom(d))
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

// POST /v1/live/rooms
//
// Body (可选): {"focus_symbol": "600519.SH", "focus_name": "贵州茅台"}
//
// 行为:
//   * 检查全局 status='live' 房间数 → 已存在则 409 LIVE.ROOM_LIVE_EXISTS
//   * 创建一个 origin='manual' 房间,auto_end_at=now+15min,立即启动 liveLoop
//   * 返回 RoomBrief(客户端用 uuid 进入直播间页)
//
// 限流:Service 层依赖"全局唯一"语义已经天然防滥用,这里不另做 token bucket。
func handleLiveCreateRoom(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var in live.CreateManualInput
		// 允许空 body(用户不指定开场焦点)
		if r.ContentLength > 0 {
			if err := DecodeJSON(r, &in); err != nil {
				WriteError(w, r, err)
				return
			}
		}
		brief, err := d.Live.CreateManualRoom(r.Context(), in)
		if err != nil {
			switch {
			case errors.Is(err, live.ErrLiveAlreadyExists):
				WriteError(w, r, platform.ErrConflict(
					"LIVE.ROOM_LIVE_EXISTS",
					"已有直播间正在进行,请先进入查看或等待结束"))
			case errors.Is(err, live.ErrManualNotEnabled):
				WriteError(w, r, platform.ErrUnavailable(
					"LIVE.MANUAL_DISABLED", err))
			default:
				WriteError(w, r, platform.ErrInternal("LIVE.CREATE_ROOM", err))
			}
			return
		}
		WriteJSON(w, http.StatusCreated, brief)
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

// DELETE /v1/live/rooms/{uuid}
//
// 删除一个已结束的直播间(连同聊天记录)。正在直播的房间不允许删除。
func handleLiveDeleteRoom(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uuid := strings.TrimSpace(chi.URLParam(r, "uuid"))
		if uuid == "" {
			WriteError(w, r, platform.ErrBadRequest("LIVE.UUID_REQUIRED", "uuid required", nil))
			return
		}
		err := d.Live.DeleteRoom(r.Context(), uuid)
		if err != nil {
			switch {
			case errors.Is(err, live.ErrRoomNotFound):
				WriteError(w, r, platform.ErrNotFound("LIVE.ROOM_NOT_FOUND", "room not found"))
			case errors.Is(err, live.ErrCannotDeleteLive):
				WriteError(w, r, platform.ErrConflict(
					"LIVE.ROOM_IS_LIVE", "直播进行中,无法删除,请等待结束后再删"))
			default:
				WriteError(w, r, platform.ErrInternal("LIVE.DELETE_ROOM", err))
			}
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"deleted": true})
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
		// since_idx 语义:返回 idx 严格大于此值的消息。
		// atoiOr 在缺省/非法/<=0 时返回 0,表示客户端要"从头开始"。
		sinceIdx := atoiOr(r.URL.Query().Get("since_idx"), 0)
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
