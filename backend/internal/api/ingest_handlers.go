package api

import (
	"crypto/subtle"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/ingest"
	"github.com/sencloud/finme-backend/internal/platform"
)

// maxIngestBodyBytes 采集端一次推送最多 500 条行情，1MB 足够。
const maxIngestBodyBytes = 1 << 20

var errIngestDisabled = errors.New("ingest endpoint disabled (ingest.key 未配置)")

// mountIngest 挂载「本机采集端」推送入口。
//
// 鉴权用 X-Ingest-Key（配置文件里的 ingest.key），不走用户 JWT——
// 调用方是运维自己的采集进程，不是 App 用户。
func mountIngest(r chi.Router, d *Deps) {
	r.Post("/ingest/quotes", handleIngestQuotes(d))
}

func handleIngestQuotes(d *Deps) http.HandlerFunc {
	type reqBody struct {
		Quotes []ingest.Quote `json:"quotes"`
		Source string         `json:"source,omitempty"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		key := d.Config.Ingest.Key
		if key == "" {
			WriteError(w, r, platform.ErrUnavailable("INGEST.DISABLED",
				errIngestDisabled))
			return
		}
		got := r.Header.Get("X-Ingest-Key")
		if subtle.ConstantTimeCompare([]byte(got), []byte(key)) != 1 {
			WriteError(w, r, platform.ErrUnauthorized("INGEST.FORBIDDEN", "采集密钥不正确"))
			return
		}
		if d.Ingest == nil {
			WriteError(w, r, platform.ErrUnavailable("INGEST.DISABLED",
				errIngestDisabled))
			return
		}
		var body reqBody
		if err := decodeJSONLarge(r, &body, maxIngestBodyBytes); err != nil {
			WriteError(w, r, err)
			return
		}
		n := d.Ingest.Put(body.Quotes)
		total, latest := d.Ingest.Stats()
		platform.LoggerFrom(r.Context()).Debug().
			Int("accepted", n).Int("cached", total).Str("source", body.Source).
			Msg("ingest: quotes received")
		WriteJSON(w, http.StatusOK, map[string]any{
			"accepted": n,
			"cached":   total,
			"latest":   latest.UnixMilli(),
		})
	}
}
