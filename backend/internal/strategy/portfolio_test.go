package strategy

import (
	"context"
	"math"
	"testing"
)

// 与线上 /api/live 同形：5 只建仓 → 9/30 调仓卖掉 4 只（建筑分两笔），剩华泰 500 股；
// 中国石化有一笔分红只记在资金流水里。
const fakeLiveWithTrades = `{
  "as_of":"2026-10-09","inception":"2026-09-21","capital":50000,
  "cash":41557.94,"market_value":8985,"total":50542.94,"pnl":542.94,"pnl_pct":0.010859,
  "realized":536.03,"fees":71.06,"dividends":252,
  "positions":[{"code":"601688.SH","name":"华泰证券","shares":500,"avg_cost":18.4602,
                "price":17.97,"market_value":8985,"cost":9230.09,"pnl":-245.09,"pnl_pct":-0.0266}],
  "curve":[{"date":"2026-10-09","total":50542.94}],
  "cash_flows":[{"flow_date":"2026-09-21","kind":"principal","amount":50000,"note":"本金投入"},
                {"flow_date":"2026-09-30","kind":"dividend","amount":252,"note":"中国石化分红 2400股×0.105"}],
  "trades":[
    {"trade_date":"2026-09-21","trade_time":"09:25:00","action":"buy","code":"601318.SH","name":"中国平安","shares":100,"price":53.3,"amount":5330,"commission":5,"stamp_tax":0,"transfer_fee":0.05},
    {"trade_date":"2026-09-21","trade_time":"09:25:00","action":"buy","code":"600050.SH","name":"中国联通","shares":3000,"price":4.22,"amount":12660,"commission":5,"stamp_tax":0,"transfer_fee":0.13},
    {"trade_date":"2026-09-21","trade_time":"09:25:00","action":"buy","code":"601668.SH","name":"中国建筑","shares":2200,"price":4.27,"amount":9394,"commission":5,"stamp_tax":0,"transfer_fee":0.09},
    {"trade_date":"2026-09-21","trade_time":"09:25:00","action":"buy","code":"600028.SH","name":"中国石化","shares":2400,"price":5.14,"amount":12336,"commission":5,"stamp_tax":0,"transfer_fee":0.12},
    {"trade_date":"2026-09-21","trade_time":"09:25:00","action":"buy","code":"601688.SH","name":"华泰证券","shares":500,"price":18.45,"amount":9225,"commission":5,"stamp_tax":0,"transfer_fee":0.09,"note":"策略建仓"},
    {"trade_date":"2026-09-30","trade_time":"09:30:00","action":"sell","code":"600050.SH","name":"中国联通","shares":3000,"price":4.24,"amount":12720,"commission":5,"stamp_tax":6.36,"transfer_fee":0.13},
    {"trade_date":"2026-09-30","trade_time":"09:30:00","action":"sell","code":"600028.SH","name":"中国石化","shares":2400,"price":5.29,"amount":12696,"commission":5,"stamp_tax":6.35,"transfer_fee":0.13},
    {"trade_date":"2026-09-30","trade_time":"09:30:00","action":"sell","code":"601318.SH","name":"中国平安","shares":100,"price":53.36,"amount":5336,"commission":5,"stamp_tax":2.67,"transfer_fee":0.05},
    {"trade_date":"2026-09-30","trade_time":"09:30:00","action":"sell","code":"601668.SH","name":"中国建筑","shares":1600,"price":4.35,"amount":6960,"commission":5,"stamp_tax":3.48,"transfer_fee":0.07},
    {"trade_date":"2026-09-30","trade_time":"09:30:00","action":"sell","code":"601668.SH","name":"中国建筑","shares":600,"price":4.35,"amount":2610,"commission":5,"stamp_tax":1.31,"transfer_fee":0.03}
  ]
}`

func TestBuildLivePortfolioReplaysTradesAndReconciles(t *testing.T) {
	svc := newTestService(t, fakeDashboard, fakeLiveWithTrades)
	ctx := context.Background()
	snap, err := svc.Sync(ctx)
	if err != nil {
		t.Fatal(err)
	}
	p := BuildLivePortfolio(snap)
	if p == nil {
		t.Fatal("nil portfolio")
	}
	if p.ID != "live:sse50_9f_top5" || p.Name != "实盘：上证50 九因子" {
		t.Fatalf("id/name: %s / %s", p.ID, p.Name)
	}
	if !p.Reconciled {
		t.Fatalf("trades replay should match positions: %+v", p.Transactions)
	}
	if len(p.Holdings) != 1 || p.Holdings[0].Symbol != "601688.SH" || p.Holdings[0].Industry != "证券" {
		t.Fatalf("holdings: %+v", p.Holdings)
	}
	var buys, sells, divs int
	shares := map[string]float64{}
	var htCost float64
	for _, tx := range p.Transactions {
		switch tx.Type {
		case "buy":
			buys++
			shares[tx.Symbol] += tx.Quantity
			if tx.Symbol == "601688.SH" {
				htCost += tx.Quantity * tx.Price
			}
		case "sell":
			sells++
			shares[tx.Symbol] -= tx.Quantity
		case "dividend":
			divs++
			if tx.Symbol != "600028.SH" || tx.Quantity != 2400 || tx.Price != 0.105 {
				t.Fatalf("dividend mapping: %+v", tx)
			}
		}
	}
	if buys != 5 || sells != 5 || divs != 1 {
		t.Fatalf("buys=%d sells=%d divs=%d", buys, sells, divs)
	}
	for code, n := range shares {
		want := 0.0
		if code == "601688.SH" {
			want = 500
		}
		if math.Abs(n-want) > 1e-9 {
			t.Fatalf("%s replayed %v, want %v", code, n, want)
		}
	}
	// 含费净价回放后的均价应与券商口径一致（18.4602）。
	if avg := htCost / 500; math.Abs(avg-18.4602) > 0.0005 {
		t.Fatalf("avg cost %v", avg)
	}
	for i := 1; i < len(p.Transactions); i++ {
		if p.Transactions[i-1].Date > p.Transactions[i].Date {
			t.Fatal("transactions not sorted by date")
		}
	}
}

func TestBuildLivePortfolioAddsAdjustmentWhenTradesMissing(t *testing.T) {
	// 旧快照没有 trades：必须补一条对账调整，保证持仓股数正确。
	svc := newTestService(t, fakeDashboard, fakeLive)
	snap, err := svc.Sync(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	p := BuildLivePortfolio(snap)
	if p.Reconciled || len(p.Transactions) != 1 {
		t.Fatalf("want one adjustment, got %+v", p.Transactions)
	}
	tx := p.Transactions[0]
	if tx.Type != "buy" || tx.Quantity != 500 || tx.Price != 18.36 || tx.Symbol != "601688.SH" {
		t.Fatalf("adjustment: %+v", tx)
	}
	if BuildLivePortfolio(&Snapshot{}) != nil {
		t.Fatal("no live section → nil")
	}
}

func TestMaterializeLivePortfolioIsIdempotentPerDay(t *testing.T) {
	svc := newTestService(t, fakeDashboard, fakeLiveWithTrades)
	ctx := context.Background()
	if _, err := svc.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	p1, new1, err := svc.MaterializeLivePortfolio(ctx)
	if err != nil || p1 == nil || !new1 {
		t.Fatalf("first: %v %v %v", p1, new1, err)
	}
	_, new2, err := svc.MaterializeLivePortfolio(ctx)
	if err != nil || new2 {
		t.Fatalf("second run same day should not be new: %v %v", new2, err)
	}
	var n int
	if err := svc.st.DB.Get(&n, `SELECT COUNT(1) FROM live_portfolio_daily`); err != nil || n != 1 {
		t.Fatalf("rows=%d err=%v", n, err)
	}
	got, err := svc.LatestLivePortfolio(ctx)
	if err != nil || got == nil || got.AsOf != "2026-10-09" || len(got.Transactions) != 11 {
		t.Fatalf("latest: %+v err=%v", got, err)
	}
	if err := NewLivePortfolioJob(svc, 0, svc.logger).Run(ctx); err != nil {
		t.Fatal(err)
	}
}
