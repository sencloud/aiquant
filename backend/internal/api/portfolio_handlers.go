package api

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/platform"
)

// decodeJSONLarge 是 DecodeJSON 的可配额变体；
// 仅当某 endpoint 业务上必须接受大体积 body（截图 base64）时使用。
func decodeJSONLarge(r *http.Request, dst any, maxBytes int64) error {
	r.Body = http.MaxBytesReader(nil, r.Body, maxBytes)
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

// mountPortfolioParse 挂载需要登录的组合辅助路由。
//
// 当前只一个：POST /v1/portfolio/parse-screenshot —— 给客户端上传一张
// 券商持仓截图，返回结构化 holdings JSON 让用户确认后批量导入。
func mountPortfolioParse(r chi.Router, d *Deps) {
	r.Post("/portfolio/parse-screenshot", handleParseHoldingsScreenshot(d))
	r.Post("/portfolio/parse-trades", handleParseTradesScreenshot(d))
}

// handleParseHoldingsScreenshot 调 qwen3-vl-plus 把券商截图解析成 JSON。
//
// 请求体（JSON）：
//
//	{ "image_base64": "...", "mime_type": "image/png" }
//
// 响应：直接把 vision 模型返回的 ParseHoldingsResult 透传，外加 source 标识。
func handleParseHoldingsScreenshot(d *Deps) http.HandlerFunc {
	type reqBody struct {
		ImageBase64 string `json:"image_base64"`
		MimeType    string `json:"mime_type,omitempty"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		_ = MustUser(r)
		if d.Qwen == nil || !d.Qwen.Configured() {
			WriteError(w, r, platform.ErrUnavailable(
				"PORTFOLIO.VISION_UNAVAILABLE",
				errors.New("qwen vision not configured")))
			return
		}

		// 截图 base64 体积大，DecodeJSON 默认 256KB 不够；本接口允许到 8MB。
		var body reqBody
		if err := decodeJSONLarge(r, &body, 8*1024*1024); err != nil {
			WriteError(w, r, err)
			return
		}
		raw := strings.TrimSpace(body.ImageBase64)
		if raw == "" {
			WriteError(w, r, platform.ErrBadRequest(
				"PORTFOLIO.IMAGE_EMPTY", "image_base64 不能为空", nil))
			return
		}
		// 客户端可能发不带 data: 前缀的纯 base64；做一次轻量校验
		// （太大的截图直接拒掉，避免 vision 请求超时空跑费 quota）。
		if !strings.HasPrefix(raw, "data:") {
			if _, err := base64.StdEncoding.DecodeString(raw); err != nil {
				WriteError(w, r, platform.ErrBadRequest(
					"PORTFOLIO.IMAGE_INVALID",
					"image_base64 不是合法 base64", err))
				return
			}
			mime := body.MimeType
			if mime == "" {
				mime = "image/png"
			}
			raw = "data:" + mime + ";base64," + raw
		}

		out, err := d.Qwen.ParseHoldingsFromImage(r.Context(), raw)
		if err != nil {
			WriteError(w, r, platform.ErrInternal(
				"PORTFOLIO.VISION_FAILED", err))
			return
		}
		if len(out.Holdings) == 0 {
			WriteError(w, r, platform.ErrBadRequest(
				"PORTFOLIO.NO_HOLDINGS",
				"未识别到任何持仓行，请换一张更清晰的截图重试", nil))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"source":      "qwen-vl",
			"broker_hint": out.BrokerHint,
			"currency":    out.Currency,
			"holdings":    out.Holdings,
		})
	}
}

func handleParseTradesScreenshot(d *Deps) http.HandlerFunc {
	type reqBody struct {
		ImageBase64 string `json:"image_base64"`
		MimeType    string `json:"mime_type,omitempty"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		_ = MustUser(r)
		if d.Qwen == nil || !d.Qwen.Configured() {
			WriteError(w, r, platform.ErrUnavailable(
				"PORTFOLIO.VISION_UNAVAILABLE",
				errors.New("qwen vision not configured")))
			return
		}

		var body reqBody
		if err := decodeJSONLarge(r, &body, 8*1024*1024); err != nil {
			WriteError(w, r, err)
			return
		}
		raw := strings.TrimSpace(body.ImageBase64)
		if raw == "" {
			WriteError(w, r, platform.ErrBadRequest(
				"PORTFOLIO.IMAGE_EMPTY", "image_base64 不能为空", nil))
			return
		}
		if !strings.HasPrefix(raw, "data:") {
			if _, err := base64.StdEncoding.DecodeString(raw); err != nil {
				WriteError(w, r, platform.ErrBadRequest(
					"PORTFOLIO.IMAGE_INVALID",
					"image_base64 不是合法 base64", err))
				return
			}
			mime := strings.TrimSpace(body.MimeType)
			if !strings.HasPrefix(mime, "image/") {
				mime = "image/png"
			}
			raw = "data:" + mime + ";base64," + raw
		}

		out, err := d.Qwen.ParseTradesFromImage(r.Context(), raw)
		if err != nil {
			message := err.Error()
			if strings.Contains(message, "no valid trade rows") {
				platform.LoggerFrom(r.Context()).Info().
					Str("mime_type", safeVisionMime(body.MimeType)).
					Int("image_base64_chars", len(body.ImageBase64)).
					Bool("no_new_rows", true).
					Msg("trade screenshot contained no new rows")
				// 滚动截图的重叠页、页尾空白或已被上一张覆盖的区域，
				// 视觉模型可能正确返回“没有可确认的成交行”。这是成功的
				// 空页，不应让整批多图导入失败，更不应显示成网络错误。
				WriteJSON(w, http.StatusOK, map[string]any{
					"source":      "qwen-vl",
					"broker_hint": "",
					"currency":    "CNY",
					"trades":      []any{},
					"warnings": []string{
						"本页没有发现新的成交行，可能是两张截图的重叠区域或空白页。",
					},
					"no_new_rows": true,
				})
				return
			}
			platform.LoggerFrom(r.Context()).Warn().
				Err(err).
				Str("mime_type", safeVisionMime(body.MimeType)).
				Int("image_base64_chars", len(body.ImageBase64)).
				Bool("no_new_rows", false).
				Msg("trade screenshot parse failed")
			WriteError(w, r, platform.ErrInternal(
				"PORTFOLIO.VISION_FAILED", err))
			return
		}
		if len(out.Trades) == 0 {
			WriteJSON(w, http.StatusOK, map[string]any{
				"source":      "qwen-vl",
				"broker_hint": out.BrokerHint,
				"currency":    out.Currency,
				"trades":      []any{},
				"warnings": append(out.Warnings,
					"本页没有发现新的成交行，可能是两张截图的重叠区域或空白页。"),
				"no_new_rows": true,
			})
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"source":      "qwen-vl",
			"broker_hint": out.BrokerHint,
			"currency":    out.Currency,
			"trades":      out.Trades,
			"warnings":    out.Warnings,
			"no_new_rows": false,
		})
	}
}

func safeVisionMime(raw string) string {
	mime := strings.ToLower(strings.TrimSpace(raw))
	if len(mime) > 64 || !strings.HasPrefix(mime, "image/") {
		return "unknown"
	}
	return mime
}
