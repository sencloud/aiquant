package api

import (
	"context"
	"errors"
	"net/http"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/realtime"
	"github.com/sencloud/finme-backend/internal/ingest"
)

type fakeMarketQuoteSource struct {
	stock  *realtime.Quote
	future *realtime.FuturesQuote
	err    error
}

func (f fakeMarketQuoteSource) FetchSnapshot(
	_ context.Context,
	_ string,
) (*realtime.Quote, error) {
	return f.stock, f.err
}

func (f fakeMarketQuoteSource) FetchFuturesSnapshot(
	_ context.Context,
	_ string,
) (*realtime.FuturesQuote, error) {
	return f.future, f.err
}

func TestMarketRealtimeQuoteRoutesByAssetClass(t *testing.T) {
	e := newTestEnvWith(t, func(d *Deps) {
		d.Realtime = fakeMarketQuoteSource{
			stock: &realtime.Quote{
				TsCode:   "600519.SH",
				Name:     "贵州茅台",
				Last:     1500.5,
				Open:     1490,
				High:     1510,
				Low:      1488,
				PreClose: 1488,
				Volume:   12000,
				AsOf:     time.Now().Unix(),
			},
			future: &realtime.FuturesQuote{
				TsCode:    "P2701.DCE",
				Name:      "棕榈油2701",
				Exchange:  "DCE",
				Last:      9261,
				Open:      9271,
				High:      9299,
				Low:       9195,
				PreSettle: 9310,
				Volume:    281628,
				OI:        142691,
				AsOf:      time.Now().Unix(),
			},
		}
	})

	rec, out := e.do(t, http.MethodGet,
		"/v1/market/quote?ts_code=600519.SH", "", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("stock quote %d: %s", rec.Code, rec.Body.String())
	}
	quote, _ := out["quote"].(map[string]any)
	if quote["asset_class"] != "stock" || quote["last"] != 1500.5 ||
		quote["source"] != "tencent_qt" {
		t.Fatalf("stock quote body %v", out)
	}

	rec, out = e.do(t, http.MethodGet,
		"/v1/market/quote?ts_code=P2701.DCE", "", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("future quote %d: %s", rec.Code, rec.Body.String())
	}
	quote, _ = out["quote"].(map[string]any)
	if quote["asset_class"] != "future" || quote["oi"] != float64(142691) ||
		quote["delayed"] != true {
		t.Fatalf("future quote body %v", out)
	}
}

func TestMarketRealtimeQuoteValidationAndFailures(t *testing.T) {
	e := newTestEnvWith(t, func(d *Deps) {
		d.Realtime = fakeMarketQuoteSource{err: errors.New("upstream unavailable")}
	})
	for _, path := range []string{
		"/v1/market/quote",
		"/v1/market/quote?ts_code=not-a-market-code",
		"/v1/market/quote?ts_code=P2701.UNKNOWN",
	} {
		if rec, _ := e.do(t, http.MethodGet, path, "", nil); rec.Code != http.StatusBadRequest {
			t.Fatalf("%s = %d, want 400", path, rec.Code)
		}
	}

	rec, _ := e.do(t, http.MethodGet,
		"/v1/market/quote?ts_code=600519.SH", "", nil)
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("upstream error = %d, want 502", rec.Code)
	}

	disabled := newTestEnvWith(t, func(d *Deps) { d.Realtime = nil })
	rec, _ = disabled.do(t, http.MethodGet,
		"/v1/market/quote?ts_code=600519.SH", "", nil)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("nil realtime = %d, want 503", rec.Code)
	}
}

func TestMarketRealtimeQuotePrefersExactLocalAgentContract(t *testing.T) {
	e := newTestEnvWith(t, func(d *Deps) {
		reg := ingest.NewRegistry(nil)
		reg.Put([]ingest.Quote{{
			Symbol:   "P2701.DCE",
			Name:     "棕榈油2701",
			Last:     9238,
			PctChg:   -0.3,
			Open:     9271,
			High:     9299,
			Low:      9195,
			PreClose: 9298,
			Volume:   281999,
			OI:       142700,
			Ts:       time.Now().UnixMilli(),
		}})
		d.Ingest = reg
		d.Realtime = fakeMarketQuoteSource{err: errors.New("must not call upstream")}
	})

	rec, out := e.do(t, http.MethodGet,
		"/v1/market/quote?ts_code=P2701.DCE", "", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("local quote %d: %s", rec.Code, rec.Body.String())
	}
	quote, _ := out["quote"].(map[string]any)
	if quote["source"] != "local_agent" || quote["last"] != float64(9238) ||
		quote["quote_time"] == nil {
		t.Fatalf("local quote body %v", out)
	}
}
