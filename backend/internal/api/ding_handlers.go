package api

import (
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/ding"
	"github.com/sencloud/finme-backend/internal/platform"
)

func mountDing(r chi.Router, d *Deps) {
	r.Route("/ding/tasks", func(r chi.Router) {
		r.Get("/", handleListTasks(d))
		r.Post("/", handleCreateTask(d))
		r.Patch("/{uuid}", handleUpdateTask(d))
		r.Delete("/{uuid}", handleDeleteTask(d))
		r.Post("/{uuid}/runs", handleReportRun(d))
	})
	r.Route("/notifications", func(r chi.Router) {
		r.Get("/", handleListNotif(d))
		r.Get("/unread-count", handleUnreadCount(d))
		r.Get("/{uuid}", handleGetNotif(d))
		r.Patch("/{uuid}/read", handleMarkRead(d))
		r.Post("/mark-all-read", handleMarkAllRead(d))
		r.Delete("/{uuid}", handleDeleteNotif(d))
	})
}

// ── Tasks ──────────────────────────────────────────────────────────────

func handleListTasks(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		rows, err := d.Ding.ListTasks(r.Context(), uc.UserID)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		out := make([]any, 0, len(rows))
		for _, t := range rows {
			out = append(out, t.ToDTO())
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": out})
	}
}

func handleCreateTask(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		var in ding.CreateTaskReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		t, err := d.Ding.CreateTask(r.Context(), uc.UserID, in)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, t.ToDTO())
	}
}

func handleUpdateTask(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		uuid := chi.URLParam(r, "uuid")
		var in ding.UpdateTaskReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		t, err := d.Ding.UpdateTask(r.Context(), uc.UserID, uuid, in)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, t.ToDTO())
	}
}

func handleDeleteTask(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		uuid := chi.URLParam(r, "uuid")
		if err := d.Ding.DeleteTask(r.Context(), uc.UserID, uuid); err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

func handleReportRun(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		uuid := chi.URLParam(r, "uuid")
		var in ding.ReportRunReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		// URL 路径里的 uuid 优先级高于 body
		if uuid != "" {
			in.TaskUUID = uuid
		}
		if in.TaskUUID == "" {
			WriteError(w, r, platform.ErrBadRequest("DING.TASK_UUID_REQUIRED",
				"task_uuid required", nil))
			return
		}
		_, n, err := d.Ding.ReportRun(r.Context(), uc.UserID, in)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		out := map[string]any{"ok": true}
		if n != nil {
			out["notification"] = n.ToDTO()
		}
		WriteJSON(w, http.StatusOK, out)
	}
}

// ── Notifications ─────────────────────────────────────────────────────

func handleListNotif(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		q := r.URL.Query()
		var cursor int64
		if c := q.Get("cursor"); c != "" {
			cursor, _ = strconv.ParseInt(c, 10, 64)
		}
		var limit int
		if l := q.Get("limit"); l != "" {
			n, _ := strconv.Atoi(l)
			limit = n
		}
		unreadOnly := q.Get("unread_only") == "1" || q.Get("unread_only") == "true"
		rows, next, err := d.Ding.ListNotifications(r.Context(), uc.UserID, cursor, limit, unreadOnly)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		out := make([]any, 0, len(rows))
		for _, n := range rows {
			out = append(out, n.ToDTO())
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"items":       out,
			"next_cursor": next,
		})
	}
}

func handleGetNotif(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		uuid := chi.URLParam(r, "uuid")
		n, err := d.Ding.GetNotification(r.Context(), uc.UserID, uuid)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, n.ToDTO())
	}
}

func handleMarkRead(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		uuid := chi.URLParam(r, "uuid")
		if err := d.Ding.MarkRead(r.Context(), uc.UserID, uuid); err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

func handleMarkAllRead(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		n, err := d.Ding.MarkAllRead(r.Context(), uc.UserID)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"affected": n})
	}
}

func handleUnreadCount(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		n, err := d.Ding.UnreadCount(r.Context(), uc.UserID)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"unread": n})
	}
}

func handleDeleteNotif(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		uuid := chi.URLParam(r, "uuid")
		if err := d.Ding.DeleteNotification(r.Context(), uc.UserID, uuid); err != nil {
			WriteError(w, r, err)
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}
