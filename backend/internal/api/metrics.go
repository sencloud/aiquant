package api

import (
	"fmt"
	"net/http"
	"runtime"
	"sync/atomic"
	"time"
)

// metricsState 是进程内极简指标。
//
// 不引入 prometheus/client_golang —— 单进程低 QPS 阶段够用；
// 上规模后再换 prom 客户端即可。
type metricsState struct {
	startedAt    int64
	requestTotal atomic.Int64
	errorTotal   atomic.Int64
	authFails    atomic.Int64
}

var globalMetrics = &metricsState{startedAt: time.Now().Unix()}

// metricsMiddleware 在响应链路上打点。
func metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		globalMetrics.requestTotal.Add(1)
		ww := &statusRecorder{ResponseWriter: w, code: 200}
		next.ServeHTTP(ww, r)
		if ww.code >= 500 {
			globalMetrics.errorTotal.Add(1)
		}
		if ww.code == http.StatusUnauthorized {
			globalMetrics.authFails.Add(1)
		}
	})
}

type statusRecorder struct {
	http.ResponseWriter
	code int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.code = code
	s.ResponseWriter.WriteHeader(code)
}

// handleMetrics 输出 prom textfmt（可被 Prometheus / Datadog 抓）。
func handleMetrics(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		stats := d.Store.DB.Stats()
		var ms runtime.MemStats
		runtime.ReadMemStats(&ms)
		now := time.Now().Unix()
		_, _ = fmt.Fprintf(w, "# HELP finme_uptime_seconds Process uptime in seconds.\n")
		_, _ = fmt.Fprintf(w, "# TYPE finme_uptime_seconds gauge\n")
		_, _ = fmt.Fprintf(w, "finme_uptime_seconds %d\n", now-globalMetrics.startedAt)
		_, _ = fmt.Fprintf(w, "# HELP finme_http_requests_total Total HTTP requests served.\n")
		_, _ = fmt.Fprintf(w, "# TYPE finme_http_requests_total counter\n")
		_, _ = fmt.Fprintf(w, "finme_http_requests_total %d\n", globalMetrics.requestTotal.Load())
		_, _ = fmt.Fprintf(w, "# HELP finme_http_errors_total Total 5xx responses.\n")
		_, _ = fmt.Fprintf(w, "# TYPE finme_http_errors_total counter\n")
		_, _ = fmt.Fprintf(w, "finme_http_errors_total %d\n", globalMetrics.errorTotal.Load())
		_, _ = fmt.Fprintf(w, "# HELP finme_auth_failures_total Total 401 responses.\n")
		_, _ = fmt.Fprintf(w, "# TYPE finme_auth_failures_total counter\n")
		_, _ = fmt.Fprintf(w, "finme_auth_failures_total %d\n", globalMetrics.authFails.Load())
		_, _ = fmt.Fprintf(w, "# HELP finme_db_open_connections Current open SQL connections.\n")
		_, _ = fmt.Fprintf(w, "# TYPE finme_db_open_connections gauge\n")
		_, _ = fmt.Fprintf(w, "finme_db_open_connections %d\n", stats.OpenConnections)
		_, _ = fmt.Fprintf(w, "# HELP finme_db_in_use Current in-use SQL connections.\n")
		_, _ = fmt.Fprintf(w, "# TYPE finme_db_in_use gauge\n")
		_, _ = fmt.Fprintf(w, "finme_db_in_use %d\n", stats.InUse)
		_, _ = fmt.Fprintf(w, "# HELP finme_db_wait_count Total connection waits.\n")
		_, _ = fmt.Fprintf(w, "# TYPE finme_db_wait_count counter\n")
		_, _ = fmt.Fprintf(w, "finme_db_wait_count %d\n", stats.WaitCount)
		_, _ = fmt.Fprintf(w, "# HELP finme_go_goroutines Current goroutines.\n")
		_, _ = fmt.Fprintf(w, "# TYPE finme_go_goroutines gauge\n")
		_, _ = fmt.Fprintf(w, "finme_go_goroutines %d\n", runtime.NumGoroutine())
		_, _ = fmt.Fprintf(w, "# HELP finme_go_memory_alloc_bytes Heap alloc.\n")
		_, _ = fmt.Fprintf(w, "# TYPE finme_go_memory_alloc_bytes gauge\n")
		_, _ = fmt.Fprintf(w, "finme_go_memory_alloc_bytes %d\n", ms.Alloc)
	}
}
