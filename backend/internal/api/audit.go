package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5/middleware"

	"github.com/sencloud/finme-backend/internal/store"
)

// auditMiddleware 把 mutating 请求（POST/PATCH/PUT/DELETE）成功响应后落 audit_log。
//
// 落库内容：
//   - user_id（如果 JWT 中有）
//   - action = "<METHOD> <path>"
//   - ip / user-agent
//   - detail_json = {"status":<code>,"req_id":<id>}
//
// 失败的请求只走访问日志；err+stack 不进 audit。
func auditMiddleware(st *store.Store) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
			start := time.Now()
			next.ServeHTTP(ww, r)
			if !shouldAudit(r) {
				return
			}
			status := ww.Status()
			if status >= 400 {
				return
			}
			var userID int64
			if uc, ok := r.Context().Value(userCtxKey{}).(UserContext); ok {
				userID = uc.UserID
			}
			rid := middleware.GetReqID(r.Context())
			detail, _ := json.Marshal(map[string]any{
				"status":  status,
				"req_id":  rid,
				"dur_ms":  time.Since(start).Milliseconds(),
			})
			// 异步写库，避免拖响应
			go func() {
				ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
				defer cancel()
				_, _ = st.DB.ExecContext(ctx, `
					INSERT INTO audit_log(user_id, action, ip, ua, detail_json, created_at)
					VALUES(?, ?, ?, ?, ?, ?)`,
					nullableInt64(userID),
					r.Method+" "+sanitizePath(r.URL.Path),
					nullableStr(r.RemoteAddr),
					nullableStr(r.UserAgent()),
					nullableStr(string(detail)),
					time.Now().UnixMilli(),
				)
			}()
		})
	}
}

func shouldAudit(r *http.Request) bool {
	switch r.Method {
	case http.MethodPost, http.MethodPatch, http.MethodPut, http.MethodDelete:
		// 跳过部分高频低价值的端点：/v1/auth/sms/send 太密 → 不审计
		if strings.HasPrefix(r.URL.Path, "/v1/auth/sms/send") {
			return false
		}
		return strings.HasPrefix(r.URL.Path, "/v1/")
	default:
		return false
	}
}

// 路径里别带 query，保持 audit log 体积小
func sanitizePath(p string) string {
	if i := strings.IndexByte(p, '?'); i >= 0 {
		return p[:i]
	}
	return p
}

func nullableInt64(v int64) any {
	if v == 0 {
		return nil
	}
	return v
}

func nullableStr(s string) any {
	if s == "" {
		return nil
	}
	return s
}
