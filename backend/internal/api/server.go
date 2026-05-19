// Package api 装载 HTTP 路由 / 中间件 / handler。
package api

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/ai/chat"
	"github.com/sencloud/finme-backend/internal/ai/qwen"
	"github.com/sencloud/finme-backend/internal/auth"
	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/devices"
	"github.com/sencloud/finme-backend/internal/ding"
	"github.com/sencloud/finme-backend/internal/onboarding"
	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
	"github.com/sencloud/finme-backend/internal/users"
)

// Deps 是 HTTP 层用到的所有依赖。
type Deps struct {
	Config     *platform.Config
	Logger     zerolog.Logger
	Store      *store.Store
	Auth       *auth.Service
	Users      *users.Service
	Devices    *devices.Service
	Billing    *billing.Service
	Ding       *ding.Service
	Onboarding *onboarding.Service
	Chat       *chat.Service
	Qwen       *qwen.VisionClient
}

// NewRouter 装配业务路由。
func NewRouter(d *Deps) http.Handler {
	r := chi.NewRouter()

	r.Use(middleware.RealIP)
	r.Use(requestIDMiddleware)
	r.Use(loggerMiddleware(d.Logger))
	r.Use(middleware.Recoverer)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"}, // 上线前替换为白名单
		AllowedMethods:   []string{"GET", "POST", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"*"},
		ExposedHeaders:   []string{"X-Request-Id"},
		AllowCredentials: false,
		MaxAge:           300,
	}))
	r.Use(metricsMiddleware)

	r.Get("/healthz", handleHealthz(d))
	r.Get("/readyz", handleReadyz(d))
	r.Get("/metrics", handleMetrics(d))

	// SSE 子路由：JWT + audit，但不挂 middleware.Timeout —— chi 的 timeout
	// 用 http.TimeoutHandler 包了 ResponseWriter，会让 SSE handler 拿不到
	// http.Flusher，且 60s 强制 cancel ctx 切断长流。
	r.Route("/v1", func(r chi.Router) {
		r.Group(func(r chi.Router) {
			r.Use(JWTMiddleware(d.Auth))
			r.Use(auditMiddleware(d.Store))
			mountAIChat(r, d)
			mountDingLong(r, d)
		})

		// 其余路由统一加全局 60s 超时
		r.Group(func(r chi.Router) {
			r.Use(middleware.Timeout(d.Config.Server.WriteTimeout()))

			// 客户端错误上报：不挂 audit middleware（handler 自身已经写一条
			// action='client.error' 的 audit_log，避免重复）。
			mountClientError(r, d)

			r.Group(func(r chi.Router) {
				r.Use(auditMiddleware(d.Store))
				mountAuth(r, d)
				mountBillingPublic(r, d)
			})
			r.Group(func(r chi.Router) {
				r.Use(JWTMiddleware(d.Auth))
				r.Use(auditMiddleware(d.Store))
				mountMe(r, d)
				mountDevices(r, d)
				mountBillingPrivate(r, d)
				mountDing(r, d)
				mountPortfolioParse(r, d)
			})
		})
	})

	return r
}

// 简单的 GET /healthz：进程存活。
func handleHealthz(_ *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		WriteJSON(w, http.StatusOK, map[string]any{
			"status":     "ok",
			"timestamp":  time.Now().UnixMilli(),
		})
	}
}

// /readyz：进程 + DB 都正常。
func handleReadyz(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := d.Store.DB.PingContext(ctx); err != nil {
			WriteError(w, r, platform.ErrInternal("DB.PING", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"status": "ok"})
	}
}

// WriteJSON 写 JSON 响应（统一的小工具）。
func WriteJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

// WriteError 把任意 error 序列化成 {code,message,request_id}。
func WriteError(w http.ResponseWriter, r *http.Request, err error) {
	apiErr := platform.AsAPIError(err)
	if apiErr.Status >= 500 {
		platform.LoggerFrom(r.Context()).Error().
			Err(apiErr.Internal).
			Str("code", apiErr.Code).
			Msg("server error")
	} else {
		platform.LoggerFrom(r.Context()).Debug().
			Err(apiErr.Internal).
			Str("code", apiErr.Code).
			Msg("client error")
	}
	WriteJSON(w, apiErr.Status, map[string]any{
		"code":       apiErr.Code,
		"message":    apiErr.Message,
		"request_id": middleware.GetReqID(r.Context()),
	})
}

// DecodeJSON 严格 JSON 解码 + 大小限制（256KB，业务请求都够了）。
func DecodeJSON(r *http.Request, dst any) error {
	r.Body = http.MaxBytesReader(nil, r.Body, 256*1024)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return platform.ErrBadRequest("REQUEST.INVALID_JSON", "invalid json body", err)
	}
	if dec.More() {
		return platform.ErrBadRequest("REQUEST.INVALID_JSON", "multiple json values", nil)
	}
	return nil
}

// requestIDMiddleware 用 chi 自带的 RequestID。
var requestIDMiddleware = middleware.RequestID

// loggerMiddleware 把 logger 注入 ctx，并在响应后输出一条访问日志。
func loggerMiddleware(base zerolog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			rid := middleware.GetReqID(r.Context())
			l := base.With().Str("request_id", rid).Logger()
			ctx := platform.WithLogger(r.Context(), &l)
			ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
			next.ServeHTTP(ww, r.WithContext(ctx))
			l.Info().
				Str("method", r.Method).
				Str("path", r.URL.Path).
				Int("status", ww.Status()).
				Int("size", ww.BytesWritten()).
				Dur("dur", time.Since(start)).
				Str("ip", r.RemoteAddr).
				Msg("request")
		})
	}
}
