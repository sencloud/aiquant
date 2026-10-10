package falsification

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

func openStore(t *testing.T) *store.Store {
	t.Helper()
	st, err := store.Open(platform.DBConfig{
		Path:          filepath.Join(t.TempDir(), "falsification_test.db"),
		BusyTimeoutMs: 5000, CacheKB: 4096, MaxOpenConns: 2, MaxIdleConns: 1,
	})
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { _ = st.Close() })
	return st
}

func newUser(t *testing.T, st *store.Store, balance int64) int64 {
	t.Helper()
	now := time.Now().UnixMilli()
	res, err := st.DB.Exec(`INSERT INTO users(uuid, status, credit_balance, created_at, updated_at)
		VALUES(?, 'active', ?, ?, ?)`, fmt.Sprintf("u-%d-%d", now, time.Now().UnixNano()), balance, now, now)
	if err != nil {
		t.Fatalf("insert user: %v", err)
	}
	id, _ := res.LastInsertId()
	return id
}

func balanceOf(t *testing.T, st *store.Store, uid int64) int64 {
	t.Helper()
	var b int64
	if err := st.DB.Get(&b, "SELECT credit_balance FROM users WHERE id=?", uid); err != nil {
		t.Fatal(err)
	}
	return b
}

func ledgerCount(t *testing.T, st *store.Store, uid int64, reason string) int {
	t.Helper()
	var n int
	if err := st.DB.Get(&n, "SELECT COUNT(*) FROM credit_ledger WHERE user_id=? AND reason=?", uid, reason); err != nil {
		t.Fatal(err)
	}
	return n
}

var testPrices = Prices{Unlock: 5, FalsifyDaily: 10, FalsifyMinute: 30}

// 上游 alpha-radar 的导出：含 report_url（顶层 / 条目 / 嵌套）、一条 NC 许可、
// 一条样本不足，以及新字段。
const upstreamJSON = `{
  "generated_at": "2026-10-10 12:00",
  "threshold_version": "gates-v1",
  "report_url": "https://internal/report/index.html",
  "gates": [{"id":"sample","name":"样本闸门","rule":"≥ 200 笔","why":"..."}],
  "summary": {"archive_total": 3},
  "archive": [
    {"id":"ema-cross-P-1d","strategy":"EMA 交叉","family":"趋势跟随","symbol":"P.DCE","freq":"1d",
     "verdict":"reject","failed_gate":"yearly","headline":"利润集中在一年",
     "metrics":{"trades":420,"years":6,"positive_years":2},
     "yearly":[["2021",100],["2022",-50]],"mechanism":"单年依赖","command":"alpharadar run --strategy ema_cross --symbol P.DCE",
     "report_url":"https://internal/r/1.html","gates":{"yearly":{"status":"fail","value":"2/6","threshold":"≥0.8","report_url":"x"}},
     "license":"MIT","curated":false,"threshold_version":"gates-v1","updated_at":"2026-10-10","asset_class":"futures"},
    {"id":"lux-thing","strategy":"Lux 某指标","family":"反转","verdict":"reject","license":"CC BY-NC-SA 4.0",
     "metrics":{"trades":300,"years":4},"command":"alpharadar run --strategy lux_thing"},
    {"id":"noise-1","strategy":"噪声","family":"反转","verdict":"insufficient","failed_gate":"sample",
     "metrics":{"trades":3,"years":1,"pf":99},"command":"alpharadar run --strategy noise"}
  ]
}`

func TestSanitizeStripsReportURLAndNonCommercial(t *testing.T) {
	p, err := Decode([]byte(upstreamJSON))
	if err != nil {
		t.Fatal(err)
	}
	p = Sanitize(p)
	b, _ := json.Marshal(p)
	if strings.Contains(string(b), "report_url") {
		t.Fatalf("report_url leaked: %s", b)
	}
	for _, e := range Archive(p) {
		if e["id"] == "lux-thing" {
			t.Fatal("non-commercial entry should be dropped")
		}
	}
	if !IsNonCommercial("CC BY-NC-SA 4.0") || !IsNonCommercial("cc by-nc 4.0") || IsNonCommercial("MIT") ||
		IsNonCommercial("原创实现") || IsNonCommercial("") {
		t.Fatal("IsNonCommercial misclassified")
	}
}

func TestSeedIsValidAndCurated(t *testing.T) {
	p, err := Seed()
	if err != nil {
		t.Fatal(err)
	}
	arch := Archive(p)
	if len(arch) < 8 {
		t.Fatalf("seed archive = %d", len(arch))
	}
	for _, e := range arch {
		if c, _ := e["curated"].(bool); !c {
			t.Fatalf("seed entry %v not curated", e["id"])
		}
		if IsNonCommercial(str(e["license"])) {
			t.Fatalf("seed entry %v is non-commercial", e["id"])
		}
	}
	if p["threshold_version"] == nil || p["cost_scales"] == nil {
		t.Fatal("seed missing threshold_version / cost_scales")
	}
}

func TestPublicViewFiltersAndLocks(t *testing.T) {
	p, _ := Decode([]byte(upstreamJSON))
	p = Sanitize(p)

	v := PublicView(p, false, nil)
	arch := Archive(v)
	if len(arch) != 1 || arch[0]["id"] != "ema-cross-P-1d" {
		t.Fatalf("main list should only contain non-insufficient entries, got %v", arch)
	}
	e := arch[0]
	if e["locked"] != true {
		t.Fatal("entry should be locked for anonymous")
	}
	for _, f := range PaidFields {
		if _, ok := e[f]; ok {
			t.Fatalf("paid field %s leaked", f)
		}
	}
	if e["metrics"] == nil || e["headline"] == nil || e["gates"] == nil || e["failed_gate"] == nil {
		t.Fatal("free fields missing")
	}
	// 原始 payload 不被修改。
	if orig, _ := FindEntry(p, "ema-cross-P-1d"); orig["mechanism"] == nil {
		t.Fatal("PublicView mutated source payload")
	}

	all := Archive(PublicView(p, true, map[string]bool{"ema-cross-P-1d": true}))
	if len(all) != 2 {
		t.Fatalf("include=insufficient should return 2, got %d", len(all))
	}
	if all[0]["locked"] != false || all[0]["mechanism"] == nil {
		t.Fatal("unlocked entry should carry paid fields")
	}
}

func TestSyncAndCurrentWithFallback(t *testing.T) {
	st := openStore(t)
	var up atomic.Bool
	up.Store(true)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/falsification" || !up.Load() {
			http.Error(w, "down", http.StatusBadGateway)
			return
		}
		_, _ = w.Write([]byte(upstreamJSON))
	}))
	defer srv.Close()
	svc := NewService(st, nil, Options{URL: srv.URL, Prices: testPrices})
	ctx := context.Background()

	// 还没同步过：回落 seed。
	p, origin := svc.Current(ctx)
	if origin != OriginSeed || len(Archive(p)) < 8 {
		t.Fatalf("expected seed fallback, got %s / %d", origin, len(Archive(p)))
	}

	n, err := svc.Sync(ctx)
	if err != nil || n != 2 {
		t.Fatalf("sync: n=%d err=%v", n, err)
	}
	p, origin = svc.Current(ctx)
	if origin != OriginRemote {
		t.Fatalf("origin = %s", origin)
	}
	b, _ := json.Marshal(p)
	if strings.Contains(string(b), "report_url") {
		t.Fatal("report_url stored / served")
	}
	// 上游没有精选档案 → seed 的精选档案被补进来，cost_scales 也补齐。
	if _, ok := FindEntry(p, "utbot-5min"); !ok {
		t.Fatal("curated seed entries should be merged")
	}
	if p["cost_scales"] == nil {
		t.Fatal("cost_scales should be filled from seed")
	}

	// 上游挂了：Sync 报错，但仍返回上一份快照。
	up.Store(false)
	if _, err := svc.Sync(ctx); err == nil {
		t.Fatal("expected sync error")
	}
	svc.invalidate()
	if _, origin = svc.Current(ctx); origin != OriginRemote {
		t.Fatal("should keep last snapshot when upstream is down")
	}
}

func TestUnlockChargesOnceAndIsIdempotent(t *testing.T) {
	st := openStore(t)
	svc := NewService(st, nil, Options{Prices: testPrices})
	ctx := context.Background()
	uid := newUser(t, st, 12)

	res, err := svc.Unlock(ctx, uid, "utbot-5min")
	if err != nil {
		t.Fatal(err)
	}
	if res.Charged != 5 || res.Already || res.Entry["mechanism"] == nil || res.Entry["locked"] != false {
		t.Fatalf("first unlock: %+v", res)
	}
	res, err = svc.Unlock(ctx, uid, "utbot-5min")
	if err != nil || res.Charged != 0 || !res.Already {
		t.Fatalf("second unlock should be free: %+v %v", res, err)
	}
	if b := balanceOf(t, st, uid); b != 7 {
		t.Fatalf("balance = %d, want 7", b)
	}
	if n := ledgerCount(t, st, uid, billing.ReasonConsumeUnlock); n != 1 {
		t.Fatalf("consume_unlock rows = %d", n)
	}

	// 另一个用户解锁同一条：各自扣费（ref_id 带用户）。
	uid2 := newUser(t, st, 5)
	if res, err := svc.Unlock(ctx, uid2, "utbot-5min"); err != nil || res.Charged != 5 {
		t.Fatalf("user2 unlock: %+v %v", res, err)
	}

	// 余额不足。
	uid3 := newUser(t, st, 4)
	if _, err := svc.Unlock(ctx, uid3, "utbot-5min"); !errors.Is(err, billing.ErrInsufficientBalance) {
		t.Fatalf("want insufficient, got %v", err)
	}
	if ids, _ := svc.UnlockedIDs(ctx, uid3); len(ids) != 0 {
		t.Fatal("failed unlock must not be recorded")
	}

	if _, err := svc.Unlock(ctx, uid, "nope"); !errors.Is(err, ErrEntryNotFound) {
		t.Fatalf("want not found, got %v", err)
	}
	d, err := svc.Detail(ctx, uid, "utbot-5min")
	if err != nil || d["locked"] != false {
		t.Fatalf("detail for unlocked: %v %v", d, err)
	}
	d, _ = svc.Detail(ctx, uid3, "utbot-5min")
	if d["locked"] != true || d["mechanism"] != nil {
		t.Fatal("detail for locked user leaked")
	}
}

func TestRunStubIsUnsupportedAndFree(t *testing.T) {
	st := openStore(t)
	svc := NewService(st, nil, Options{Prices: testPrices})
	ctx := context.Background()
	uid := newUser(t, st, 100)

	opts := svc.Options(ctx)
	if opts.Available || len(opts.Strategies) == 0 || len(opts.Symbols) == 0 {
		t.Fatalf("options: %+v", opts)
	}
	run, err := svc.CreateRun(ctx, uid, "utbot", "P.DCE", "5min")
	if err != nil {
		t.Fatal(err)
	}
	if run.Status != RunUnsupported || run.Charged || run.Credits != 30 || run.Message == "" {
		t.Fatalf("stub run: %+v", run)
	}
	if b := balanceOf(t, st, uid); b != 100 {
		t.Fatalf("stub must not charge, balance=%d", b)
	}
	if _, err := svc.CreateRun(ctx, uid, "not-a-strategy", "P.DCE", "5min"); !errors.Is(err, ErrInvalidRunInput) {
		t.Fatalf("unknown strategy should be rejected: %v", err)
	}
	if _, err := svc.CreateRun(ctx, uid, "utbot", "P.DCE", "2min"); !errors.Is(err, ErrInvalidRunInput) {
		t.Fatal("bad freq should be rejected")
	}
	if got, err := svc.GetRun(ctx, uid, run.ID); err != nil || got.Status != RunUnsupported {
		t.Fatalf("get run: %+v %v", got, err)
	}
	if _, err := svc.GetRun(ctx, uid+1, run.ID); !errors.Is(err, ErrRunNotFound) {
		t.Fatal("other user must not see the run")
	}
}

// fakeRunner 模拟 alpha-radar 任务接口。
type fakeRunner struct {
	submitErr error
	status    string
}

func (f *fakeRunner) Available() bool { return true }
func (f *fakeRunner) Submit(context.Context, RunRequest) (string, error) {
	if f.submitErr != nil {
		return "", f.submitErr
	}
	return "job-1", nil
}
func (f *fakeRunner) Status(context.Context, string) (*RunStatus, error) {
	if f.status == RunDone {
		return &RunStatus{Status: RunDone, Result: map[string]any{"verdict": "reject", "report_url": "x"}}, nil
	}
	return &RunStatus{Status: f.status, Error: "boom"}, nil
}

func TestRunChargesAndRefundsOnFailure(t *testing.T) {
	st := openStore(t)
	fr := &fakeRunner{status: RunQueued}
	svc := NewService(st, nil, Options{Prices: testPrices, Runner: fr})
	ctx := context.Background()
	uid := newUser(t, st, 45)

	// 日线 10 喜点：扣费 → 完成。
	run, err := svc.CreateRun(ctx, uid, "utbot", "P.DCE", "1d")
	if err != nil || run.Status != RunQueued || !run.Charged || run.Credits != 10 {
		t.Fatalf("create: %+v %v", run, err)
	}
	fr.status = RunDone
	got, err := svc.GetRun(ctx, uid, run.ID)
	if err != nil || got.Status != RunDone || got.Result == nil || got.Result["report_url"] != nil {
		t.Fatalf("done: %+v %v", got, err)
	}
	if b := balanceOf(t, st, uid); b != 35 {
		t.Fatalf("balance = %d, want 35", b)
	}

	// 分钟线 30 喜点：上游失败 → 退款，重复查询不重复退。
	fr.status = RunQueued
	run, err = svc.CreateRun(ctx, uid, "utbot", "P.DCE", "5min")
	if err != nil || balanceOf(t, st, uid) != 5 {
		t.Fatalf("create minute run: %v balance=%d", err, balanceOf(t, st, uid))
	}
	fr.status = RunFailed
	got, _ = svc.GetRun(ctx, uid, run.ID)
	if got.Status != RunFailed || !got.Refunded {
		t.Fatalf("failed run: %+v", got)
	}
	_, _ = svc.GetRun(ctx, uid, run.ID)
	if b := balanceOf(t, st, uid); b != 35 {
		t.Fatalf("after refund balance = %d, want 35", b)
	}
	if n := ledgerCount(t, st, uid, billing.ReasonRefundFalsify); n != 1 {
		t.Fatalf("refund rows = %d", n)
	}

	// 余额不足：不登记、不扣费。
	poor := newUser(t, st, 29)
	if _, err := svc.CreateRun(ctx, poor, "utbot", "P.DCE", "5min"); !errors.Is(err, billing.ErrInsufficientBalance) {
		t.Fatalf("want insufficient, got %v", err)
	}
	if runs, _ := svc.ListRuns(ctx, poor); len(runs) != 0 {
		t.Fatal("insufficient run must not be recorded")
	}

	// 提交失败：立即退款。
	fr.submitErr = errors.New("queue down")
	run, err = svc.CreateRun(ctx, uid, "utbot", "P.DCE", "1d")
	if err != nil || run.Status != RunFailed || !run.Refunded {
		t.Fatalf("submit failure: %+v %v", run, err)
	}
	if b := balanceOf(t, st, uid); b != 35 {
		t.Fatalf("after submit failure balance = %d", b)
	}
	if n := ledgerCount(t, st, uid, billing.ReasonConsumeFalsify); n != 3 {
		t.Fatalf("consume_falsify rows = %d", n)
	}
}

func TestHTTPRunnerContract(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Api-Key") != "k" {
			http.Error(w, "no", http.StatusUnauthorized)
			return
		}
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/api/runs/paid":
			var req RunRequest
			_ = json.NewDecoder(r.Body).Decode(&req)
			if req.Strategy != "utbot" || req.RunID == "" {
				http.Error(w, "bad", http.StatusBadRequest)
				return
			}
			w.WriteHeader(http.StatusAccepted)
			_, _ = w.Write([]byte(`{"job_id":"j9"}`))
		case r.Method == http.MethodGet && r.URL.Path == "/api/runs/paid/j9":
			_, _ = w.Write([]byte(`{"status":"running"}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()
	h := NewHTTPRunner(srv.URL+"/", "k")
	id, err := h.Submit(context.Background(), RunRequest{RunID: "r", Strategy: "utbot", Symbol: "P.DCE", Freq: "1d"})
	if err != nil || id != "j9" {
		t.Fatalf("submit: %q %v", id, err)
	}
	st, err := h.Status(context.Background(), "j9")
	if err != nil || st.Status != RunRunning {
		t.Fatalf("status: %+v %v", st, err)
	}
}

// contractJSON 取自 alpha-radar docs/falsification-export.md（schema_version 1）。
const contractJSON = `{
  "schema_version": 1,
  "generated_at": "2026-10-10T18:00:00",
  "threshold_version": "2026-10-10.v1",
  "gates": [{"id":"sample","name":"样本闸门","rule":"r","why":"w"},
            {"id":"scale","name":"尺度闸门","rule":"r","why":"w"}],
  "summary": {"archive_total": 3, "curated": 1, "auto": 2,
              "by_verdict": {"tradable":0,"pending":1,"finding":0,"reject":1,"insufficient":1},
              "failed_gate": {"scale":0,"yearly":1,"drawdown":0},
              "tradable":0,"pending":1,"rejected":1},
  "archive": [
    {"id":"orb-5min","strategy":"ORB","strategy_key":"orb_classic","family":"日内突破","family_key":"breakout",
     "license":"MIT","license_status":"open","symbol":"P.DCE","freq":"5min","verdict":"reject","failed_gate":"yearly",
     "flags":["rerun_pending"],"curated":true,"editor_verdict":"reject","headline":"h",
     "metrics":{"trades":1223,"pf":0.889,"avg_points":null},
     "gates":{"yearly":{"status":"fail","value":{"positive_years":0,"years":5,"recent":[["2023",-1],["2024",-2],["2025",-3]]},"threshold":{"min_positive_ratio":0.8}}},
     "yearly":[["2022",-10]],"mechanism":"m","command":"alpharadar run --strategy orb_classic"},
    {"id":"supertrend-p-dce-5min","strategy":"SuperTrend","strategy_key":"supertrend","family":"趋势跟随","family_key":"trend",
     "license":"MPL-2.0","license_status":"open","symbol":"P.DCE","freq":"5min","verdict":"pending","failed_gate":null,
     "flags":["scale_marginal"],"curated":false,"headline":"h","metrics":{"trades":500,"pf":1.3},
     "yearly":[],"mechanism":"","command":"alpharadar run --strategy supertrend"},
    {"id":"x-nc","strategy":"X","strategy_key":"x","family":"反转","family_key":"reversal","license":"",
     "license_status":"nc","symbol":"P.DCE","freq":"5min","verdict":"pending","curated":false,"headline":"h"}
  ]
}`

func TestContractPayload(t *testing.T) {
	p, err := Decode([]byte(contractJSON))
	if err != nil {
		t.Fatal(err)
	}
	seed, err := Seed()
	if err != nil {
		t.Fatal(err)
	}
	p = Merge(Sanitize(p), seed)

	if _, ok := FindEntry(p, "x-nc"); ok {
		t.Fatal("license_status=nc must be dropped")
	}
	orb, ok := FindEntry(p, "orb-5min")
	if !ok {
		t.Fatal("orb missing")
	}
	if StrategyKey(orb) != "orb_classic" {
		t.Fatalf("strategy key = %q", StrategyKey(orb))
	}
	if orb["rerun_pending"] != true {
		t.Fatal("rerun_pending should be derived from flags")
	}
	sum := p["summary"].(map[string]any)
	if sum["archive_rejected"] != 1 || sum["archive_pending"] != 1 || sum["rejected"] != float64(1) {
		t.Fatalf("legacy summary not filled: %v", sum)
	}
	if p["cost_scales"] == nil || p["source"] == nil {
		t.Fatal("cost_scales / source should come from seed")
	}
	// 上游有精选档案时，不再追加 seed 的精选档案。
	if _, ok := FindEntry(p, "utbot-5min"); ok {
		t.Fatal("seed curated entries should not be merged when upstream has curated")
	}

	// 未解锁：付费字段与分年闸门里的近三年盈亏都去掉，免费的闸门结论保留。
	locked := LockedCopy(orb, false)
	for _, f := range PaidFields {
		if _, has := locked[f]; has {
			t.Fatalf("paid field %s leaked", f)
		}
	}
	y := locked["gates"].(map[string]any)["yearly"].(map[string]any)
	if y["status"] != "fail" || y["value"].(map[string]any)["recent"] != nil {
		t.Fatalf("yearly gate not redacted: %v", y)
	}
	// 原条目不被改动。
	if orb["gates"].(map[string]any)["yearly"].(map[string]any)["value"].(map[string]any)["recent"] == nil {
		t.Fatal("LockedCopy must not mutate the source entry")
	}
	full := LockedCopy(orb, true)
	if full["mechanism"] != "m" || full["locked"] != false {
		t.Fatal("unlocked copy should keep paid fields")
	}
}
