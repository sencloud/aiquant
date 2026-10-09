package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/platform"
)

// 数据源冒烟测试：把所有 AI 工具真跑一遍，看哪些拿不到数据。
//
// 默认跳过（需要外网 + Tushare/新闻源凭据），本地排查数据源时用：
//
//	$env:FINME_SMOKE='1'; go test ./cmd/finme-server -run TestDataSourcesSmoke -v
//
// 工具返回体里的 {"error": ...} 即视为失败——工具层刻意不把错误作为 Go error
// 抛出（要让模型看到原因），所以只能这样判定。
func TestDataSourcesSmoke(t *testing.T) {
	if os.Getenv("FINME_SMOKE") != "1" {
		t.Skip("set FINME_SMOKE=1 to run (needs network + credentials)")
	}
	cfg, err := platform.LoadConfig("")
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	l := zerolog.New(zerolog.ConsoleWriter{Out: os.Stdout, TimeFormat: "15:04:05"}).
		With().Timestamp().Logger()
	reg := buildToolRegistry(cfg, &l)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	// 需要动态参数的工具（主力合约）先取一次，后面复用。
	dominant := map[string]string{}
	for _, p := range []string{"螺纹钢", "铁矿石", "豆粕", "原油", "沪深300股指", "50ETF期权"} {
		out := reg.Dispatch(ctx, "get_dominant_contract",
			fmt.Sprintf(`{"product":%q}`, p))
		// 返回结构是 {"dominant": {"ts_code": ...}, "all_contracts": [...]}
		if ts := pickNestedString(out, "dominant", "ts_code"); ts != "" {
			dominant[p] = ts
		}
	}
	t.Logf("主力合约解析：%v", dominant)

	// 期权合约代码也要现取：写死的月份过两个月就失效。
	optionCode := ""
	if out := reg.Dispatch(ctx, "list_option_contracts",
		`{"underlying":"510050.SH","limit":1}`); !isErrorResult(out) {
		optionCode = firstContractCode(out)
	}
	t.Logf("期权合约：%q", optionCode)

	cases := []struct {
		tool string
		args string
	}{
		// 行情
		{"search_instrument", `{"query":"贵州茅台"}`},
		{"get_realtime_quote", `{"symbol":"600519"}`},
		{"get_market_snapshot", `{}`},
		{"get_top_movers", `{"limit":5}`},
		// 海外 / 外盘 / 天气（本次新增或改源）
		{"get_overseas_futures", `{"symbols":["大豆","玉米","小麦","原油","黄金"]}`},
		{"get_region_weather", `{"keys":["us_corn_belt","india_sugar_up"],"days":3}`},
		{"get_quote", `{"symbol":"600519.SH","days":10}`},
		{"compare_quotes", `{"symbols":["600519.SH","000858.SZ"]}`},
		{"get_index_components", `{"index_code":"000300.SH"}`},
		// 期货 / 期权
		{"get_dominant_contract", `{"product":"螺纹钢"}`},
		{"get_futures_realtime", fmt.Sprintf(`{"ts_code":%q}`, dominant["螺纹钢"])},
		{"get_futures_realtime_batch", fmt.Sprintf(`{"ts_codes":[%q,%q]}`,
			dominant["螺纹钢"], dominant["豆粕"])},
		{"list_option_contracts", `{"underlying":"510050.SH"}`},
		{"get_option_quote", fmt.Sprintf(`{"ts_code":%q}`, optionCode)},
		{"screen_sell_put", `{"underlyings":["510050.SH"],"top_n":3}`},
		// 基本面
		{"get_valuation", `{"symbol":"600519.SH"}`},
		{"get_income_statement", `{"symbol":"600519.SH"}`},
		{"get_balance_sheet", `{"symbol":"600519.SH"}`},
		{"get_cash_flow", `{"symbol":"600519.SH"}`},
		{"get_dividend_history", `{"symbol":"600519.SH"}`},
		{"get_top_holders", `{"symbol":"600519.SH"}`},
		// 资金面 / 宏观
		{"get_margin_trading", `{"days":5}`},
		{"get_northbound_flow", `{}`},
		{"get_industry_money_flow", `{"top":5}`},
		{"get_economic_calendar", `{}`},
		// 海外 / 全球
		{"get_global_index", `{}`},
		{"get_us_stock_realtime", `{"symbol":"AAPL"}`},
		{"get_us_stock_realtime_batch", `{"symbols":["AAPL","NVDA"]}`},
		{"get_forex_rate", `{}`},
		// 资讯 / 事件
		{"search_chinese_news", `{"query":"美联储","limit":5}`},
		{"get_industry_news", `{"theme":"futures","limit":5}`},
		{"search_global_events", `{"query":"oil","limit":5}`},
		{"search_geopolitics_events", `{}`},
		{"search_shipping_events", `{}`},
		{"get_satellite_fire_hotspots", `{"west":100,"south":20,"east":130,"north":45,"day_range":1}`},
		// 量化
		{"calc_returns", `{"symbol":"600519.SH","days":20}`},
		{"calc_moving_average", `{"symbol":"600519.SH"}`},
		{"calc_rsi", `{"symbol":"600519.SH"}`},
		{"calc_macd", `{"symbol":"600519.SH"}`},
		{"calc_sharpe", `{"symbol":"600519.SH"}`},
		{"calc_max_drawdown", `{"symbol":"600519.SH"}`},
		{"calc_beta", `{"symbol":"600519.SH"}`},
		{"calc_correlation", `{"symbols":["600519.SH","000858.SZ"]}`},
		// 主题
		{"list_etfs_by_theme", `{"theme_keyword":"科技"}`},
		{"list_industry_stocks", `{"industry_keyword":"半导体"}`},
	}

	var failed []string
	for _, c := range cases {
		start := time.Now()
		out := reg.Dispatch(ctx, c.tool, c.args)
		dur := time.Since(start)
		if isErrorResult(out) {
			failed = append(failed, c.tool)
			t.Errorf("FAIL %-28s %4dms  %s", c.tool, dur.Milliseconds(), snippet(out, 200))
			continue
		}
		t.Logf("ok   %-28s %4dms  %s", c.tool, dur.Milliseconds(), snippet(out, 100))
	}

	// 列出没覆盖到的工具，避免"改天新增了工具但没人测"。
	covered := map[string]bool{}
	for _, c := range cases {
		covered[c.tool] = true
	}
	for _, n := range reg.Names() {
		if !covered[n] {
			t.Logf("未覆盖: %s", n)
		}
	}
	if len(failed) > 0 {
		t.Errorf("失败 %d 个：%s", len(failed), strings.Join(failed, ", "))
	}
}

// isErrorResult 判断工具返回体里是否带 error 字段（含 null 之外的任何值）。
func isErrorResult(out string) bool {
	var m map[string]any
	if err := json.Unmarshal([]byte(out), &m); err != nil {
		return true
	}
	if v, ok := m["error"]; ok && v != nil {
		s := fmt.Sprintf("%v", v)
		return strings.TrimSpace(s) != ""
	}
	// 批量类工具会把失败塞在子项里，这里只看顶层。
	return false
}

// pickString 从 JSON 里取一个字符串字段（用于在测试里串起多个工具）。
func pickString(out, key string) string {
	var m map[string]any
	if err := json.Unmarshal([]byte(out), &m); err != nil {
		return ""
	}
	if s, ok := m[key].(string); ok {
		return s
	}
	return ""
}

// TestDumpToolSpecs 打印所有工具的必填入参，方便写/修冒烟用例。
//
//	$env:FINME_SMOKE='1'; go test ./cmd/finme-server -run TestDumpToolSpecs -v
func TestDumpToolSpecs(t *testing.T) {
	if os.Getenv("FINME_SMOKE") != "1" {
		t.Skip("set FINME_SMOKE=1 to run")
	}
	cfg, err := platform.LoadConfig("")
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	l := zerolog.Nop()
	reg := buildToolRegistry(cfg, &l)
	for _, spec := range reg.ToolListJSON() {
		// ToolListJSON 返回的是 Go 值（properties 是 struct map），先做一次
		// JSON round-trip 才好按 map[string]any 取。
		raw, err := json.Marshal(spec)
		if err != nil {
			t.Fatal(err)
		}
		var m map[string]any
		if err := json.Unmarshal(raw, &m); err != nil {
			t.Fatal(err)
		}
		fn, _ := m["function"].(map[string]any)
		name, _ := fn["name"].(string)
		params, _ := fn["parameters"].(map[string]any)
		req, _ := params["required"].([]any)
		props, _ := params["properties"].(map[string]any)
		keys := make([]string, 0, len(props))
		for k := range props {
			keys = append(keys, k)
		}
		t.Logf("%-30s required=%v props=%v", name, req, keys)
	}
}

// pickNestedString 取嵌套对象里的字符串字段。
func pickNestedString(out, obj, key string) string {
	var m map[string]any
	if err := json.Unmarshal([]byte(out), &m); err != nil {
		return ""
	}
	inner, ok := m[obj].(map[string]any)
	if !ok {
		return ""
	}
	if s, ok := inner[key].(string); ok {
		return s
	}
	return ""
}

// firstContractCode 从 list_option_contracts 的返回里取第一个合约代码。
func firstContractCode(out string) string {
	var m struct {
		Contracts []struct {
			TsCode string `json:"ts_code"`
			Code   string `json:"code"`
		} `json:"contracts"`
	}
	if err := json.Unmarshal([]byte(out), &m); err != nil || len(m.Contracts) == 0 {
		return ""
	}
	if m.Contracts[0].TsCode != "" {
		return m.Contracts[0].TsCode
	}
	return m.Contracts[0].Code
}

func snippet(s string, n int) string {
	s = strings.ReplaceAll(s, "\n", " ")
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
