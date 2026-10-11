package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tushare"
	"github.com/sencloud/finme-backend/internal/fishing"
	"github.com/sencloud/finme-backend/internal/llm"
	"github.com/sencloud/finme-backend/internal/miniapp"
)

type nopTools struct{}

func (nopTools) Has(string) bool { return true }
func (nopTools) Dispatch(context.Context, string, string) string {
	return `{"error":"offline in test"}`
}

type scriptLLM struct{ outs []string }

func (s *scriptLLM) Complete(context.Context, string, []llm.Message) (string, llm.Usage, error) {
	if len(s.outs) == 0 {
		return `{"action":"refuse","message":"不行"}`, llm.Usage{}, nil
	}
	o := s.outs[0]
	s.outs = s.outs[1:]
	return o, llm.Usage{}, nil
}

func newMiniAppEnv(t *testing.T, l miniapp.LLM) (*testEnv, *miniapp.Service) {
	t.Helper()
	var svc *miniapp.Service
	e := newTestEnvWith(t, func(d *Deps) {
		fs := fishing.NewService(d.Store, nil, nil, nil)
		hist := func(context.Context, string, time.Time, time.Time) ([]tushare.Candle, error) {
			return nil, errors.New("offline in test")
		}
		reg := miniapp.BuiltinRegistry(miniapp.BuiltinDeps{Tools: nopTools{}, History: hist, Fishing: fs})
		svc = miniapp.NewService(d.Store, reg, miniapp.NewFetcher(reg, miniapp.FetcherOptions{}), l,
			miniapp.Options{Sync: true}, nil)
		d.MiniApps = svc
	})
	return e, svc
}

func specEnvelope(t *testing.T, svc *miniapp.Service, topic string) string {
	tp := svc.Templates(topic)[0]
	b, _ := json.Marshal(map[string]any{"action": "spec", "summary": "ok", "spec": tp.Spec})
	return string(b)
}

func TestMiniAppPublicTemplatesNoAuth(t *testing.T) {
	e, _ := newMiniAppEnv(t, nil)
	for _, topic := range []string{"money", "fishing"} {
		rec, out := e.do(t, http.MethodGet, "/v1/miniapps/templates?topic="+topic, "", nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s: %d %s", topic, rec.Code, rec.Body.String())
		}
		items, _ := out["items"].([]any)
		if len(items) != 3 {
			t.Fatalf("%s templates = %d", topic, len(items))
		}
		id := items[0].(map[string]any)["id"].(string)
		rec, _ = e.do(t, http.MethodPost, "/v1/miniapps/templates/"+id+"/run", "", map[string]any{})
		if rec.Code != http.StatusOK {
			t.Fatalf("anon template run %s: %d %s", id, rec.Code, rec.Body.String())
		}
	}
	rec, out := e.do(t, http.MethodGet, "/v1/miniapps/catalog?topic=fishing", "", nil)
	if rec.Code != http.StatusOK || out["generation"] != false {
		t.Fatalf("catalog: %d %v", rec.Code, out)
	}
	if rec, _ := e.do(t, http.MethodGet, "/v1/miniapps/templates?topic=crypto", "", nil); rec.Code != http.StatusBadRequest {
		t.Fatalf("bad topic: %d", rec.Code)
	}
}

func TestMiniAppPrivateRequiresAuth(t *testing.T) {
	e, _ := newMiniAppEnv(t, nil)
	paths := []struct{ m, p string }{
		{http.MethodGet, "/v1/miniapps?topic=money"},
		{http.MethodPost, "/v1/miniapps/generate"},
		{http.MethodGet, "/v1/miniapps/gens/req-00000001"},
		{http.MethodPost, "/v1/miniapps/from-template"},
		{http.MethodPost, "/v1/miniapps/x/run"},
		{http.MethodDelete, "/v1/miniapps/x"},
	}
	for _, p := range paths {
		if rec, _ := e.do(t, p.m, p.p, "", map[string]any{}); rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s %s without token: %d", p.m, p.p, rec.Code)
		}
	}
}

func TestMiniAppGenerateFlowAndLedger(t *testing.T) {
	l := &scriptLLM{}
	e, svc := newMiniAppEnv(t, l)
	// 测试里数据源离线 → 试运行会报问题触发修复；脚本重复同一个 spec，最后一轮带警告接受。
	env := specEnvelope(t, svc, "fishing")
	l.outs = []string{env, env, env, env}
	uid, tok := e.user(t, 6)
	body := map[string]any{"request_id": "req-api-0001", "topic": "fishing", "message": "比较几个水库"}
	rec, out := e.do(t, http.MethodPost, "/v1/miniapps/generate", tok, body)
	if rec.Code != http.StatusOK {
		t.Fatalf("generate: %d %s", rec.Code, rec.Body.String())
	}
	gen := out["gen"].(map[string]any)
	if gen["outcome"] != "spec" || out["balance"].(float64) != 1 {
		t.Fatalf("gen=%v balance=%v", gen, out["balance"])
	}
	appID := gen["result"].(map[string]any)["app_uuid"].(string)
	// 重放：不重复扣费。
	rec, out = e.do(t, http.MethodPost, "/v1/miniapps/generate", tok, body)
	if rec.Code != http.StatusOK || out["balance"].(float64) != 1 || out["gen"].(map[string]any)["replayed"] != true {
		t.Fatalf("replay: %d %v", rec.Code, out)
	}
	var reasons []string
	_ = e.st.DB.Select(&reasons, "SELECT reason FROM credit_ledger WHERE user_id=? ORDER BY id", uid)
	if len(reasons) != 1 || reasons[0] != "fishing.miniapp.create" {
		t.Fatalf("ledger = %v", reasons)
	}
	// 余额不足（修改需要 2，余额 1）。
	rec, out = e.do(t, http.MethodPost, "/v1/miniapps/generate", tok,
		map[string]any{"request_id": "req-api-0002", "topic": "fishing", "message": "改一下", "app_uuid": appID})
	if rec.Code != http.StatusPaymentRequired {
		t.Fatalf("insufficient: %d %v", rec.Code, out)
	}
	// 挂载、列表、运行、轮询。
	if rec, _ := e.do(t, http.MethodPost, "/v1/miniapps/"+appID+"/mount", tok, map[string]any{"card_size": "large"}); rec.Code != http.StatusOK {
		t.Fatalf("mount: %d", rec.Code)
	}
	rec, out = e.do(t, http.MethodGet, "/v1/miniapps?topic=fishing", tok, nil)
	items := out["items"].([]any)
	if rec.Code != http.StatusOK || len(items) != 1 || items[0].(map[string]any)["card_size"] != "large" {
		t.Fatalf("list: %d %v", rec.Code, out)
	}
	if rec, _ := e.do(t, http.MethodPost, "/v1/miniapps/"+appID+"/run", tok, nil); rec.Code != http.StatusOK {
		t.Fatalf("run: %d", rec.Code)
	}
	if rec, out := e.do(t, http.MethodGet, "/v1/miniapps/gens/req-api-0001", tok, nil); rec.Code != http.StatusOK || out["gen"] == nil {
		t.Fatalf("poll: %d", rec.Code)
	}
	// 别人拿不到。
	_, tok2 := e.user(t, 0)
	if rec, _ := e.do(t, http.MethodGet, "/v1/miniapps/"+appID, tok2, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("cross user get: %d", rec.Code)
	}
	if rec, _ := e.do(t, http.MethodGet, "/v1/miniapps/gens/req-api-0001", tok2, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("cross user gen: %d", rec.Code)
	}
	// 免费从模板复制。
	tid := svc.Templates("money")[0].ID
	if rec, _ := e.do(t, http.MethodPost, "/v1/miniapps/from-template", tok2, map[string]any{"template_id": tid}); rec.Code != http.StatusOK {
		t.Fatalf("from template: %d", rec.Code)
	}
}

func TestMiniAppRefundViaAPI(t *testing.T) {
	l := &scriptLLM{outs: []string{`{"action":"ask","message":"哪个品种？","questions":[{"q":"品种","options":["豆粕","菜粕"]}]}`}}
	e, _ := newMiniAppEnv(t, l)
	uid, tok := e.user(t, 5)
	rec, out := e.do(t, http.MethodPost, "/v1/miniapps/generate", tok,
		map[string]any{"request_id": "req-api-0003", "topic": "money", "message": "价差"})
	if rec.Code != http.StatusOK {
		t.Fatalf("%d %s", rec.Code, rec.Body.String())
	}
	if out["balance"].(float64) != 5 || out["gen"].(map[string]any)["refunded"] != true {
		t.Fatalf("not refunded: %v", out)
	}
	var reasons []string
	_ = e.st.DB.Select(&reasons, "SELECT reason FROM credit_ledger WHERE user_id=? ORDER BY id", uid)
	if len(reasons) != 2 || reasons[0] != "miniapp.create" || reasons[1] != "miniapp.refund" {
		t.Fatalf("ledger = %v", reasons)
	}
}
