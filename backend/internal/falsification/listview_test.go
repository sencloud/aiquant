package falsification

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

// bigPayload 造一份「像生产」的导出：2 条精选、1 条仍在验证、1 条样本不足，
// 以及两个策略各一堆自动淘汰（a 有 30 条，b 有 5 条）。
func bigPayload(generatedAt, judgedAt string, extraHeadline string) string {
	var arch []string
	arch = append(arch,
		`{"id":"cur-1","strategy":"UT Bot","strategy_key":"utbot","verdict":"reject","curated":true,"failed_gate":"yearly",
		  "headline":"精选淘汰","mechanism":"手写机制","yearly":[["2021",1]],"command":"x","metrics":{"trades":500,"years":5,"positive_years":1}}`,
		`{"id":"cur-2","strategy":"UT Bot","strategy_key":"utbot","verdict":"finding","curated":true,"headline":"研究发现"}`,
		`{"id":"pend-1","strategy":"Pending","strategy_key":"p","verdict":"pending","headline":"待验",
		  "metrics":{"trades":900,"years":5,"positive_years":5},"window":{"start":"2020"},"judged_at":"`+judgedAt+`"}`,
		`{"id":"ins-1","strategy":"Noise","strategy_key":"n","verdict":"insufficient","failed_gate":"sample","headline":"太少"}`,
		`{"id":"ins-2","strategy":"Noise","strategy_key":"n","verdict":"insufficient","failed_gate":"sample","headline":"也太少"}`,
	)
	for i := 0; i < 30; i++ {
		gate := "yearly"
		if i == 7 {
			gate = "scale"
		}
		if i == 9 {
			gate = "drawdown"
		}
		arch = append(arch, fmt.Sprintf(`{"id":"a-%02d","strategy":"Alpha","strategy_key":"a","family_key":"trend","symbol":"S%02d","freq":"5min",
		  "verdict":"reject","failed_gate":%q,"headline":"a 淘汰 %d%s","license":"MIT","license_status":"open","asset_class":"stock",
		  "few":"x","window":{"start":"20240101","end":"20261008"},"judged_at":%q,"editor_verdict":null,
		  "metrics":{"trades":%d,"years":5,"positive_years":%d,"pf":0.9,"pnl_dd":-0.5,"max_dd_pct":null},
		  "gates":{"scale":{"status":"unknown","value":null,"threshold":{"pass_below":0.25}},
		           "yearly":{"status":"fail","value":{"years":5,"positive_years":1,"recent":[1,2,3]}}},
		  "yearly":[["2021",1]],"mechanism":"m","command":"alpharadar run --strategy a"}`,
			i, i, gate, i, extraHeadline, judgedAt, 300+i, i%5))
	}
	for i := 0; i < 5; i++ {
		arch = append(arch, fmt.Sprintf(`{"id":"b-%02d","strategy":"Beta","strategy_key":"b","family_key":"bands","symbol":"P.DCE","freq":"1d",
		  "verdict":"reject","failed_gate":"yearly","headline":"b 淘汰 %d","metrics":{"trades":%d,"years":4,"positive_years":1},
		  "command":"alpharadar run --strategy b"}`, i, i, 250+i))
	}
	return `{"generated_at":"` + generatedAt + `","threshold_version":"v1","gates":[{"id":"sample","name":"样本闸门"}],
	  "report_url":"https://internal/x","archive":[` + strings.Join(arch, ",") + `]}`
}

func mustPayload(t *testing.T, s string) Payload {
	t.Helper()
	p, err := Decode([]byte(s))
	if err != nil {
		t.Fatal(err)
	}
	return Sanitize(p)
}

func ids(p Payload) map[string]map[string]any {
	out := map[string]map[string]any{}
	for _, e := range Archive(p) {
		out[str(e["id"])] = e
	}
	return out
}

func TestListViewKeepsCoreAndSamplesRejects(t *testing.T) {
	p := mustPayload(t, bigPayload("2026-10-10T20:00:00", "2026-10-10T20:00:00", ""))
	v := ListView(p, false, nil, ListOptions{})
	got := ids(v)

	for _, id := range []string{"cur-1", "cur-2", "pend-1"} {
		if got[id] == nil {
			t.Fatalf("%s should always be listed", id)
		}
	}
	if got["ins-1"] != nil || got["ins-2"] != nil {
		t.Fatal("insufficient should be hidden without include=insufficient")
	}
	var a, b int
	for id := range got {
		switch {
		case strings.HasPrefix(id, "a-"):
			a++
		case strings.HasPrefix(id, "b-"):
			b++
		}
	}
	if a != 3 || b != 3 {
		t.Fatalf("each strategy should keep 3 representative rejects, got a=%d b=%d", a, b)
	}
	// 代表优先覆盖不同的失败闸门：drawdown（走得最远）、yearly、scale 各一条。
	gates := map[string]bool{}
	for id, e := range got {
		if strings.HasPrefix(id, "a-") {
			gates[str(e["failed_gate"])] = true
		}
	}
	if !gates["drawdown"] || !gates["yearly"] || !gates["scale"] {
		t.Fatalf("representatives should cover distinct failed gates, got %v", gates)
	}

	meta, ok := v["list"].(ListMeta)
	if !ok || meta.Omitted[VerdictReject] != 29 || meta.Returned != len(Archive(v)) || meta.Total != 38 {
		t.Fatalf("meta = %+v", v["list"])
	}

	// 精简 + 脱敏：不需要的字段、null、付费字段、report_url 都不在列表里。
	b2, _ := json.Marshal(v)
	body := string(b2)
	for _, bad := range []string{"report_url", `"window"`, `"judged_at"`, `"license"`, `"asset_class"`, `"few"`, "null", `"mechanism"`, `"command"`} {
		if strings.Contains(body, bad) {
			t.Fatalf("list should not contain %s", bad)
		}
	}
	e := got["a-09"]
	if e == nil {
		t.Fatal("a-09 (drawdown) should be a representative")
	}
	if e["locked"] != true || e["metrics"] == nil || e["gates"] == nil || e["headline"] == nil || e["failed_gate"] == nil {
		t.Fatalf("free fields missing: %v", e)
	}
	if y := e["gates"].(map[string]any)["yearly"].(map[string]any)["value"].(map[string]any); y["recent"] != nil {
		t.Fatal("yearly.recent is paid content")
	}
	// 源快照不被修改：完整条目里付费字段 / window / judged_at 都还在。
	src, _ := FindEntry(p, "a-09")
	if src["mechanism"] == nil || src["window"] == nil || src["judged_at"] == nil {
		t.Fatal("ListView mutated source payload")
	}
	if g := src["gates"].(map[string]any)["scale"].(map[string]any); g["value"] != nil || len(g) != 3 {
		// value 原本就是 null，键应该还在。
		if _, has := g["value"]; !has {
			t.Fatal("ListView mutated nested gates of source payload")
		}
	}

	// include=insufficient：样本不足每个策略只留 1 条代表。
	vi := ids(ListView(p, true, nil, ListOptions{}))
	if (vi["ins-1"] != nil) == (vi["ins-2"] != nil) {
		t.Fatal("insufficient should keep exactly one representative per strategy")
	}

	// 已解锁：带付费字段。
	vu := ids(ListView(p, false, map[string]bool{"a-09": true}, ListOptions{}))
	if vu["a-09"]["mechanism"] == nil || vu["a-09"]["locked"] != false {
		t.Fatal("unlocked entry should carry paid fields in list")
	}
}

func TestListViewGlobalCapRoundRobin(t *testing.T) {
	p := mustPayload(t, bigPayload("g", "j", ""))
	v := ListView(p, false, nil, ListOptions{RejectsPerStrategy: 10, MaxRejects: 4})
	var a, b int
	for id := range ids(v) {
		switch {
		case strings.HasPrefix(id, "a-"):
			a++
		case strings.HasPrefix(id, "b-"):
			b++
		}
	}
	// 总上限 4 在两个策略间轮流分：各 2 条，而不是被条目多的 a 吃光。
	if a != 2 || b != 2 {
		t.Fatalf("round robin cap: a=%d b=%d", a, b)
	}
	// 精选淘汰不受上限影响。
	if ids(v)["cur-1"] == nil {
		t.Fatal("curated reject must not count against the cap")
	}
}

func TestSearchCoversFullSnapshot(t *testing.T) {
	p := mustPayload(t, bigPayload("g", "j", ""))
	// a-20 不是代表，列表里没有，但能搜到。
	if ids(ListView(p, true, nil, ListOptions{}))["a-20"] != nil {
		t.Fatal("precondition: a-20 should not be in the list")
	}
	hits, meta := Search(p, "a 淘汰 20", 0, nil)
	if meta.Matched != 1 || len(hits) != 1 || hits[0].(map[string]any)["id"] != "a-20" {
		t.Fatalf("search = %+v %v", meta, hits)
	}
	h := hits[0].(map[string]any)
	if h["locked"] != true || h["mechanism"] != nil || h["window"] != nil {
		t.Fatalf("search hit should be slim and locked: %v", h)
	}
	// 中文家族名、周期、结论都能搜；大小写不敏感；样本不足也能搜到。
	if _, m := Search(p, "趋势跟随 5MIN", 0, nil); m.Matched != 30 {
		t.Fatalf("family+freq search matched %d", m.Matched)
	}
	if _, m := Search(p, "样本不足", 0, nil); m.Matched != 2 {
		t.Fatalf("verdict label search matched %d", m.Matched)
	}
	// limit 生效，精选排最前。
	hits, m := Search(p, "淘汰", 5, nil)
	if len(hits) != 5 || m.Matched < 30 || hits[0].(map[string]any)["id"] != "cur-1" {
		t.Fatalf("limit / ordering: %+v first=%v", m, hits[0])
	}
	if hits, _ := Search(p, "   ", 0, nil); len(hits) != 0 {
		t.Fatal("empty query returns nothing")
	}
}

func TestContentHashIgnoresVolatileFields(t *testing.T) {
	h1, _ := ContentHash(mustPayload(t, bigPayload("2026-10-10T20:00:00", "2026-10-10T20:00:00", "")))
	h2, _ := ContentHash(mustPayload(t, bigPayload("2026-10-10T21:00:00", "2026-10-10T21:00:05", "")))
	h3, _ := ContentHash(mustPayload(t, bigPayload("2026-10-10T21:00:00", "2026-10-10T21:00:05", "!")))
	if h1 != h2 {
		t.Fatal("generated_at / judged_at must not change the hash")
	}
	if h1 == h3 {
		t.Fatal("content change must change the hash")
	}
}

func TestSyncDedupeETagAndHash(t *testing.T) {
	st := openStore(t)
	var (
		body     atomic.Value
		etag     atomic.Value
		calls    atomic.Int32
		inm      atomic.Value
		honor304 atomic.Bool
	)
	body.Store(bigPayload("t0", "t0", ""))
	etag.Store(`"v0"`)
	inm.Store("")
	honor304.Store(true)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		inm.Store(r.Header.Get("If-None-Match"))
		if honor304.Load() && r.Header.Get("If-None-Match") == etag.Load().(string) {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		w.Header().Set("ETag", etag.Load().(string))
		w.Header().Set("Last-Modified", "Sat, 10 Oct 2026 12:00:00 GMT")
		_, _ = w.Write([]byte(body.Load().(string)))
	}))
	defer srv.Close()
	svc := NewService(st, nil, Options{URL: srv.URL, Prices: testPrices})
	ctx := context.Background()
	rows := func() int {
		var n int
		if err := st.DB.Get(&n, "SELECT COUNT(*) FROM falsification_snapshots"); err != nil {
			t.Fatal(err)
		}
		return n
	}

	r, err := svc.SyncDetailed(ctx)
	if err != nil || !r.Stored || r.Entries != 40 || rows() != 1 {
		t.Fatalf("first sync: %+v err=%v rows=%d", r, err, rows())
	}
	var checked0 int64
	_ = st.DB.Get(&checked0, "SELECT checked_at FROM falsification_snapshots")

	// 同一个 ETag：带 If-None-Match，上游 304，不新增行，只刷新 checked_at。
	r, err = svc.SyncDetailed(ctx)
	if err != nil || !r.NotModified || r.Stored || r.Entries != 40 || rows() != 1 {
		t.Fatalf("304 sync: %+v err=%v rows=%d", r, err, rows())
	}
	if inm.Load() != `"v0"` {
		t.Fatalf("If-None-Match = %v", inm.Load())
	}
	var checked1 int64
	_ = st.DB.Get(&checked1, "SELECT checked_at FROM falsification_snapshots")
	if checked1 < checked0 || checked1 == 0 {
		t.Fatal("checked_at should be refreshed")
	}

	// 上游重新生成：ETag 变了、generated_at / judged_at 变了，但结论没变 → 不新增。
	body.Store(bigPayload("t1", "t1", ""))
	etag.Store(`"v1"`)
	r, err = svc.SyncDetailed(ctx)
	if err != nil || !r.Unchanged || r.Stored || rows() != 1 {
		t.Fatalf("unchanged sync: %+v err=%v rows=%d", r, err, rows())
	}
	var storedETag string
	_ = st.DB.Get(&storedETag, "SELECT etag FROM falsification_snapshots")
	if storedETag != `"v1"` {
		t.Fatalf("etag should be refreshed on unchanged content, got %s", storedETag)
	}

	// 内容真的变了 → 新增一行；api 侧缓存失效后读到新内容。
	body.Store(bigPayload("t2", "t2", "!"))
	etag.Store(`"v2"`)
	r, err = svc.SyncDetailed(ctx)
	if err != nil || !r.Stored || rows() != 2 {
		t.Fatalf("changed sync: %+v err=%v rows=%d", r, err, rows())
	}
	p, origin := svc.Current(ctx)
	if e, _ := FindEntry(p, "a-00"); origin != OriginRemote || !strings.HasSuffix(str(e["headline"]), "!") {
		t.Fatal("Current should serve the new snapshot")
	}

	// 旧快照（0020 之前写入，没有 content_hash）也能去重：现算并回填。
	if _, err := st.DB.Exec("UPDATE falsification_snapshots SET content_hash='', etag=''"); err != nil {
		t.Fatal(err)
	}
	honor304.Store(false)
	r, err = svc.SyncDetailed(ctx)
	if err != nil || !r.Unchanged || rows() != 2 {
		t.Fatalf("legacy row dedupe: %+v err=%v rows=%d", r, err, rows())
	}

	// 保留份数上限。
	for i := 0; i < SnapshotRetention+3; i++ {
		body.Store(bigPayload("t", "t", fmt.Sprintf("#%d", i)))
		etag.Store(fmt.Sprintf(`"r%d"`, i))
		if _, err := svc.SyncDetailed(ctx); err != nil {
			t.Fatal(err)
		}
	}
	if rows() != SnapshotRetention {
		t.Fatalf("retention: rows=%d want %d", rows(), SnapshotRetention)
	}
}
