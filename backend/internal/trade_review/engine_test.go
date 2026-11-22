package trade_review

import (
	"math"
	"strings"
	"testing"
	"time"
)

func TestAnalyzeFIFOWithFeesAndOpenLot(t *testing.T) {
	now := time.Date(2026, 11, 22, 11, 0, 0, 0, time.Local)
	report := Analyze(AnalyzeInput{
		Trades: []Trade{
			{SourceIndex: 0, TradeDate: "2026-11-20", TradeTime: "09:30:00", Symbol: "600000", Name: "浦发银行", Side: "buy", Quantity: 100, Price: 10, Fee: 5},
			{SourceIndex: 1, TradeDate: "2026-11-20", TradeTime: "10:00:00", Symbol: "600000", Name: "浦发银行", Side: "buy", Quantity: 100, Price: 12, Fee: 5},
			{SourceIndex: 2, TradeDate: "2026-11-21", TradeTime: "14:00:00", Symbol: "600000", Name: "浦发银行", Side: "sell", Quantity: 150, Price: 15, Fee: 6},
		},
		Currency: "CNY",
	}, now)

	if len(report.Trades) != 3 {
		t.Fatalf("valid trades = %d, want 3", len(report.Trades))
	}
	if closeEnough(report.Metrics.RealizedPnl, 636.5) {
		// Expected.
	} else {
		t.Fatalf("realized pnl = %.4f, want 636.5", report.Metrics.RealizedPnl)
	}
	if report.Metrics.MatchedSellCount != 1 {
		t.Fatalf("matched sells = %d, want 1", report.Metrics.MatchedSellCount)
	}
	if report.Metrics.TotalFees != 16 {
		t.Fatalf("fees = %.2f, want 16", report.Metrics.TotalFees)
	}
	if report.Metrics.OpenLotCount != 1 {
		t.Fatalf("open lots = %d, want 1", report.Metrics.OpenLotCount)
	}
}

func TestAnalyzeDoesNotCountUnmatchedSell(t *testing.T) {
	report := Analyze(AnalyzeInput{Trades: []Trade{
		{SourceIndex: 0, TradeDate: "2026-11-20", Symbol: "000001", Name: "平安银行", Side: "sell", Quantity: 100, Price: 12},
	}}, time.Date(2026, 11, 22, 11, 0, 0, 0, time.Local))

	if report.Metrics.RealizedPnl != 0 || report.Metrics.MatchedSellCount != 0 {
		t.Fatalf("orphan sell counted: %+v", report.Metrics)
	}
	if !containsText(report.Warnings, "无法与截图中的买入配对") {
		t.Fatalf("missing unmatched warning: %v", report.Warnings)
	}
}

func TestAnalyzeKeepsSymbolsSeparate(t *testing.T) {
	report := Analyze(AnalyzeInput{Trades: []Trade{
		{SourceIndex: 0, TradeDate: "2026-11-20", TradeTime: "09:30:00", Symbol: "600000", Side: "buy", Quantity: 100, Price: 10},
		{SourceIndex: 1, TradeDate: "2026-11-20", TradeTime: "09:31:00", Symbol: "000001", Side: "buy", Quantity: 100, Price: 20},
		{SourceIndex: 2, TradeDate: "2026-11-21", TradeTime: "10:00:00", Symbol: "600000", Side: "sell", Quantity: 100, Price: 11},
		{SourceIndex: 3, TradeDate: "2026-11-21", TradeTime: "10:01:00", Symbol: "000001", Side: "sell", Quantity: 100, Price: 18},
	}}, time.Date(2026, 11, 22, 11, 0, 0, 0, time.Local))

	if !closeEnough(report.Metrics.RealizedPnl, -100) {
		t.Fatalf("realized pnl = %.2f, want -100", report.Metrics.RealizedPnl)
	}
	if report.Metrics.WinningSellCount != 1 || report.Metrics.LosingSellCount != 1 {
		t.Fatalf("outcomes = %d win / %d loss", report.Metrics.WinningSellCount, report.Metrics.LosingSellCount)
	}
	if report.Metrics.OpenLotCount != 0 {
		t.Fatalf("open lots = %d, want 0", report.Metrics.OpenLotCount)
	}
}

func closeEnough(got, want float64) bool {
	return math.Abs(got-want) < 0.001
}

func containsText(values []string, want string) bool {
	for _, value := range values {
		if strings.Contains(value, want) {
			return true
		}
	}
	return false
}
