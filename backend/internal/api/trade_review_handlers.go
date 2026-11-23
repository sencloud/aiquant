package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/trade_review"
)

const maxTradeReportBytes = 512 * 1024

func mountTradeReview(r chi.Router, d *Deps) {
	r.Get("/trade-reviews", handleListTradeReviews(d))
	r.Post("/trade-reviews/analyze", handleAnalyzeTradeReview(d))
	r.Put("/trade-reviews/{id}", handleSaveTradeReview(d))
	r.Delete("/trade-reviews/{id}", handleDeleteTradeReview(d))
}

func handleListTradeReviews(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user := MustUser(r)
		reports, err := d.TradeReviews.List(r.Context(), user.UserID)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("TRADE_REVIEW.LIST_FAILED", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"reports": reports})
	}
}

func handleSaveTradeReview(d *Deps) http.HandlerFunc {
	type reqBody struct {
		Report json.RawMessage `json:"report"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		user := MustUser(r)
		id := strings.TrimSpace(chi.URLParam(r, "id"))
		if id == "" || len(id) > 160 {
			WriteError(w, r, platform.ErrBadRequest(
				"TRADE_REVIEW.INVALID_ID", "复盘编号无效", nil))
			return
		}
		var body reqBody
		if err := decodeJSONLarge(r, &body, maxTradeReportBytes); err != nil {
			WriteError(w, r, err)
			return
		}
		createdAt, err := validateTradeReport(body.Report, id)
		if err != nil {
			WriteError(w, r, platform.ErrBadRequest(
				"TRADE_REVIEW.INVALID_REPORT", err.Error(), err))
			return
		}
		if err := d.TradeReviews.Save(
			r.Context(), user.UserID, id, body.Report, createdAt,
		); err != nil {
			WriteError(w, r, platform.ErrInternal("TRADE_REVIEW.SAVE_FAILED", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"id":         id,
			"created_at": createdAt.UTC().Format(time.RFC3339Nano),
		})
	}
}

func handleDeleteTradeReview(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user := MustUser(r)
		id := strings.TrimSpace(chi.URLParam(r, "id"))
		err := d.TradeReviews.Delete(r.Context(), user.UserID, id)
		if errors.Is(err, sql.ErrNoRows) {
			WriteError(w, r, platform.ErrNotFound(
				"TRADE_REVIEW.NOT_FOUND", "没有找到这份复盘"))
			return
		}
		if err != nil {
			WriteError(w, r, platform.ErrInternal("TRADE_REVIEW.DELETE_FAILED", err))
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleAnalyzeTradeReview(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		_ = MustUser(r)
		var body trade_review.AnalyzeInput
		if err := decodeJSONLarge(r, &body, 1024*1024); err != nil {
			WriteError(w, r, err)
			return
		}
		if len(body.Trades) == 0 {
			WriteError(w, r, platform.ErrBadRequest(
				"TRADE_REVIEW.NO_TRADES", "没有可分析的成交行", nil))
			return
		}
		if len(body.Trades) > 500 {
			WriteError(w, r, platform.ErrBadRequest(
				"TRADE_REVIEW.TOO_MANY_TRADES", "一次最多分析 500 笔成交", nil))
			return
		}
		report := d.TradeReviews.Analyze(r.Context(), body, time.Now())
		WriteJSON(w, http.StatusOK, map[string]any{"report": report})
	}
}

func validateTradeReport(raw json.RawMessage, expectedID string) (time.Time, error) {
	if len(raw) == 0 || string(raw) == "null" {
		return time.Time{}, errors.New("缺少复盘内容")
	}
	var report map[string]json.RawMessage
	if err := json.Unmarshal(raw, &report); err != nil {
		return time.Time{}, errors.New("复盘内容不是合法 JSON 对象")
	}
	var id string
	if err := json.Unmarshal(report["id"], &id); err != nil || id != expectedID {
		return time.Time{}, errors.New("复盘编号与请求不一致")
	}
	var created string
	if err := json.Unmarshal(report["created_at"], &created); err != nil {
		return time.Time{}, errors.New("复盘创建时间无效")
	}
	parsed, err := time.Parse(time.RFC3339Nano, created)
	if err != nil {
		return time.Time{}, errors.New("复盘创建时间格式无效")
	}
	var metrics map[string]json.RawMessage
	if err := json.Unmarshal(report["metrics"], &metrics); err != nil {
		return time.Time{}, errors.New("复盘指标无效")
	}
	return parsed, nil
}
