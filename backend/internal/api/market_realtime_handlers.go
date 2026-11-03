package api

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/ai/realtime"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
	"github.com/sencloud/finme-backend/internal/platform"
)

// MarketQuoteSource is the small realtime surface needed by the public market
// endpoint. Keeping it behind an interface lets the API handler be tested
// without reaching Tencent or Eastmoney.
type MarketQuoteSource interface {
	FetchSnapshot(ctx context.Context, symbol string) (*realtime.Quote, error)
	FetchFuturesSnapshot(ctx context.Context, tsCode string) (*realtime.FuturesQuote, error)
}

type marketQuote struct {
	TsCode     string  `json:"ts_code"`
	Name       string  `json:"name"`
	AssetClass string  `json:"asset_class"`
	Exchange   string  `json:"exchange,omitempty"`
	Last       float64 `json:"last"`
	PctChg     float64 `json:"pct_chg"`
	Change     float64 `json:"change"`
	Open       float64 `json:"open"`
	High       float64 `json:"high"`
	Low        float64 `json:"low"`
	PreClose   float64 `json:"pre_close"`
	PreSettle  float64 `json:"pre_settle,omitempty"`
	Volume     int64   `json:"volume"`
	Amount     float64 `json:"amount"`
	OI         int64   `json:"oi,omitempty"`
	Bid        float64 `json:"bid,omitempty"`
	Ask        float64 `json:"ask,omitempty"`
	Delayed    bool    `json:"delayed"`
	Source     string  `json:"source"`
	// AsOf is when the backend obtained this snapshot (unix ms).
	AsOf int64 `json:"as_of"`
	// QuoteTime is the upstream quote timestamp when the provider exposes one
	// (unix ms). It is intentionally separate from AsOf so a delayed provider
	// cannot make stale prices look current.
	QuoteTime int64 `json:"quote_time,omitempty"`
}

type marketQuoteEnvelope struct {
	Quote      marketQuote `json:"quote"`
	AssetClass string      `json:"asset_class"`
	AsOf       int64       `json:"as_of"`
}

// mountMarketRealtimePublic exposes read-only, non-user market data. It does
// not require authentication and is safe to poll from the iOS market screen.
func mountMarketRealtimePublic(r chi.Router, d *Deps) {
	r.Get("/market/quote", handleMarketRealtimeQuote(d))
}

func handleMarketRealtimeQuote(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		tsCode := tushare.NormalizeSymbol(r.URL.Query().Get("ts_code"))
		if tsCode == "" || !isSupportedMarketCode(tsCode) {
			WriteError(w, r, platform.ErrBadRequest(
				"MARKET.INVALID_TS_CODE",
				"ts_code 必须是股票、指数或期货代码，例如 600519.SH、P2701.DCE",
				nil,
			))
			return
		}

		now := time.Now()
		// The local collector carries the only true intraday futures tick in
		// production. Only use an exact contract match here: applying a main
		// continuous quote to a different delivery month would be misleading.
		if d.Ingest != nil {
			if entry, ok := d.Ingest.Get(tsCode, ingestMaxAge(d)); ok &&
				entry.Quote.Last > 0 {
				q := entry.Quote
				quoteTime := q.Ts
				if quoteTime <= 0 {
					quoteTime = entry.ReceivedAt.UnixMilli()
				}
				payload := marketQuote{
					TsCode:     tsCode,
					Name:       q.Name,
					AssetClass: assetClassForMarketCode(tsCode),
					Exchange:   tushare.ExchangeOf(tsCode),
					Last:       q.Last,
					PctChg:     q.PctChg,
					Change:     q.Change,
					Open:       q.Open,
					High:       q.High,
					Low:        q.Low,
					PreClose:   q.PreClose,
					Volume:     int64(q.Volume),
					OI:         int64(q.OI),
					Delayed:    false,
					Source:     "local_agent",
					AsOf:       now.UnixMilli(),
					QuoteTime:  quoteTime,
				}
				writeMarketQuote(w, payload)
				return
			}
		}

		if d.Realtime == nil {
			WriteError(w, r, platform.ErrUnavailable(
				"MARKET.REALTIME_DISABLED",
				errors.New("market realtime source is not configured"),
			))
			return
		}

		if tushare.IsFuture(tsCode) {
			q, err := d.Realtime.FetchFuturesSnapshot(r.Context(), tsCode)
			if err != nil {
				writeMarketQuoteError(w, r, err)
				return
			}
			if q == nil {
				writeMarketQuoteError(w, r, errors.New("empty futures quote"))
				return
			}
			writeMarketQuote(w, marketQuote{
				TsCode:     firstNonEmpty(q.TsCode, tsCode),
				Name:       q.Name,
				AssetClass: "future",
				Exchange:   q.Exchange,
				Last:       q.Last,
				PctChg:     q.PctChg,
				Change:     q.Change,
				Open:       q.Open,
				High:       q.High,
				Low:        q.Low,
				PreClose:   q.PreClose,
				PreSettle:  q.PreSettle,
				Volume:     q.Volume,
				Amount:     q.Amount,
				OI:         q.OI,
				Bid:        q.Bid,
				Ask:        q.Ask,
				// push2delay is a delayed feed regardless of f1. Mark it
				// explicitly so the app never presents it as exchange tick data.
				Delayed:   true,
				Source:    "eastmoney_delay",
				AsOf:      now.UnixMilli(),
				QuoteTime: unixSecondsToMillis(q.AsOf),
			})
			return
		}

		q, err := d.Realtime.FetchSnapshot(r.Context(), tsCode)
		if err != nil {
			writeMarketQuoteError(w, r, err)
			return
		}
		if q == nil {
			writeMarketQuoteError(w, r, errors.New("empty stock quote"))
			return
		}
		writeMarketQuote(w, marketQuote{
			TsCode:     firstNonEmpty(q.TsCode, tsCode),
			Name:       q.Name,
			AssetClass: assetClassForMarketCode(tsCode),
			Last:       q.Last,
			PctChg:     q.PctChg,
			Change:     q.Change,
			Open:       q.Open,
			High:       q.High,
			Low:        q.Low,
			PreClose:   q.PreClose,
			Volume:     q.Volume,
			Amount:     q.Amount,
			Delayed:    q.Delayed,
			Source:     "tencent_qt",
			AsOf:       now.UnixMilli(),
			QuoteTime:  unixSecondsToMillis(q.AsOf),
		})
	}
}

func writeMarketQuote(w http.ResponseWriter, q marketQuote) {
	w.Header().Set("Cache-Control", "no-store")
	WriteJSON(w, http.StatusOK, marketQuoteEnvelope{
		Quote:      q,
		AssetClass: q.AssetClass,
		AsOf:       q.AsOf,
	})
}

func writeMarketQuoteError(w http.ResponseWriter, r *http.Request, err error) {
	WriteError(w, r, platform.NewAPIError(
		http.StatusBadGateway,
		"MARKET.REALTIME_UPSTREAM",
		"实时行情暂时不可用",
		err,
	))
}

func isSupportedMarketCode(code string) bool {
	return tushare.IsStock(code) || tushare.IsFuture(code)
}

func assetClassForMarketCode(code string) string {
	switch {
	case tushare.IsFuture(code):
		return "future"
	case tushare.IsIndex(code):
		return "index"
	default:
		return "stock"
	}
}

func ingestMaxAge(d *Deps) time.Duration {
	if d == nil || d.Config == nil || d.Config.Ingest.MaxAgeSec <= 0 {
		return 2 * time.Minute
	}
	return time.Duration(d.Config.Ingest.MaxAgeSec) * time.Second
}

func unixSecondsToMillis(sec int64) int64 {
	if sec <= 0 {
		return 0
	}
	return sec * 1000
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
