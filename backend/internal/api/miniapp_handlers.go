package api

import (
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/miniapp"
	"github.com/sencloud/finme-backend/internal/platform"
)

const maxMiniAppBody = 16 << 10

// mountMiniAppsPublic 小应用公开接口：官方模板浏览 / 试运行（未登录可用，私人数据为空）。
//
//	GET  /v1/miniapps/catalog?topic=money
//	GET  /v1/miniapps/templates?topic=money
//	POST /v1/miniapps/templates/{id}/run   {"inputs":{...}}
func mountMiniAppsPublic(r chi.Router, d *Deps) {
	r.Get("/miniapps/catalog", handleMiniAppCatalog(d))
	r.Get("/miniapps/templates", handleMiniAppTemplates(d))
	r.Post("/miniapps/templates/{id}/run", handleMiniAppTemplateRun(d))
}

// mountMiniAppsPrivate 小应用需登录的接口（全部按用户私有）。
func mountMiniAppsPrivate(r chi.Router, d *Deps) {
	r.Get("/miniapps", handleMiniAppList(d))
	r.Post("/miniapps/generate", handleMiniAppGenerate(d))
	r.Get("/miniapps/gens/{rid}", handleMiniAppGen(d))
	r.Get("/miniapps/sessions/{sid}", handleMiniAppSession(d))
	r.Post("/miniapps/from-template", handleMiniAppFromTemplate(d))
	r.Post("/miniapps/mounts/order", handleMiniAppReorder(d))
	r.Get("/miniapps/{id}", handleMiniAppGet(d))
	r.Patch("/miniapps/{id}", handleMiniAppRename(d))
	r.Delete("/miniapps/{id}", handleMiniAppDelete(d))
	r.Get("/miniapps/{id}/versions", handleMiniAppVersions(d))
	r.Post("/miniapps/{id}/restore", handleMiniAppRestore(d))
	r.Post("/miniapps/{id}/mount", handleMiniAppMount(d))
	r.Delete("/miniapps/{id}/mount", handleMiniAppUnmount(d))
	r.Post("/miniapps/{id}/run", handleMiniAppRun(d))
	r.Post("/miniapps/{id}/state", handleMiniAppState(d))
}

func miniAppsDisabled(w http.ResponseWriter, r *http.Request, d *Deps) bool {
	if d.MiniApps == nil {
		WriteError(w, r, platform.ErrUnavailable("MINIAPP.DISABLED", errors.New("miniapps disabled")))
		return true
	}
	return false
}

func topicParam(r *http.Request) string {
	t := strings.TrimSpace(r.URL.Query().Get("topic"))
	if t == "" {
		return "money"
	}
	return t
}

// writeMiniAppError 把业务错误映射成 HTTP 错误。
func writeMiniAppError(w http.ResponseWriter, r *http.Request, d *Deps, err error) {
	var p miniapp.Prices
	if d.MiniApps != nil {
		p = d.MiniApps.Prices()
	}
	switch {
	case errors.Is(err, miniapp.ErrNotFound):
		WriteError(w, r, platform.ErrNotFound("MINIAPP.NOT_FOUND", "小应用不存在或已删除"))
	case errors.Is(err, miniapp.ErrBadTopic):
		WriteError(w, r, platform.ErrBadRequest("MINIAPP.BAD_TOPIC", "主题不正确", err))
	case errors.Is(err, miniapp.ErrBadRequestID):
		WriteError(w, r, platform.ErrBadRequest("MINIAPP.BAD_REQUEST_ID", "request_id 无效", err))
	case errors.Is(err, miniapp.ErrBadMessage):
		WriteError(w, r, platform.ErrBadRequest("MINIAPP.BAD_MESSAGE",
			fmt.Sprintf("说说想要什么小工具（不超过 %d 字）", miniapp.MaxMessageRunes), err))
	case errors.Is(err, miniapp.ErrBadInput):
		WriteError(w, r, platform.ErrBadRequest("MINIAPP.BAD_INPUT", strings.TrimPrefix(err.Error(), miniapp.ErrBadInput.Error()+": "), err))
	case errors.Is(err, miniapp.ErrAppLimit):
		WriteError(w, r, platform.ErrConflict("MINIAPP.APP_LIMIT",
			fmt.Sprintf("每个主题最多 %d 个小应用，先删掉不用的再来", miniapp.MaxAppsPerTopic)))
	case errors.Is(err, miniapp.ErrMountLimit):
		WriteError(w, r, platform.ErrConflict("MINIAPP.MOUNT_LIMIT",
			fmt.Sprintf("发现页最多放 %d 个小应用，先取下一个", miniapp.MaxMountedPerTopic)))
	case errors.Is(err, miniapp.ErrTooFast):
		WriteError(w, r, platform.ErrTooManyRequests("MINIAPP.TOO_FAST", "生成太频繁了，歇一分钟再来"))
	case errors.Is(err, miniapp.ErrDailyLimit):
		WriteError(w, r, platform.ErrTooManyRequests("MINIAPP.DAILY_LIMIT", "今天生成次数已用完，明天再来"))
	case errors.Is(err, miniapp.ErrRunRateLimit):
		WriteError(w, r, platform.ErrTooManyRequests("MINIAPP.RUN_LIMIT", "刷新太频繁了，稍后再试"))
	case errors.Is(err, miniapp.ErrGenBusy):
		WriteError(w, r, platform.ErrConflict("MINIAPP.GEN_BUSY", "上一条还在生成中，请稍候"))
	case errors.Is(err, miniapp.ErrUnavailable):
		WriteError(w, r, platform.ErrUnavailable("MINIAPP.GEN_UNAVAILABLE", err))
	case errors.Is(err, billing.ErrInsufficientBalance):
		WriteError(w, r, platform.ErrPaymentRequired("MINIAPP.INSUFFICIENT_BALANCE",
			fmt.Sprintf("喜点不足：新建小应用需要 %d 喜点，修改需要 %d 喜点", p.Create, p.Iterate)))
	default:
		WriteError(w, r, platform.ErrInternal("MINIAPP.INTERNAL", err))
	}
}

func handleMiniAppCatalog(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		topic := topicParam(r)
		if !miniapp.ValidTopic(topic) {
			writeMiniAppError(w, r, d, miniapp.ErrBadTopic)
			return
		}
		type src struct {
			ID    string `json:"id"`
			Title string `json:"title"`
		}
		var srcs []src
		for _, s := range d.MiniApps.Registry().ForTopic(topic) {
			srcs = append(srcs, src{ID: s.ID, Title: s.Title})
		}
		p := d.MiniApps.Prices()
		WriteJSON(w, http.StatusOK, map[string]any{
			"schema":           miniapp.SchemaID,
			"renderer_version": miniapp.RendererVersion,
			"prices":           map[string]int64{"create": p.Create, "iterate": p.Iterate},
			"limits": map[string]int{"apps": miniapp.MaxAppsPerTopic, "mounted": miniapp.MaxMountedPerTopic,
				"message_runes": miniapp.MaxMessageRunes},
			"generation": d.MiniApps.LLMConfigured(),
			"disclaimer": miniapp.Disclaimer(topic),
			"sources":    srcs,
		})
	}
}

func handleMiniAppTemplates(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		topic := topicParam(r)
		if !miniapp.ValidTopic(topic) {
			writeMiniAppError(w, r, d, miniapp.ErrBadTopic)
			return
		}
		items := d.MiniApps.Templates(topic)
		if items == nil {
			items = []*miniapp.Template{}
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": items})
	}
}

type runBody struct {
	Inputs map[string]any `json:"inputs"`
}

func handleMiniAppTemplateRun(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		var body runBody
		if r.ContentLength != 0 {
			if err := decodeJSONLarge(r, &body, maxMiniAppBody); err != nil {
				WriteError(w, r, err)
				return
			}
		}
		res, err := d.MiniApps.RunTemplate(r.Context(), optionalUserID(d, r), clientIP(r), chi.URLParam(r, "id"), body.Inputs)
		if err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, res)
	}
}

func clientIP(r *http.Request) string {
	ip := r.RemoteAddr
	if i := strings.LastIndexByte(ip, ':'); i > 0 && !strings.Contains(ip[i:], "]") {
		ip = ip[:i]
	}
	return ip
}

func handleMiniAppList(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		items, err := d.MiniApps.List(r.Context(), MustUser(r).UserID, topicParam(r))
		if err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": items})
	}
}

func handleMiniAppGenerate(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		uc := MustUser(r)
		var body miniapp.GenRequest
		if err := decodeJSONLarge(r, &body, maxMiniAppBody); err != nil {
			WriteError(w, r, err)
			return
		}
		g, err := d.MiniApps.Generate(r.Context(), uc.UserID, body)
		if err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"gen": g, "balance": creditBalance(r.Context(), d, uc.UserID)})
	}
}

func handleMiniAppGen(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		uc := MustUser(r)
		g, err := d.MiniApps.Gen(r.Context(), uc.UserID, chi.URLParam(r, "rid"))
		if err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		out := map[string]any{"gen": g}
		if g.Status != miniapp.GenPending {
			out["balance"] = creditBalance(r.Context(), d, uc.UserID)
		}
		WriteJSON(w, http.StatusOK, out)
	}
}

func handleMiniAppSession(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		items, err := d.MiniApps.Session(r.Context(), MustUser(r).UserID, chi.URLParam(r, "sid"))
		if err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": items})
	}
}

func handleMiniAppFromTemplate(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		var body struct {
			TemplateID string `json:"template_id"`
		}
		if err := decodeJSONLarge(r, &body, maxMiniAppBody); err != nil {
			WriteError(w, r, err)
			return
		}
		app, err := d.MiniApps.FromTemplate(r.Context(), MustUser(r).UserID, body.TemplateID)
		if err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"app": app})
	}
}

func handleMiniAppReorder(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		var body struct {
			Topic string   `json:"topic"`
			IDs   []string `json:"ids"`
		}
		if err := decodeJSONLarge(r, &body, maxMiniAppBody); err != nil {
			WriteError(w, r, err)
			return
		}
		items, err := d.MiniApps.Reorder(r.Context(), MustUser(r).UserID, body.Topic, body.IDs)
		if err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": items})
	}
}

func handleMiniAppGet(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		app, err := d.MiniApps.Get(r.Context(), MustUser(r).UserID, chi.URLParam(r, "id"))
		if err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"app": app})
	}
}

func handleMiniAppRename(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		var body struct {
			Title *string `json:"title"`
			Icon  *string `json:"icon"`
		}
		if err := decodeJSONLarge(r, &body, maxMiniAppBody); err != nil {
			WriteError(w, r, err)
			return
		}
		app, err := d.MiniApps.Rename(r.Context(), MustUser(r).UserID, chi.URLParam(r, "id"), body.Title, body.Icon)
		if err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"app": app})
	}
}

func handleMiniAppDelete(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		if err := d.MiniApps.Delete(r.Context(), MustUser(r).UserID, chi.URLParam(r, "id")); err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

func handleMiniAppVersions(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		items, err := d.MiniApps.Versions(r.Context(), MustUser(r).UserID, chi.URLParam(r, "id"))
		if err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": items})
	}
}

func handleMiniAppRestore(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		var body struct {
			Version int `json:"version"`
		}
		if err := decodeJSONLarge(r, &body, maxMiniAppBody); err != nil {
			WriteError(w, r, err)
			return
		}
		app, err := d.MiniApps.Restore(r.Context(), MustUser(r).UserID, chi.URLParam(r, "id"), body.Version)
		if err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"app": app})
	}
}

func handleMiniAppMount(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		var body struct {
			CardSize string `json:"card_size"`
		}
		if r.ContentLength != 0 {
			if err := decodeJSONLarge(r, &body, maxMiniAppBody); err != nil {
				WriteError(w, r, err)
				return
			}
		}
		app, err := d.MiniApps.Mount(r.Context(), MustUser(r).UserID, chi.URLParam(r, "id"), body.CardSize)
		if err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"app": app})
	}
}

func handleMiniAppUnmount(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		if err := d.MiniApps.Unmount(r.Context(), MustUser(r).UserID, chi.URLParam(r, "id")); err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

func handleMiniAppRun(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		var body runBody
		if r.ContentLength != 0 {
			if err := decodeJSONLarge(r, &body, maxMiniAppBody); err != nil {
				WriteError(w, r, err)
				return
			}
		}
		res, err := d.MiniApps.Run(r.Context(), MustUser(r).UserID, chi.URLParam(r, "id"), body.Inputs)
		if err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, res)
	}
}

func handleMiniAppState(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if miniAppsDisabled(w, r, d) {
			return
		}
		var body struct {
			Inputs map[string]any `json:"inputs"`
			State  map[string]any `json:"state"`
		}
		if err := decodeJSONLarge(r, &body, maxMiniAppBody); err != nil {
			WriteError(w, r, err)
			return
		}
		app, err := d.MiniApps.SaveState(r.Context(), MustUser(r).UserID, chi.URLParam(r, "id"), body.Inputs, body.State)
		if err != nil {
			writeMiniAppError(w, r, d, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"app": app})
	}
}
