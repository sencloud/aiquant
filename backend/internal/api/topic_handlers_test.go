package api

import (
	"net/http"
	"testing"
)

func TestMePreferredTopicRoundTrip(t *testing.T) {
	e := newTestEnv(t)
	_, tok := e.user(t, 10)

	rec, out := e.do(t, http.MethodGet, "/v1/me", tok, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /me %d: %s", rec.Code, rec.Body.String())
	}
	if _, ok := out["preferred_topic"]; ok {
		t.Fatalf("preferred_topic should be omitted when unset: %v", out)
	}

	rec, out = e.do(t, http.MethodPatch, "/v1/me", tok, map[string]any{"preferred_topic": "fishing"})
	if rec.Code != http.StatusOK || out["preferred_topic"] != "fishing" {
		t.Fatalf("PATCH fishing %d: %s", rec.Code, rec.Body.String())
	}
	_, out = e.do(t, http.MethodGet, "/v1/me", tok, nil)
	if out["preferred_topic"] != "fishing" {
		t.Fatalf("GET after PATCH = %v", out["preferred_topic"])
	}

	rec, _ = e.do(t, http.MethodPatch, "/v1/me", tok, map[string]any{"preferred_topic": "golf"})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("unknown topic should be 400, got %d", rec.Code)
	}
	// 只改昵称不影响主题。
	_, out = e.do(t, http.MethodPatch, "/v1/me", tok, map[string]any{"nickname": "钓友"})
	if out["preferred_topic"] != "fishing" {
		t.Fatalf("nickname patch cleared topic: %v", out)
	}
	// 未登录不能改。
	rec, _ = e.do(t, http.MethodPatch, "/v1/me", "", map[string]any{"preferred_topic": "money"})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous PATCH /me = %d", rec.Code)
	}
}

func TestHomeSuggestionsByTopic(t *testing.T) {
	e := newTestEnv(t)
	rec, out := e.do(t, http.MethodGet, "/v1/ai/home-suggestions?topic=fishing", "", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d", rec.Code)
	}
	qs, _ := out["questions"].([]any)
	if len(qs) == 0 || out["topic"] != "fishing" {
		t.Fatalf("fishing suggestions = %v", out)
	}
	// 不带 topic = 钱主题（Brief 未配置时空数组），老客户端行为不变。
	rec, out = e.do(t, http.MethodGet, "/v1/ai/home-suggestions", "", nil)
	if rec.Code != http.StatusOK || out["topic"] != nil {
		t.Fatalf("default suggestions = %d %v", rec.Code, out)
	}
	rec, _ = e.do(t, http.MethodGet, "/v1/ai/home-suggestions?topic=golf", "", nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("unknown topic = %d", rec.Code)
	}
}
