package strategy

import (
	"context"
	"math"
	"strings"
	"testing"
	"time"
)

// 3 只的策略：7/1 建仓（推出来的名单 联通/华泰/平安），8/3 剔除平安换石化；
// 5/6 那笔成交与名单对不上 → 历史在那里截断。最新信号 8/31 名单不变。
const simDashboard = `{
  "params": {"universe":"上证50 当期成分","topn":3,"exclude":["银行"],
             "capital":50000,"since":"2020-01-02","until":"2026-09-04"},
  "kpi": {"capital":50000,"equity":110240,"trades":203},
  "equity": [["2020-01-02",1.0],["2026-09-04",2.2]],
  "benchmark": [["2020-01-02",1.0],["2026-09-04",0.9]],
  "trades": [
    {"date":"2026-08-03","action":"buy","code":"600028.SH","name":"中国石化","shares":4800,"price":5.45,"amount":26173.08,"fee":6.81,"pnl":null},
    {"date":"2026-08-03","action":"sell","code":"601318.SH","name":"中国平安","shares":400,"price":53.4,"amount":21000,"fee":16.0,"pnl":120.5},
    {"date":"2026-07-01","action":"buy","code":"601318.SH","name":"中国平安","shares":400,"price":53.49,"amount":21406.7,"fee":5.57,"pnl":null},
    {"date":"2026-07-01","action":"buy","code":"601688.SH","name":"华泰证券","shares":1300,"price":19.4,"amount":25232.61,"fee":6.56,"pnl":null},
    {"date":"2026-07-01","action":"sell","code":"601668.SH","name":"中国建筑","shares":4200,"price":5.14,"amount":21500,"fee":16.0,"pnl":-30},
    {"date":"2026-07-01","action":"sell","code":"600900.SH","name":"长江电力","shares":700,"price":27.79,"amount":19400,"fee":15.0,"pnl":800},
    {"date":"2026-05-06","action":"buy","code":"601857.SH","name":"中国石油","shares":2400,"price":8.8,"amount":21120,"fee":5.5,"pnl":null}
  ],
  "next": {"signal":"2026-08-31","exec":"2026-09-01","changed":false,
           "note":"目标名单与上期相同，下次调仓无需操作",
           "target":[{"code":"600050.SH","name":"中国联通"},{"code":"601688.SH","name":"华泰证券"},
                     {"code":"600028.SH","name":"中国石化"}],
           "prev_target":[{"code":"600050.SH","name":"中国联通"},{"code":"601688.SH","name":"华泰证券"},
                          {"code":"600028.SH","name":"中国石化"}]}
}`

// fakePrices：工作日都有收盘价；华泰 8/10 起涨到 22；联通 7/15 除息 0.1；石化 8/20 送转 10 送 3。
type fakePrices struct {
	calls   int
	failDiv bool
}

var simBase = map[string]float64{
	"600050.SH": 5, "601688.SH": 20, "600028.SH": 6, "601318.SH": 50,
	"601668.SH": 5, "600900.SH": 28, "601857.SH": 9,
}

func (f *fakePrices) DailyCloses(_ context.Context, code string, start, end time.Time) ([]DailyClose, error) {
	f.calls++
	var out []DailyClose
	for d := start; !d.After(end); d = d.AddDate(0, 0, 1) {
		if d.Weekday() == time.Saturday || d.Weekday() == time.Sunday {
			continue
		}
		ds := d.Format("2006-01-02")
		px := simBase[code]
		if code == "601688.SH" && ds >= "2026-08-10" {
			px = 22
		}
		out = append(out, DailyClose{Date: ds, Close: px})
	}
	return out, nil
}

func (f *fakePrices) Dividends(_ context.Context, code string) ([]Dividend, error) {
	if f.failDiv {
		return nil, context.DeadlineExceeded
	}
	switch code {
	case "600050.SH":
		return []Dividend{{ExDate: "2026-07-15", CashPerShare: 0.1}}, nil
	case "600028.SH":
		return []Dividend{{ExDate: "2026-08-20", StockPerShare: 0.3}}, nil
	}
	return nil, nil
}

func simSnapshot(t *testing.T) *Snapshot {
	t.Helper()
	svc := newTestService(t, simDashboard, fakeLive)
	snap, err := svc.Sync(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	return snap
}

func codesOf(ts []TargetItem) string {
	var s []string
	for _, t := range ts {
		s = append(s, t.Code)
	}
	return strings.Join(s, ",")
}

func TestReconstructRebalancesWalksBackFromLatestTarget(t *testing.T) {
	snap := simSnapshot(t)
	if len(snap.BacktestTrades) != 7 {
		t.Fatalf("backtest trades not normalized: %d", len(snap.BacktestTrades))
	}
	plans, note := ReconstructRebalances(snap)
	if len(plans) != 2 {
		t.Fatalf("plans: %+v", plans)
	}
	if plans[0].Date != "2026-07-01" || !plans[0].Initial ||
		codesOf(plans[0].Target) != "600050.SH,601318.SH,601688.SH" ||
		codesOf(plans[0].Buys) != codesOf(plans[0].Target) || len(plans[0].Sells) != 0 {
		t.Fatalf("initial: %+v", plans[0])
	}
	if plans[1].Date != "2026-08-03" || codesOf(plans[1].Buys) != "600028.SH" ||
		codesOf(plans[1].Sells) != "601318.SH" ||
		codesOf(plans[1].Target) != "600028.SH,600050.SH,601688.SH" {
		t.Fatalf("second: %+v", plans[1])
	}
	if !strings.Contains(note, "2026-07-01") || !strings.Contains(note, "截断") {
		t.Fatalf("note: %s", note)
	}

	// 最新一期名单变了、上游回测还没执行：以上期名单为终点倒推，再补一期。
	snap.Action.Changed = true
	snap.Action.ExecDate = "2026-09-01"
	snap.Action.PrevTarget = snap.Action.Target
	snap.Action.Target = []TargetItem{{Code: "600050.SH", Name: "中国联通"},
		{Code: "601688.SH", Name: "华泰证券"}, {Code: "601857.SH", Name: "中国石油"}}
	plans, _ = ReconstructRebalances(snap)
	if len(plans) != 3 || plans[2].Date != "2026-09-01" ||
		codesOf(plans[2].Buys) != "601857.SH" || codesOf(plans[2].Sells) != "600028.SH" {
		t.Fatalf("pending: %+v", plans)
	}

	// 没有回测成交：只能从最新一期建仓，并如实说明。
	snap.BacktestTrades = nil
	snap.Action.Changed = false
	plans, note = ReconstructRebalances(snap)
	if len(plans) != 1 || !plans[0].Initial || plans[0].Date != "2026-09-01" || !strings.Contains(note, "最新一期") {
		t.Fatalf("no history: %+v %s", plans, note)
	}
}

func TestSimulatePortfolioFollowsSignalsWithCosts(t *testing.T) {
	snap := simSnapshot(t)
	p, err := SimulatePortfolio(context.Background(), snap, &fakePrices{}, 1_000_000)
	if err != nil {
		t.Fatal(err)
	}
	if p.ID != LivePortfolioID || p.Mode != "simulation" || p.Name != "策略模拟：上证50 九因子" {
		t.Fatalf("id/mode/name: %s %s %s", p.ID, p.Mode, p.Name)
	}
	if p.Capital != 1_000_000 || p.Inception != "2026-07-01" || p.AsOf != "2026-09-30" {
		t.Fatalf("capital/range: %v %s %s", p.Capital, p.Inception, p.AsOf)
	}
	if len(p.Holdings) != 3 || codesOf(snap.Action.Target) == "" {
		t.Fatalf("holdings: %+v", p.Holdings)
	}
	for _, h := range p.Holdings {
		if !h.InTarget {
			t.Fatalf("holding not in latest target: %+v", h)
		}
		if h.Symbol != "600028.SH" && math.Mod(h.Shares, 100) != 0 {
			t.Fatalf("lot rounding: %+v", h)
		}
	}
	var buys, sells, divs, splits int
	for _, tx := range p.Transactions {
		switch tx.Type {
		case "buy":
			buys++
		case "sell":
			sells++
		case "dividend":
			divs++
		case "split":
			splits++
		}
		if strings.Contains(tx.Note, "对账") {
			t.Fatal("no reconciliation rows in simulation")
		}
	}
	if buys != 4 || sells != 1 || divs != 1 || splits != 1 {
		t.Fatalf("buys=%d sells=%d divs=%d splits=%d: %+v", buys, sells, divs, splits, p.Transactions)
	}
	// 建仓：100 万三等分，联通 5 元 → 66,600 股（含滑点与费用不超预算）。
	first := p.Transactions[0]
	if first.Date != "2026-07-01" || first.Symbol != "600050.SH" || first.Quantity != 66600 {
		t.Fatalf("first buy: %+v", first)
	}
	wantFee := math.Max(5, 66600*5.0025*0.00025) + 66600*5.0025*0.00001
	if math.Abs(first.Fees-round2(wantFee)) > 0.011 || first.GrossPrice != 5.0025 {
		t.Fatalf("buy cost model: %+v want fee %.2f", first, wantFee)
	}
	// 分红：联通 66,600 × 0.1。
	if p.Dividends != 6660 {
		t.Fatalf("dividends %v", p.Dividends)
	}
	// 账务恒等式：总资产 − 本金 = 持仓浮盈 + 已实现 + 分红。
	var unreal float64
	for _, h := range p.Holdings {
		unreal += h.PnL
	}
	if math.Abs((p.Total-p.Capital)-(unreal+p.Realized+p.Dividends)) > 0.05 {
		t.Fatalf("identity: total=%v unreal=%v realized=%v div=%v", p.Total, unreal, p.Realized, p.Dividends)
	}
	if math.Abs(p.Total-(p.Cash+p.MarketValue)) > 0.01 || p.Cash < 0 {
		t.Fatalf("cash/mv: %v %v %v", p.Total, p.Cash, p.MarketValue)
	}
	if len(p.Curve) == 0 || p.Curve[0].Date != "2026-07-01" || p.Curve[len(p.Curve)-1].Total != p.Total {
		t.Fatalf("curve: %v … %v", p.Curve[0], p.Curve[len(p.Curve)-1])
	}
	if len(p.Rebalances) != 2 || !strings.Contains(p.Description, "非实盘") || p.CostModel == "" {
		t.Fatalf("rebalances/desc: %d %s", len(p.Rebalances), p.Description)
	}

	// 分红取不到：照常模拟，记一条说明。
	p2, err := SimulatePortfolio(context.Background(), snap, &fakePrices{failDiv: true}, 0)
	if err != nil || p2.Capital != DefaultSimCapital || p2.Dividends != 0 || len(p2.Notes) == 0 {
		t.Fatalf("degrade: %v %+v", err, p2)
	}
}

func TestMaterializeLivePortfolioIsIdempotentAndDropsOldRows(t *testing.T) {
	svc := newTestService(t, simDashboard, fakeLive)
	fp := &fakePrices{}
	svc.prices = fp
	svc.SimCapital = 1_000_000
	ctx := context.Background()
	if _, err := svc.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	// 早期按人工实盘生成的旧行：必须被清掉。
	if _, err := svc.st.DB.Exec(`INSERT INTO live_portfolio_daily(portfolio_id, as_of, payload_json, materialized_at)
		VALUES(?, '2026-10-09', '{"name":"实盘：上证50 九因子","reconciled":true}', 1)`, LivePortfolioID); err != nil {
		t.Fatal(err)
	}
	p1, new1, err := svc.MaterializeLivePortfolio(ctx)
	if err != nil || p1 == nil || !new1 {
		t.Fatalf("first: %v %v %v", p1, new1, err)
	}
	calls := fp.calls
	p2, new2, err := svc.MaterializeLivePortfolio(ctx)
	if err != nil || new2 || p2.Total != p1.Total {
		t.Fatalf("second run: %v %v", new2, err)
	}
	if fp.calls != calls {
		t.Fatal("unchanged inputs should not refetch prices")
	}
	var n int
	if err := svc.st.DB.Get(&n, `SELECT COUNT(1) FROM live_portfolio_daily`); err != nil || n != 1 {
		t.Fatalf("rows=%d err=%v", n, err)
	}
	got, err := svc.LatestLivePortfolio(ctx)
	if err != nil || got == nil || got.Mode != "simulation" || got.AsOf != "2026-09-30" || len(got.Holdings) != 3 {
		t.Fatalf("latest: %+v err=%v", got, err)
	}
	// 本金改了 → 输入变了，重算。
	svc.SimCapital = 500_000
	p3, _, err := svc.MaterializeLivePortfolio(ctx)
	if err != nil || p3.Capital != 500_000 || fp.calls == calls {
		t.Fatalf("capital change: %v %v", p3, err)
	}
	if err := NewLivePortfolioJob(svc, 0, svc.logger).Run(ctx); err != nil {
		t.Fatal(err)
	}
}

func TestMaterializeWithoutTushareFails(t *testing.T) {
	svc := newTestService(t, simDashboard, fakeLive)
	ctx := context.Background()
	if _, err := svc.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.MaterializeLivePortfolio(ctx); err == nil || !strings.Contains(err.Error(), "tushare") {
		t.Fatalf("want tushare error, got %v", err)
	}
}
