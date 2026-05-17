package api

import (
	"context"
	"net/http"
	"strings"

	"github.com/sencloud/finme-backend/internal/auth"
	"github.com/sencloud/finme-backend/internal/platform"
)

// userCtxKey 用强类型避免 ctx key 冲突。
type userCtxKey struct{}

// UserContext 是路由处理器从 ctx 拿到的当前登录用户的最小信息。
type UserContext struct {
	UserID   int64
	UserUUID string
	JTI      string
}

// JWTMiddleware 校验 Authorization: Bearer <access_token>，注入 UserContext。
func JWTMiddleware(a *auth.Service) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			h := r.Header.Get("Authorization")
			if !strings.HasPrefix(h, "Bearer ") {
				WriteError(w, r, platform.ErrUnauthorized("AUTH.MISSING_TOKEN", "missing bearer token"))
				return
			}
			tok := strings.TrimPrefix(h, "Bearer ")
			c, err := a.ParseAccess(tok)
			if err != nil {
				WriteError(w, r, platform.ErrUnauthorized("AUTH.TOKEN_INVALID", err.Error()))
				return
			}
			uc := UserContext{
				UserID:   c.UserID,
				UserUUID: c.UserUUID,
				JTI:      c.JTI,
			}
			ctx := context.WithValue(r.Context(), userCtxKey{}, uc)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// MustUser 在受保护的 handler 中读取 UserContext。
// 调用方保证已经过 JWTMiddleware；缺失时 panic（路由配错才会发生）。
func MustUser(r *http.Request) UserContext {
	uc, ok := r.Context().Value(userCtxKey{}).(UserContext)
	if !ok {
		panic("MustUser called outside JWTMiddleware")
	}
	return uc
}
