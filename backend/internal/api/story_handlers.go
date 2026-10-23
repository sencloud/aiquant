package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/story"
)

// mountStory 挂载《天亮以前》的进度 / 结局 / AI 聊天。
//
// 路由放在无 middleware.Timeout 的 SSE 分组里：故事聊天和 AI 聊天一样，
// 可能连续流式输出超过 60s；进度接口跟着一起挂，避免两套前缀。
func mountStory(r chi.Router, d *Deps) {
	r.Get("/story/state", handleStoryState(d))
	r.Get("/story/endings", handleStoryEndings(d))
	r.Put("/story/runs/{id}", handleStorySave(d))
	r.Post("/story/runs/{id}/chat", handleStoryChat(d))
	r.Delete("/story/runs/{id}", handleStoryDelete(d))
}

// mountStoryPublic 只暴露开关本身（不含用户数据），客户端打开试用版时先读它。
func mountStoryPublic(r chi.Router, d *Deps) {
	r.Get("/story/config", handleStoryConfig(d))
}

// mountStoryAdmin 用 X-Admin-Key 更新试用版开关；key 沿用 nautilus admin_key。
func mountStoryAdmin(r chi.Router, d *Deps) {
	r.Route("/admin/story", func(r chi.Router) {
		r.Use(adminKeyMiddleware(d))
		r.Put("/config", handleStoryAdminConfig(d))
	})
}

func handleStoryConfig(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if d.Story == nil {
			WriteError(w, r, platform.ErrUnavailable("STORY.NOT_CONFIGURED", errors.New("story disabled")))
			return
		}
		cfg, err := d.Story.Config(r.Context())
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, cfg)
	}
}

func handleStoryAdminConfig(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if d.Story == nil {
			WriteError(w, r, platform.ErrUnavailable("STORY.NOT_CONFIGURED", errors.New("story disabled")))
			return
		}
		var body story.ConfigInput
		if err := DecodeJSON(r, &body); err != nil {
			WriteError(w, r, err)
			return
		}
		cfg, err := d.Story.SetConfig(r.Context(), body)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, cfg)
	}
}

func handleStoryState(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if d.Story == nil {
			WriteError(w, r, platform.ErrUnavailable("STORY.NOT_CONFIGURED", errors.New("story disabled")))
			return
		}
		uc := MustUser(r)
		st, err := d.Story.State(r.Context(), uc.UserID, r.URL.Query().Get("run_id"))
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, st)
	}
}

func handleStoryEndings(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if d.Story == nil {
			WriteError(w, r, platform.ErrUnavailable("STORY.NOT_CONFIGURED", errors.New("story disabled")))
			return
		}
		uc := MustUser(r)
		endings, err := d.Story.Endings(r.Context(), uc.UserID)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"endings": endings})
	}
}

func handleStorySave(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if d.Story == nil {
			WriteError(w, r, platform.ErrUnavailable("STORY.NOT_CONFIGURED", errors.New("story disabled")))
			return
		}
		uc := MustUser(r)
		var body story.SaveInput
		if err := DecodeJSON(r, &body); err != nil {
			WriteError(w, r, err)
			return
		}
		run, err := d.Story.Save(r.Context(), uc.UserID, chi.URLParam(r, "id"), body)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"run": run})
	}
}

func handleStoryDelete(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if d.Story == nil {
			WriteError(w, r, platform.ErrUnavailable("STORY.NOT_CONFIGURED", errors.New("story disabled")))
			return
		}
		uc := MustUser(r)
		err := d.Story.Delete(r.Context(), uc.UserID, chi.URLParam(r, "id"))
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

// handleStoryChat 是故事自由聊天的 SSE 入口。
func handleStoryChat(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if d.Story == nil {
			WriteError(w, r, platform.ErrUnavailable("STORY.NOT_CONFIGURED", errors.New("story disabled")))
			return
		}
		uc := MustUser(r)
		var body story.ChatInput
		if err := DecodeJSON(r, &body); err != nil {
			WriteError(w, r, err)
			return
		}
		flusher, ok := w.(http.Flusher)
		if !ok {
			WriteError(w, r, platform.ErrInternal("SSE.NO_FLUSHER", errors.New("response writer is not a flusher")))
			return
		}
		rc := http.NewResponseController(w)
		_ = rc.SetWriteDeadline(time.Time{})
		_ = rc.SetReadDeadline(time.Time{})

		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache, no-transform")
		w.Header().Set("Connection", "keep-alive")
		w.Header().Set("X-Accel-Buffering", "no")
		w.WriteHeader(http.StatusOK)
		flusher.Flush()

		var mu sync.Mutex
		emit := func(event string, data any) error {
			raw, err := json.Marshal(data)
			if err != nil {
				return err
			}
			mu.Lock()
			defer mu.Unlock()
			if _, err := fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event, raw); err != nil {
				return err
			}
			flusher.Flush()
			return nil
		}

		if err := d.Story.Chat(r.Context(), uc.UserID, chi.URLParam(r, "id"), body, emit); err != nil {
			var apiErr *platform.APIError
			if errors.As(err, &apiErr) {
				_ = emit("error", map[string]any{"code": apiErr.Code, "message": apiErr.Message})
				return
			}
			_ = emit("error", map[string]any{"code": "STORY.CHAT", "message": err.Error()})
		}
	}
}
