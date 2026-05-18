package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

// mountClientError 公开路由 — 客户端 runZonedGuarded 捕获到未处理异常时
// 轻量上报，落 audit_log(action='client.error')。
//
// 设计原则：
//   - 不暴露任何业务字段，仅记 message / type / location 摘要；
//   - body 上限 64KB（外层 DecodeJSON 已限制 256KB，再做截断兜底）；
//   - 始终返回 200，避免循环上报；
//   - 若 Authorization 携带合法 access_token，提取 user_id；否则匿名记录。
func mountClientError(r chi.Router, d *Deps) {
	r.Post("/client/error", handleClientError(d))
}

type clientErrorReq struct {
	Type     string `json:"type,omitempty"`     // flutter / dart / network ...
	Message  string `json:"message,omitempty"`  // 错误信息
	Stack    string `json:"stack,omitempty"`    // 调用栈（只取前 4KB）
	Path     string `json:"path,omitempty"`     // 当前路由 / Widget 名
	Platform string `json:"platform,omitempty"` // ios / android
	Version  string `json:"version,omitempty"`  // app version
}

func handleClientError(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var in clientErrorReq
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		var userID int64
		if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
			if c, err := d.Auth.ParseAccess(strings.TrimPrefix(h, "Bearer ")); err == nil {
				userID = c.UserID
			}
		}

		detail, _ := json.Marshal(map[string]any{
			"type":     trim(in.Type, 64),
			"message":  trim(in.Message, 512),
			"stack":    trim(in.Stack, 4096),
			"path":     trim(in.Path, 256),
			"platform": trim(in.Platform, 32),
			"version":  trim(in.Version, 32),
			"req_id":   middleware.GetReqID(r.Context()),
		})

		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			_, _ = d.Store.DB.ExecContext(ctx, `
				INSERT INTO audit_log(user_id, action, ip, ua, detail_json, created_at)
				VALUES(?, ?, ?, ?, ?, ?)`,
				nullableInt64(userID),
				"client.error",
				nullableStr(r.RemoteAddr),
				nullableStr(r.UserAgent()),
				nullableStr(string(detail)),
				time.Now().UnixMilli(),
			)
		}()

		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

// trim 把字符串截到 max 字节以内，并保证截断点落在合法的 UTF-8 边界，
// 避免中文/emoji 被切成半个码点导致 audit_log 出现 \ufffd 乱码。
func trim(s string, max int) string {
	s = strings.TrimSpace(s)
	if len(s) <= max {
		return s
	}
	cut := max
	for cut > 0 && !utf8.RuneStart(s[cut]) {
		cut--
	}
	return s[:cut]
}
