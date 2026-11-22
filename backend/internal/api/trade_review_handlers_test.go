package api

import (
	"fmt"
	"net/http"
	"testing"

	"github.com/sencloud/finme-backend/internal/trade_review"
)

func TestTradeReviewEndpointsRequireAuth(t *testing.T) {
	e := newTestEnv(t)
	for _, c := range []struct{ method, path string }{
		{http.MethodGet, "/v1/trade-reviews"},
		{http.MethodPost, "/v1/trade-reviews/analyze"},
		{http.MethodPut, "/v1/trade-reviews/review-1"},
		{http.MethodDelete, "/v1/trade-reviews/review-1"},
		{http.MethodPost, "/v1/portfolio/parse-trades"},
	} {
		rec, _ := e.do(t, c.method, c.path, "", map[string]any{})
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s %s = %d, want 401", c.method, c.path, rec.Code)
		}
	}
}

func TestTradeReviewAccountIsolation(t *testing.T) {
	e := newTestEnv(t)
	_, owner := e.user(t, 0)
	_, stranger := e.user(t, 0)
	body := map[string]any{"report": map[string]any{
		"id":         "review-1",
		"created_at": "2026-11-22T03:00:00Z",
		"title":      "11月20日 · 3 笔成交",
		"metrics":    map[string]any{"realized_pnl": 136.5},
	}}

	rec, out := e.do(t, http.MethodPut, "/v1/trade-reviews/review-1", owner, body)
	if rec.Code != http.StatusOK {
		t.Fatalf("save = %d %s", rec.Code, rec.Body.String())
	}
	if out["id"] != "review-1" {
		t.Fatalf("save body = %v", out)
	}

	rec, out = e.do(t, http.MethodGet, "/v1/trade-reviews", owner, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("owner list = %d %s", rec.Code, rec.Body.String())
	}
	if reports, _ := out["reports"].([]any); len(reports) != 1 {
		t.Fatalf("owner reports = %v", out["reports"])
	}

	rec, out = e.do(t, http.MethodGet, "/v1/trade-reviews", stranger, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("stranger list = %d %s", rec.Code, rec.Body.String())
	}
	if reports, _ := out["reports"].([]any); len(reports) != 0 {
		t.Fatalf("stranger saw reports = %v", reports)
	}

	rec, _ = e.do(t, http.MethodDelete, "/v1/trade-reviews/review-1", stranger, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("stranger delete = %d, want 404", rec.Code)
	}
	rec, out = e.do(t, http.MethodGet, "/v1/trade-reviews", owner, nil)
	if reports, _ := out["reports"].([]any); rec.Code != http.StatusOK || len(reports) != 1 {
		t.Fatalf("owner report disappeared: %d %v", rec.Code, out)
	}

	rec, _ = e.do(t, http.MethodDelete, "/v1/trade-reviews/review-1", owner, nil)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("owner delete = %d", rec.Code)
	}
}

func TestTradeReviewAnalyzeEndpoint(t *testing.T) {
	e := newTestEnv(t)
	_, token := e.user(t, 0)
	rec, out := e.do(t, http.MethodPost, "/v1/trade-reviews/analyze", token, map[string]any{
		"currency": "CNY",
		"trades": []map[string]any{
			{"source_index": 0, "trade_date": "2026-11-20", "trade_time": "09:30:00", "symbol": "600000", "name": "浦发银行", "side": "buy", "quantity": 100, "price": 10, "fee": 5},
			{"source_index": 1, "trade_date": "2026-11-21", "trade_time": "10:00:00", "symbol": "600000", "name": "浦发银行", "side": "sell", "quantity": 100, "price": 12, "fee": 6},
		},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("analyze = %d %s", rec.Code, rec.Body.String())
	}
	report, _ := out["report"].(map[string]any)
	metrics, _ := report["metrics"].(map[string]any)
	if metrics["matched_sell_count"] != float64(1) {
		t.Fatalf("report = %v", out)
	}
}

func TestTradeReviewKeepsOnlyLatestTwentyReports(t *testing.T) {
	e := newTestEnv(t)
	_, token := e.user(t, 0)
	for i := 0; i < trade_review.MaxReportsPerAccount+3; i++ {
		id := fmt.Sprintf("review-%02d", i)
		rec, _ := e.do(t, http.MethodPut, "/v1/trade-reviews/"+id, token, map[string]any{
			"report": map[string]any{
				"id":         id,
				"created_at": fmt.Sprintf("2026-11-%02dT03:00:00Z", i+1),
				"title":      id,
				"metrics":    map[string]any{},
			},
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("save %s = %d %s", id, rec.Code, rec.Body.String())
		}
	}

	rec, out := e.do(t, http.MethodGet, "/v1/trade-reviews", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("list = %d %s", rec.Code, rec.Body.String())
	}
	reports, _ := out["reports"].([]any)
	if len(reports) != trade_review.MaxReportsPerAccount {
		t.Fatalf("reports = %d, want %d", len(reports), trade_review.MaxReportsPerAccount)
	}
	last, _ := reports[len(reports)-1].(map[string]any)
	if last["id"] != "review-03" {
		t.Fatalf("oldest kept report = %v, want review-03", last["id"])
	}
}
