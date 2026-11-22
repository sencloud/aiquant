package qwen

import "testing"

func TestNormalizeTradeRows(t *testing.T) {
	rows := []ParsedTrade{
		{
			TradeDate: "2026/11/18",
			TradeTime: "9:35",
			Symbol:    "600519",
			Name:      "贵州茅台",
			Side:      "买入",
			Quantity:  100,
			Price:     1500.5,
			Fee:       5,
		},
		{
			TradeDate: "20261119",
			Symbol:    "600519",
			Name:      "贵州茅台",
			Side:      "SELL",
			Quantity:  100,
			Price:     1510,
			Fee:       -1,
		},
		{
			TradeDate: "bad-date",
			Symbol:    "000001",
			Side:      "buy",
			Quantity:  100,
			Price:     10,
		},
	}
	got, warnings, err := normalizeTradeRows(rows)
	if err != nil {
		t.Fatalf("normalizeTradeRows: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("valid rows = %d, want 2", len(got))
	}
	if got[0].TradeDate != "2026-11-18" || got[0].Side != "buy" {
		t.Fatalf("first row = %+v", got[0])
	}
	if got[1].TradeDate != "2026-11-19" || got[1].Fee != 0 {
		t.Fatalf("second row = %+v", got[1])
	}
	if len(warnings) != 2 {
		t.Fatalf("warnings = %v, want 2", warnings)
	}
}

func TestNormalizeTradeRowsRejectsAllInvalidRows(t *testing.T) {
	rows := []ParsedTrade{{
		TradeDate: "2026-11-18",
		Symbol:    "600519",
		Side:      "unknown",
		Quantity:  100,
		Price:     1500,
	}}
	if _, _, err := normalizeTradeRows(rows); err == nil {
		t.Fatal("expected invalid rows to return an error")
	}
}

func TestNormalizeTradeHelpers(t *testing.T) {
	if got := normalizeTradeSide("卖出"); got != "sell" {
		t.Fatalf("side = %q", got)
	}
	if got := normalizeTradeTime("09:35"); got != "09:35:00" {
		t.Fatalf("time = %q", got)
	}
	if got := normalizeCurrency(""); got != "CNY" {
		t.Fatalf("currency = %q", got)
	}
}
