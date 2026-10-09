package strategy

import (
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

const fakeDashboard = `{
  "params": {"universe":"上证50 当期成分","topn":5,"exclude":["银行"],
             "capital":50000,"since":"2020-01-02","until":"2026-09-30"},
  "kpi": {"capital":50000,"equity":110240,"pnl":60240,"pnl_pct":1.2048,
          "backtest_cagr":0.1244,"backtest_sharpe":0.76,"backtest_dd":-0.2164,
          "month_win":0.5625,"fees":2040,"trades":203},
  "equity": [["2020-01-02",1.0077],["2026-09-30",2.2048]],
  "benchmark": [["2020-01-02",1.0],["2026-09-30",0.9134]],
  "yearly": [{"year":2020,"ret":-0.0783},{"year":2026,"ret":-0.0041}],
  "holdings": [{"code":"601688.SH","name":"华泰证券","industry":"证券",
                "price":17.8,"score":0.84,"z":{"ep":0.99,"dv":0.2}}],
  "factors": [{"factor":"ep","ic":0.076,"t":3.5,"oos":0.0596,"win":0.5274}],
  "factor_meta": {"ep":["1/PE_TTM","估值","高","市盈率倒数，越便宜越好"]},
  "universes": [{"name":"上证50","total":1.679,"cagr":0.1746,"sharpe":1.15,"dd":-0.1746}],
  "next": {"signal":"2026-09-30","exec":"2026-10-08","changed":false,
           "note":"目标名单与上期相同，下次调仓无需操作",
           "target":[{"code":"600050.SH","name":"中国联通"},
                     {"code":"601688.SH","name":"华泰证券"}],
           "prev_target":[{"code":"600050.SH","name":"中国联通"},
                          {"code":"601688.SH","name":"华泰证券"}]}
}`

// 实盘只持有一只，且与目标名单不一致——这正是"人工调过仓"的场景。
const fakeLive = `{
  "as_of":"2026-09-30","inception":"2026-09-21","capital":50000,
  "cash":40811,"market_value":8900,"total":49711,"pnl":-289,"pnl_pct":-0.0058,
  "realized":536.03,"fees":71.06,"dividends":252,
  "positions":[{"code":"601688.SH","name":"华泰证券","shares":500,"avg_cost":18.36,
                "price":17.8,"market_value":8900,"cost":9180,"pnl":-280,"pnl_pct":-0.0305}],
  "curve":[{"date":"2026-09-30","total":49711}]
}`

func newTestService(t *testing.T, dash, live string) *Service {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/api/dashboard", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(dash))
	})
	mux.HandleFunc("/api/live", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(live))
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)

	st, err := store.Open(platform.DBConfig{
		Path:          filepath.Join(t.TempDir(), "strategy_test.db"),
		BusyTimeoutMs: 5000,
		CacheKB:       4096,
		MaxOpenConns:  2,
		MaxIdleConns:  1,
	})
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { _ = st.Close() })
	l := zerolog.Nop()
	// tu 传 nil：过期判断走"数工作日"的退化路径，测试因此是确定的。
	return NewService(st, &l, nil, srv.URL)
}

func TestSyncAndLatestNormalizesExternalData(t *testing.T) {
	svc := newTestService(t, fakeDashboard, fakeLive)
	ctx := context.Background()

	snap, err := svc.Sync(ctx)
	if err != nil {
		t.Fatalf("sync: %v", err)
	}
	if snap.Meta.Name == "" || snap.Meta.Summary == "" || snap.Meta.Disclosure == "" {
		t.Fatal("策略说明/口径声明不应为空（这是可信度来源）")
	}
	if snap.DataAsOf != "2026-09-30" {
		t.Fatalf("data_as_of = %q", snap.DataAsOf)
	}
	if len(snap.Action.Target) != 2 || snap.Action.ExecDate != "2026-10-08" {
		t.Fatalf("action 归一化异常: %+v", snap.Action)
	}
	if snap.Metrics.CAGR != 0.1244 || snap.Metrics.MaxDrawdown != -0.2164 {
		t.Fatalf("metrics 异常: %+v", snap.Metrics)
	}
	// 目标名单里只有华泰证券能拿到因子明细（外部只对持仓给出 z 值）。
	if len(snap.Action.TargetDetail) != 2 {
		t.Fatalf("target_detail 应逐条对齐目标名单: %+v", snap.Action.TargetDetail)
	}
	if snap.Action.TargetDetail[1].Score != 0.84 || snap.Action.TargetDetail[1].Z["ep"] != 0.99 {
		t.Fatalf("因子明细未映射: %+v", snap.Action.TargetDetail[1])
	}
	if len(snap.Benchmarks) != 1 {
		t.Fatalf("基准应有 1 条: %+v", snap.Benchmarks)
	}
	if len(snap.Factors) != 1 || snap.Factors[0].Name != "1/PE_TTM" {
		t.Fatalf("因子中文名未从 factor_meta 带上: %+v", snap.Factors)
	}
	if snap.Factors[0].Group != "估值" || snap.Factors[0].Desc == "" {
		t.Fatalf("因子分类/说明缺失: %+v", snap.Factors[0])
	}
	if got := snap.Benchmarks[0].Total; got > -0.08 || got < -0.09 {
		t.Fatalf("基准收益算错: %v", got)
	}
	if len(snap.Curve) != 2 {
		t.Fatalf("曲线点数异常: %d", len(snap.Curve))
	}

	// 实盘：目标 2 只、实际只持 1 只 → 必须标记与策略不一致。
	if snap.Live == nil {
		t.Fatal("live 段缺失")
	}
	if !snap.Live.Divergence {
		t.Fatal("实盘持仓集合与目标名单不同时必须标记 divergence")
	}
	if len(snap.Live.Positions) != 1 {
		t.Fatalf("持仓数异常: %+v", snap.Live.Positions)
	}
	if !snap.Live.Positions[0].InTarget {
		t.Fatal("华泰证券在目标名单里，应标记 InTarget")
	}
	if w := snap.Live.Positions[0].Weight; w < 0.17 || w > 0.19 {
		t.Fatalf("权重应由市值/总值算出: %v", w)
	}

	// Latest 读回的是同一份，并且带回 synced_at。
	got, err := svc.Latest(ctx)
	if err != nil {
		t.Fatalf("latest: %v", err)
	}
	if got == nil || got.Action.ExecDate != "2026-10-08" || got.SyncedAt == 0 {
		t.Fatalf("latest 读回异常: %+v", got)
	}
	// 2026-09-30 的数据相对"现在"必然是过期的（测试环境日期更晚）。
	if !got.Stale || got.StaleDays <= 0 {
		t.Fatalf("过期标记异常: stale=%v days=%d", got.Stale, got.StaleDays)
	}
}

func TestLatestWithoutDataReturnsNil(t *testing.T) {
	svc := newTestService(t, fakeDashboard, fakeLive)
	got, err := svc.Latest(context.Background())
	if err != nil {
		t.Fatalf("latest: %v", err)
	}
	if got != nil {
		t.Fatalf("还没有快照时应返回 nil，得到 %+v", got)
	}
}

func TestNormalizeLiveNoDivergenceWhenAligned(t *testing.T) {
	live := &liveResp{AsOf: "2026-09-30", Total: 100000}
	live.Positions = append(live.Positions,
		livePosition{Code: "600050.SH", Name: "中国联通", Shares: 100, MarketValue: 100000})

	aligned := normalizeLive(live, []TargetItem{{Code: "600050.SH", Name: "中国联通"}})
	if aligned.Divergence {
		t.Fatal("持仓与目标一致时不应标记 divergence")
	}
	if !aligned.Positions[0].InTarget {
		t.Fatal("持仓应标记为目标名单内")
	}
	// 换成不在目标名单里的持仓 → 该笔标 false，且整体标记不一致。
	live.Positions[0].Code = "601688.SH"
	stray := normalizeLive(live, []TargetItem{{Code: "600050.SH", Name: "中国联通"}})
	if stray.Positions[0].InTarget {
		t.Fatal("名单外的持仓不应标记 InTarget")
	}
	if !stray.Divergence {
		t.Fatal("名单外的持仓应标记 divergence")
	}
}

// 交易日历不可用时的退化路径：按工作日判断，且当天收盘前不把"今天"算作落后。
func TestStalenessFallback(t *testing.T) {
	svc := &Service{tu: nil, logger: ptrLogger()}
	cases := []struct {
		name     string
		now      time.Time
		dataAsOf string
		wantStale bool
		wantDays int
	}{
		{"当天收盘后已更新", time.Date(2026, 10, 9, 20, 0, 0, 0, shanghai), "2026-10-09", false, 0},
		{"当天收盘前不算落后", time.Date(2026, 10, 9, 10, 0, 0, 0, shanghai), "2026-10-08", false, 0},
		{"落后一个工作日", time.Date(2026, 10, 9, 20, 0, 0, 0, shanghai), "2026-10-08", true, 1},
		{"跨越周末只算工作日", time.Date(2026, 10, 12, 20, 0, 0, 0, shanghai), "2026-10-09", true, 1},
		{"周末不该误报过期", time.Date(2026, 10, 10, 20, 0, 0, 0, shanghai), "2026-10-09", false, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			stale, days := svc.staleness(context.Background(), c.dataAsOf, c.now)
			if stale != c.wantStale || days != c.wantDays {
				t.Fatalf("got stale=%v days=%d, want %v/%d", stale, days, c.wantStale, c.wantDays)
			}
		})
	}
}

func ptrLogger() *zerolog.Logger {
	l := zerolog.Nop()
	return &l
}
