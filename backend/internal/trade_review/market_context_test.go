package trade_review

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/calendar"
	"github.com/sencloud/finme-backend/internal/ai/cnnews"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

func TestMarketContextMergesVerifiablePerspectivesAndFiltersNewsWindow(t *testing.T) {
	report := Analyze(AnalyzeInput{
		Currency: "CNY",
		Trades: []Trade{
			{
				SourceIndex: 0,
				TradeDate:   "2026-11-20",
				TradeTime:   "09:30:00",
				Symbol:      "600000",
				Name:        "浦发银行",
				Side:        "buy",
				Quantity:    100,
				Price:       10,
			},
			{
				SourceIndex: 1,
				TradeDate:   "2026-11-21",
				TradeTime:   "10:00:00",
				Symbol:      "600000",
				Name:        "浦发银行",
				Side:        "sell",
				Quantity:    100,
				Price:       11,
			},
		},
	}, time.Date(2026, 11, 22, 11, 0, 0, 0, shanghaiTime))

	domesticInWindow := time.Date(2026, 11, 19, 10, 0, 0, 0, shanghaiTime)
	globalInWindow := time.Date(2026, 11, 21, 20, 30, 0, 0, shanghaiTime)
	outsideWindow := time.Date(2026, 10, 1, 10, 0, 0, 0, shanghaiTime)
	news := &fakeNewsSource{
		domestic: searchResult([]cnnews.Event{
			{
				Source:      "财联社",
				Title:       "央行开展公开市场操作，资金面保持平稳",
				Snippet:     "政策预期与银行板块受到关注",
				PublishedAt: domesticInWindow.UnixMilli(),
			},
			{
				Source:      "窗口外测试源",
				Title:       "窗口外的旧新闻",
				PublishedAt: outsideWindow.UnixMilli(),
			},
		}),
		global: searchResult([]cnnews.Event{
			{
				Source:      "路透中文",
				Title:       "美联储议息预期变化，美元与人民币汇率波动",
				Snippet:     "海外利率和风险偏好受到关注",
				PublishedAt: globalInWindow.UnixMilli(),
			},
		}),
	}
	enricher := NewMarketContextEnricher(
		fakeQuoteSource{},
		fakeCalendarSource{
			events: []calendar.Event{
				{
					Date:   "2026-11-20",
					Time:   "09:15",
					Region: "中国",
					Title:  "贷款市场报价利率",
					Star:   3,
					Actual: "3.0%",
				},
				{
					Date:   "2026-11-21",
					Time:   "20:30",
					Region: "美国",
					Title:  "初请失业金人数",
					Star:   2,
					Actual: "22万",
				},
			},
		},
		news,
	)
	service := NewService(nil, enricher)

	got := service.Analyze(
		context.Background(),
		AnalyzeInput{
			Currency: report.Currency,
			Trades:   report.Trades,
		},
		time.Date(2026, 11, 22, 11, 0, 0, 0, shanghaiTime),
	)

	dimensions := map[string]bool{}
	for _, item := range got.Perspectives {
		dimensions[item.Dimension] = true
	}
	for _, want := range []string{
		"execution",
		"price",
		"domestic",
		"international",
		"hotspots",
	} {
		if !dimensions[want] {
			t.Fatalf("missing perspective %q: %+v", want, got.Perspectives)
		}
	}
	if len(got.MarketContext.Events) == 0 {
		t.Fatal("expected market context events")
	}
	for _, event := range got.MarketContext.Events {
		if strings.Contains(event.Title, "窗口外") {
			t.Fatalf("out-of-window news was attached: %+v", event)
		}
	}
	if len(got.MarketContext.Coverage) != 4 {
		t.Fatalf("coverage rows = %d, want 4", len(got.MarketContext.Coverage))
	}
	if got.Metrics.MatchedSellCount != 1 || !closeEnough(got.Metrics.RealizedPnl, 100) {
		t.Fatalf("fifo metrics changed after enrichment: %+v", got.Metrics)
	}
}

func TestMarketContextSourceFailuresKeepFIFOAnalysisAndExposeGaps(t *testing.T) {
	now := time.Date(2026, 11, 22, 11, 0, 0, 0, shanghaiTime)
	enricher := NewMarketContextEnricher(
		fakeQuoteSource{err: errors.New("quotes unavailable")},
		fakeCalendarSource{err: errors.New("calendar unavailable")},
		&fakeNewsSource{
			domestic: &cnnews.Result{
				Sources: []cnnews.SourceStatus{
					{Name: "财联社", OK: false, Error: "timeout"},
				},
			},
			global: &cnnews.Result{
				Sources: []cnnews.SourceStatus{
					{Name: "路透中文", OK: false, Error: "timeout"},
				},
			},
		},
	)
	service := NewService(nil, enricher)
	got := service.Analyze(
		context.Background(),
		AnalyzeInput{
			Trades: []Trade{
				{
					SourceIndex: 0,
					TradeDate:   "2026-11-20",
					TradeTime:   "09:30:00",
					Symbol:      "600000",
					Name:        "浦发银行",
					Side:        "buy",
					Quantity:    100,
					Price:       10,
				},
				{
					SourceIndex: 1,
					TradeDate:   "2026-11-21",
					TradeTime:   "10:00:00",
					Symbol:      "600000",
					Name:        "浦发银行",
					Side:        "sell",
					Quantity:    100,
					Price:       9,
				},
			},
		},
		now,
	)

	if got.Metrics.MatchedSellCount != 1 || !closeEnough(got.Metrics.RealizedPnl, -100) {
		t.Fatalf("fifo metrics were lost: %+v", got.Metrics)
	}
	for _, item := range got.MarketContext.Coverage {
		if item.Source != "标的与大盘行情" && item.Status != "error" {
			t.Fatalf("source failure was hidden: %+v", item)
		}
	}
	if len(got.MarketContext.Gaps) == 0 {
		t.Fatal("expected explicit data gaps")
	}
	missing := 0
	for _, item := range got.Perspectives {
		if item.Basis == "数据缺口" {
			missing++
		}
	}
	if missing < 4 {
		t.Fatalf("data-gap perspectives = %d, want at least 4: %+v", missing, got.Perspectives)
	}
}

type fakeQuoteSource struct {
	err error
}

func (f fakeQuoteSource) HistoryFor(
	ctx context.Context,
	symbol string,
	start, end time.Time,
) ([]tushare.Candle, error) {
	if f.err != nil {
		return nil, f.err
	}
	if symbol == "600000.SH" {
		return []tushare.Candle{
			{
				TradeDate: "20261120",
				Open:      9.8,
				High:      10.2,
				Low:       9.7,
				Close:     10.1,
				PreClose:  9.8,
				PctChg:    3.06,
			},
			{
				TradeDate: "20261121",
				Open:      10.2,
				High:      11.2,
				Low:       10,
				Close:     11,
				PreClose:  10.1,
				PctChg:    8.91,
			},
		}, nil
	}
	return []tushare.Candle{
		{
			TradeDate: "20261120",
			Open:      3900,
			High:      3950,
			Low:       3880,
			Close:     3930,
			PreClose:  3890,
			PctChg:    1.03,
		},
		{
			TradeDate: "20261121",
			Open:      3930,
			High:      3980,
			Low:       3910,
			Close:     3960,
			PreClose:  3930,
			PctChg:    0.76,
		},
	}, nil
}

type fakeCalendarSource struct {
	events []calendar.Event
	err    error
}

func (f fakeCalendarSource) FetchEconomicCalendar(
	ctx context.Context,
	startDate, endDate string,
) ([]calendar.Event, error) {
	return f.events, f.err
}

type fakeNewsSource struct {
	domestic *cnnews.Result
	global   *cnnews.Result
}

func (f *fakeNewsSource) SearchAllResult(
	ctx context.Context,
	opt cnnews.SearchOptions,
) *cnnews.Result {
	return f.domestic
}

func (f *fakeNewsSource) SearchGlobalResult(
	ctx context.Context,
	opt cnnews.GlobalSearchOptions,
) *cnnews.Result {
	return f.global
}

func searchResult(events []cnnews.Event) *cnnews.Result {
	return &cnnews.Result{
		Events: events,
		Sources: []cnnews.SourceStatus{
			{Name: "测试源", OK: true, Count: len(events)},
		},
	}
}
