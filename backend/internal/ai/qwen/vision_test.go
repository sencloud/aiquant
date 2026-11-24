package qwen

import (
	"errors"
	"testing"
)

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
	_, _, err := normalizeTradeRows(rows)
	if err == nil {
		t.Fatal("expected invalid rows to return an error")
	}
	// 有行但一行都没通过：必须是可区分的 RejectedRowsError，客户端才能提示
	// 重传，而不是当成空白页悄悄丢数据。
	var rejected *RejectedRowsError
	if !errors.As(err, &rejected) {
		t.Fatalf("error = %T %v, want *RejectedRowsError", err, err)
	}
	if rejected.Total != 1 || len(rejected.Reasons) != 1 {
		t.Fatalf("rejected = %+v", rejected)
	}
}

func TestNormalizeTradeRowsEmptyPageIsNotAnError(t *testing.T) {
	// 模型这一页什么都没返回：这是成功的空页（重叠/空白），不是失败。
	got, warnings, err := normalizeTradeRows(nil)
	if err != nil {
		t.Fatalf("normalizeTradeRows(nil): %v", err)
	}
	if len(got) != 0 || len(warnings) != 0 {
		t.Fatalf("got = %v warnings = %v", got, warnings)
	}
}

func TestApplyFallbackInstrument(t *testing.T) {
	rows := []ParsedTrade{
		{TradeDate: "2026-10-23", Side: "sell", Quantity: 2300, Price: 4.364},
		{TradeDate: "2026-10-22", Side: "buy", Quantity: 2400, Price: 4.306},
		{
			TradeDate: "2026-10-30",
			Symbol:    "000001",
			Name:      "平安银行",
			Side:      "buy",
			Quantity:  100,
			Price:     10,
		},
	}
	filled := applyFallbackInstrument(rows, TradeInstrument{Symbol: "159919", Name: "沪深300ETF嘉实"})
	if filled != 2 {
		t.Fatalf("filled = %d, want 2", filled)
	}
	if rows[0].Symbol != "159919" || rows[0].Name != "沪深300ETF嘉实" {
		t.Fatalf("row 0 = %+v", rows[0])
	}
	// 模型自己认出来的标的不覆盖。
	if rows[2].Symbol != "000001" || rows[2].Name != "平安银行" {
		t.Fatalf("row 2 = %+v", rows[2])
	}

	// 没有可补的标的时一行都不动。
	before := rows[0]
	if n := applyFallbackInstrument(rows, TradeInstrument{}); n != 0 {
		t.Fatalf("empty fallback filled %d rows", n)
	}
	if rows[0] != before {
		t.Fatalf("row 0 changed with empty fallback: %+v", rows[0])
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
