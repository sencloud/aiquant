package miniapp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/llm"
)

// fakeLLM 按顺序返回预设输出，并记录每次收到的消息。
type fakeLLM struct {
	mu    sync.Mutex
	outs  []string
	err   error
	calls [][]llm.Message
}

func (f *fakeLLM) Complete(_ context.Context, _ string, msgs []llm.Message) (string, llm.Usage, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, append([]llm.Message(nil), msgs...))
	if f.err != nil {
		return "", llm.Usage{}, f.err
	}
	if len(f.outs) == 0 {
		return `{"action":"refuse","message":"没有更多脚本"}`, llm.Usage{}, nil
	}
	o := f.outs[0]
	f.outs = f.outs[1:]
	return o, llm.Usage{PromptTokens: 100, CompletionTokens: 50}, nil
}

func newTestService(t *testing.T, l LLM) (*Service, *testDeps) {
	t.Helper()
	d := newTestDeps(t)
	svc := NewService(d.st, d.reg, NewFetcher(d.reg, FetcherOptions{}), l, Options{Sync: true}, nil)
	return svc, d
}

// userSeq 保证测试用户 uuid 唯一（Windows 上 time.Now 精度不够，曾撞 UNIQUE）。
var userSeq atomic.Int64

func addUser(t *testing.T, d *testDeps, balance int64) int64 {
	t.Helper()
	res, err := d.st.DB.Exec(`INSERT INTO users(uuid, status, credit_balance, created_at, updated_at) VALUES(?, 'active', ?, 0, 0)`,
		fmt.Sprintf("u-%s-%d", t.Name(), userSeq.Add(1)), balance)
	if err != nil {
		t.Fatal(err)
	}
	id, _ := res.LastInsertId()
	return id
}

func balance(t *testing.T, d *testDeps, uid int64) int64 {
	var b int64
	if err := d.st.DB.Get(&b, "SELECT credit_balance FROM users WHERE id=?", uid); err != nil {
		t.Fatal(err)
	}
	return b
}

func ledgerCount(t *testing.T, d *testDeps, uid int64) int {
	var n int
	_ = d.st.DB.Get(&n, "SELECT COUNT(*) FROM credit_ledger WHERE user_id=?", uid)
	return n
}

func templateSpec(t *testing.T, id string) string {
	t.Helper()
	for _, tp := range mustTemplates(t) {
		if tp.ID == id {
			b, _ := json.Marshal(tp.Spec)
			return string(b)
		}
	}
	t.Fatalf("no template %s", id)
	return ""
}

func mustTemplates(t *testing.T) []*Template {
	d := newTestDeps(t)
	tpls, errs := LoadTemplates(d.reg)
	if len(errs) > 0 {
		t.Fatal(errs)
	}
	return tpls
}

func specEnv(spec string) string {
	return `{"action":"spec","summary":"做好了","spec":` + spec + `}`
}

var reqN int

func req(topic, msg string) GenRequest {
	reqN++
	return GenRequest{RequestID: fmt.Sprintf("req-%08d", reqN), Topic: topic, Message: msg}
}

func TestGenerateCreateChargesAndSaves(t *testing.T) {
	f := &fakeLLM{outs: []string{specEnv(templateSpec(t, "money.spread_monitor"))}}
	svc, d := newTestService(t, f)
	uid := addUser(t, d, 20)
	ctx := context.Background()
	g, err := svc.Generate(ctx, uid, req("money", "盯一下豆粕和菜粕价差"))
	if err != nil {
		t.Fatal(err)
	}
	if g.Status != GenDone || g.Outcome != OutcomeSpec || g.Result == nil || g.Result.AppUUID == "" || g.Refunded {
		t.Fatalf("gen = %+v", g)
	}
	if b := balance(t, d, uid); b != 15 {
		t.Fatalf("balance = %d, want 15", b)
	}
	app, err := svc.Get(ctx, uid, g.Result.AppUUID)
	if err != nil || app.Version != 1 || app.Status != "draft" || app.Mounted {
		t.Fatalf("app=%+v err=%v", app, err)
	}
	// 系统提示带上了目录与数据源。
	if sys := f.calls[0][0].Content; !strings.Contains(sys, "futures.dominant") || strings.Contains(sys, "fishing.forecast") {
		t.Fatalf("money prompt should list only money sources")
	}

	// 继续同一会话 → 修改同一个小应用，扣 2。
	f.outs = []string{specEnv(templateSpec(t, "money.spread_monitor"))}
	r2 := req("money", "标题改短一点")
	r2.AppUUID = g.Result.AppUUID
	g2, err := svc.Generate(ctx, uid, r2)
	if err != nil || g2.Outcome != OutcomeSpec || g2.Kind != "iterate" || g2.Result.Version != 2 || g2.SessionID != g.SessionID {
		t.Fatalf("iterate g2=%+v err=%v", g2, err)
	}
	if b := balance(t, d, uid); b != 13 {
		t.Fatalf("balance = %d, want 13", b)
	}
	// 修改时把当前 spec 发给了模型。
	last := f.calls[len(f.calls)-1]
	found := false
	for _, m := range last {
		if strings.Contains(m.Content, "当前小应用的 spec") {
			found = true
		}
	}
	if !found {
		t.Fatal("iterate should send current spec")
	}
	vs, _ := svc.Versions(ctx, uid, g.Result.AppUUID)
	if len(vs) != 2 {
		t.Fatalf("versions = %v", vs)
	}
}

func TestGenerateIdempotentReplay(t *testing.T) {
	f := &fakeLLM{outs: []string{specEnv(templateSpec(t, "money.etf_dca"))}}
	svc, d := newTestService(t, f)
	uid := addUser(t, d, 10)
	r := req("money", "定投计算器")
	g1, err := svc.Generate(context.Background(), uid, r)
	if err != nil {
		t.Fatal(err)
	}
	g2, err := svc.Generate(context.Background(), uid, r)
	if err != nil || !g2.Replayed || g2.Result.AppUUID != g1.Result.AppUUID {
		t.Fatalf("replay g2=%+v err=%v", g2, err)
	}
	if b := balance(t, d, uid); b != 5 {
		t.Fatalf("balance = %d, want 5 (charged once)", b)
	}
	if n := ledgerCount(t, d, uid); n != 1 {
		t.Fatalf("ledger rows = %d", n)
	}
	if len(f.calls) != 1 {
		t.Fatalf("llm calls = %d", len(f.calls))
	}
}

func TestGenerateRefundOnAskRefuseFail(t *testing.T) {
	cases := []struct {
		name    string
		outs    []string
		err     error
		outcome string
	}{
		{"ask", []string{`{"action":"ask","message":"想看哪个品种？","questions":[{"q":"品种","options":["豆粕","菜粕","玉米","棉花","白糖"]},{"q":"a","options":["1","2"]},{"q":"b","options":["1","2"]},{"q":"c","options":["1","2"]}]}`}, nil, OutcomeAsk},
		{"refuse", []string{`{"action":"refuse","message":"不能自动下单，可以做一个价格提醒面板"}`}, nil, OutcomeRefuse},
		{"llm_error", nil, errors.New("boom"), OutcomeFail},
		{"never_valid", []string{"not json", `{"action":"spec","spec":{"meta":{}}}`, `{"action":"dance"}`, "{"}, nil, OutcomeFail},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := &fakeLLM{outs: c.outs, err: c.err}
			svc, d := newTestService(t, f)
			uid := addUser(t, d, 5)
			g, err := svc.Generate(context.Background(), uid, req("money", "帮我自动下单"))
			if err != nil {
				t.Fatal(err)
			}
			if g.Outcome != c.outcome || !g.Refunded {
				t.Fatalf("gen = %+v", g)
			}
			if b := balance(t, d, uid); b != 5 {
				t.Fatalf("balance = %d, want 5 after refund", b)
			}
			if n := ledgerCount(t, d, uid); n != 2 {
				t.Fatalf("ledger rows = %d, want charge+refund", n)
			}
			if c.outcome == OutcomeAsk {
				if len(g.Result.Questions) != 3 || len(g.Result.Questions[0].Options) != 4 {
					t.Fatalf("questions not clamped: %+v", g.Result.Questions)
				}
			}
			if c.name == "never_valid" && len(f.calls) != 4 {
				t.Fatalf("want 1+3 repair calls, got %d", len(f.calls))
			}
			var apps int
			_ = d.st.DB.Get(&apps, "SELECT COUNT(*) FROM mini_apps WHERE user_id=?", uid)
			if apps != 0 {
				t.Fatalf("no app should be created, got %d", apps)
			}
			// 退款幂等：再退一次不会多出流水。
			var row genRow
			_ = d.st.DB.Get(&row, "SELECT * FROM mini_app_gens WHERE user_id=?", uid)
			svc.finishFail(&row, "x", "x", time.Now())
			if n := ledgerCount(t, d, uid); n != 2 || balance(t, d, uid) != 5 {
				t.Fatalf("double refund: rows=%d bal=%d", n, balance(t, d, uid))
			}
		})
	}
}

func TestRepairLoopFixesValidationAndDryRun(t *testing.T) {
	good := templateSpec(t, "money.spread_monitor")
	// 第一轮：用了钓鱼主题的数据源（白名单外）→ 校验失败；第二轮：坏字段 → 试运行报问题；第三轮：好的。
	bad := strings.Replace(good, `"futures.dominant"`, `"fishing.forecast"`, 1)
	dry := strings.Replace(good, "data.ma.close - data.mb.close", "data.ma.closing - data.mb.closing", 1)
	if dry == good {
		t.Fatal("template changed; update test")
	}
	f := &fakeLLM{outs: []string{specEnv(bad), specEnv(dry), specEnv(good)}}
	svc, d := newTestService(t, f)
	uid := addUser(t, d, 5)
	g, err := svc.Generate(context.Background(), uid, req("money", "价差监控"))
	if err != nil {
		t.Fatal(err)
	}
	if g.Outcome != OutcomeSpec {
		t.Fatalf("gen = %+v", g)
	}
	if len(f.calls) != 3 {
		t.Fatalf("calls = %d", len(f.calls))
	}
	second := f.calls[1]
	feedback := second[len(second)-1].Content
	if !strings.Contains(feedback, "没通过校验") || !strings.Contains(feedback, "fishing.forecast") {
		t.Fatalf("validation feedback = %q", feedback)
	}
	third := f.calls[2]
	if fb := third[len(third)-1].Content; !strings.Contains(fb, "试运行有问题") || !strings.Contains(fb, "computed.spread") || !strings.Contains(fb, "closing") || !strings.Contains(fb, "ts_code") {
		t.Fatalf("dry-run feedback = %q", fb)
	}
	var rounds int
	_ = d.st.DB.Get(&rounds, "SELECT repair_rounds FROM mini_app_gens WHERE user_id=?", uid)
	if rounds < 1 {
		t.Fatalf("repair_rounds = %d", rounds)
	}
	if b := balance(t, d, uid); b != 0 {
		t.Fatalf("balance = %d", b)
	}
}

func TestSourceWhitelistPerTopic(t *testing.T) {
	d := newTestDeps(t)
	money := templateSpec(t, "money.palm_morning")
	fish := templateSpec(t, "fishing.reservoir_compare")
	if _, issues := ValidateJSON([]byte(money), "fishing", d.reg); len(issues) == 0 {
		t.Fatal("money spec must not validate under fishing")
	}
	if _, issues := ValidateJSON([]byte(fish), "money", d.reg); len(issues) == 0 {
		t.Fatal("fishing spec must not validate under money")
	}
	for _, src := range d.reg.ForTopic("money") {
		if strings.HasPrefix(src.ID, "fishing.") {
			t.Fatalf("money exposes %s", src.ID)
		}
	}
	for _, src := range d.reg.ForTopic("fishing") {
		if strings.HasPrefix(src.ID, "futures.") || strings.HasPrefix(src.ID, "stock.") {
			t.Fatalf("fishing exposes %s", src.ID)
		}
	}
}

func TestQuotas(t *testing.T) {
	f := &fakeLLM{}
	svc, d := newTestService(t, f)
	ctx := context.Background()
	uid := addUser(t, d, 1000)

	// 余额不足。
	poor := addUser(t, d, 1)
	f.outs = []string{specEnv(templateSpec(t, "money.etf_dca"))}
	if _, err := svc.Generate(ctx, poor, req("money", "x")); !errors.Is(err, errInsufficient()) {
		t.Fatalf("want insufficient, got %v", err)
	}

	// 每分钟 3 次。
	for i := 0; i < 3; i++ {
		f.outs = []string{`{"action":"refuse","message":"不行"}`}
		if _, err := svc.Generate(ctx, uid, req("money", "x")); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := svc.Generate(ctx, uid, req("money", "x")); !errors.Is(err, ErrTooFast) {
		t.Fatalf("want too fast, got %v", err)
	}

	// 每主题 20 个（从模板复制免费，同样计数）。
	u2 := addUser(t, d, 0)
	for i := 0; i < MaxAppsPerTopic; i++ {
		if _, err := svc.FromTemplate(ctx, u2, "money.etf_dca"); err != nil {
			t.Fatalf("copy %d: %v", i, err)
		}
	}
	if _, err := svc.FromTemplate(ctx, u2, "money.etf_dca"); !errors.Is(err, ErrAppLimit) {
		t.Fatalf("want app limit, got %v", err)
	}
	if _, err := svc.Generate(ctx, u2, req("money", "x")); !errors.Is(err, ErrAppLimit) {
		t.Fatalf("generate should hit app limit before charging, got %v", err)
	}
	// 钓鱼主题单独计数。
	if _, err := svc.FromTemplate(ctx, u2, "fishing.bait_mix"); err != nil {
		t.Fatal(err)
	}
	// 挂载 12 个上限：模板复制时前 12 个自动挂载。
	list, _ := svc.List(ctx, u2, "money")
	mounted := 0
	var unmounted string
	for _, a := range list {
		if a.Mounted {
			mounted++
		} else {
			unmounted = a.UUID
		}
	}
	if mounted != MaxMountedPerTopic || len(list) != MaxAppsPerTopic {
		t.Fatalf("mounted=%d total=%d", mounted, len(list))
	}
	if _, err := svc.Mount(ctx, u2, unmounted, "small"); !errors.Is(err, ErrMountLimit) {
		t.Fatalf("want mount limit, got %v", err)
	}
	if b := balance(t, d, u2); b != 0 {
		t.Fatalf("templates must be free, balance=%d", b)
	}
}

func TestMountReorderDeleteRestore(t *testing.T) {
	svc, d := newTestService(t, &fakeLLM{})
	ctx := context.Background()
	uid := addUser(t, d, 0)
	a, _ := svc.FromTemplate(ctx, uid, "fishing.bait_mix")
	b, _ := svc.FromTemplate(ctx, uid, "fishing.reservoir_compare")
	c, _ := svc.FromTemplate(ctx, uid, "fishing.month_catches")
	list, err := svc.Reorder(ctx, uid, "fishing", []string{c.UUID, a.UUID, b.UUID})
	if err != nil {
		t.Fatal(err)
	}
	if list[0].UUID != c.UUID || list[1].UUID != a.UUID || list[2].Position != 2 {
		t.Fatalf("order = %v %v %v", list[0].Title, list[1].Title, list[2].Title)
	}
	if _, err := svc.Reorder(ctx, uid, "fishing", []string{c.UUID, a.UUID}); !errors.Is(err, ErrBadInput) {
		t.Fatalf("partial reorder should fail: %v", err)
	}
	if err := svc.Delete(ctx, uid, a.UUID); err != nil {
		t.Fatal(err)
	}
	list, _ = svc.List(ctx, uid, "fishing")
	if len(list) != 2 || list[0].Position != 0 || list[1].Position != 1 {
		t.Fatalf("after delete: %+v", list)
	}
	if _, err := svc.Get(ctx, uid, a.UUID); !errors.Is(err, ErrNotFound) {
		t.Fatal("deleted app still visible")
	}
	// 别人看不到。
	other := addUser(t, d, 0)
	if _, err := svc.Get(ctx, other, b.UUID); !errors.Is(err, ErrNotFound) {
		t.Fatal("cross-user access")
	}
	if _, err := svc.Run(ctx, other, b.UUID, nil); !errors.Is(err, ErrNotFound) {
		t.Fatal("cross-user run")
	}
	// 重命名 + 恢复。
	title := "我的水库"
	if v, err := svc.Rename(ctx, uid, b.UUID, &title, nil); err != nil || v.Title != title {
		t.Fatalf("rename v=%+v err=%v", v, err)
	}
	bad := "必涨神器"
	if _, err := svc.Rename(ctx, uid, b.UUID, &bad, nil); err == nil {
		// 钓鱼主题不含金融违禁词，可以通过；改用钓鱼违禁词。
		bad2 := "电鱼神器"
		if _, err := svc.Rename(ctx, uid, b.UUID, &bad2, nil); !errors.Is(err, ErrBadInput) {
			t.Fatalf("banned title accepted: %v", err)
		}
	}
	if v, err := svc.Restore(ctx, uid, b.UUID, 1); err != nil || v.Version != 2 {
		t.Fatalf("restore v=%+v err=%v", v, err)
	}
	// 参数保存只留合法的。
	v, err := svc.SaveState(ctx, uid, c.UUID, map[string]any{"nope": 1}, map[string]any{"k": "v"})
	if err != nil || len(v.Inputs) != 0 || v.State["k"] != "v" {
		t.Fatalf("state v=%+v err=%v", v, err)
	}
	if res, err := svc.Run(ctx, uid, c.UUID, nil); err != nil || res == nil {
		t.Fatalf("run err=%v", err)
	}
}

func TestTemplateRunAnonymous(t *testing.T) {
	svc, _ := newTestService(t, nil)
	res, err := svc.RunTemplate(context.Background(), 0, "1.2.3.4", "fishing.month_catches", nil)
	if err != nil || res == nil {
		t.Fatalf("anon template run: %v", err)
	}
	if _, err := svc.RunTemplate(context.Background(), 0, "1.2.3.4", "nope", nil); !errors.Is(err, ErrNotFound) {
		t.Fatal("unknown template")
	}
	if _, err := svc.Generate(context.Background(), 1, req("money", "x")); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("nil llm: %v", err)
	}
}

func TestRecoverStale(t *testing.T) {
	block := make(chan struct{})
	svc, d := newTestService(t, &blockingLLM{c: block})
	svc.opts.Sync = false
	uid := addUser(t, d, 5)
	g, err := svc.Generate(context.Background(), uid, req("money", "x"))
	if err != nil || g.Status != GenPending {
		t.Fatalf("g=%+v err=%v", g, err)
	}
	if b := balance(t, d, uid); b != 0 {
		t.Fatalf("pre-charge missing: %d", b)
	}
	svc.opts.Now = func() time.Time { return time.Now().Add(time.Hour) }
	n, err := svc.RecoverStale(context.Background(), 10*time.Minute)
	if err != nil || n != 1 {
		t.Fatalf("recover n=%d err=%v", n, err)
	}
	if b := balance(t, d, uid); b != 5 {
		t.Fatalf("not refunded: %d", b)
	}
	close(block)
}

type blockingLLM struct{ c chan struct{} }

func (b *blockingLLM) Complete(ctx context.Context, _ string, _ []llm.Message) (string, llm.Usage, error) {
	select {
	case <-b.c:
	case <-ctx.Done():
	}
	return "", llm.Usage{}, errors.New("cancelled")
}

func errInsufficient() error { return billingErrInsufficient }

func TestDevLLMBranches(t *testing.T) {
	d := newTestDeps(t)
	tpls, _ := LoadTemplates(d.reg)
	svc := NewService(d.st, d.reg, NewFetcher(d.reg, FetcherOptions{}), &DevLLM{Templates: tpls}, Options{Sync: true}, nil)
	uid := addUser(t, d, 100)
	ctx := context.Background()
	g, err := svc.Generate(ctx, uid, req("fishing", "比较几个水库明天的出钓指数"))
	if err != nil || g.Outcome != OutcomeSpec {
		t.Fatalf("g=%+v err=%v", g, err)
	}
	app, _ := svc.Get(ctx, uid, g.Result.AppUUID)
	if app.Topic != "fishing" || app.Title == "" {
		t.Fatalf("app = %+v", app)
	}
	r := req("money", "问我几个问题")
	if g, _ := svc.Generate(ctx, uid, r); g.Outcome != OutcomeAsk {
		t.Fatalf("ask: %+v", g)
	}
	if g, _ := svc.Generate(ctx, uid, req("money", "帮我自动下单")); g.Outcome != OutcomeRefuse {
		t.Fatalf("refuse: %+v", g)
	}
}
