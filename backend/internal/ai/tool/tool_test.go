package tool

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
)

type echoTool struct{ name string }

func (e echoTool) Spec() Spec { return Spec{Name: e.name, Description: e.name} }
func (e echoTool) Run(context.Context, json.RawMessage) (string, error) {
	return `{"ok":"` + e.name + `"}`, nil
}

func TestSubsetOnlyExposesAndDispatchesWhitelist(t *testing.T) {
	r := New()
	for _, n := range []string{"get_quote", "get_region_weather", "get_fishing_forecast"} {
		r.MustRegister(echoTool{n})
	}
	v := r.Subset("fishing", []string{"get_region_weather", "get_fishing_forecast", "not_registered"})

	if got := strings.Join(v.Names(), ","); got != "get_fishing_forecast,get_region_weather" {
		t.Fatalf("names = %s", got)
	}
	list := v.ToolListJSON()
	if len(list) != 2 {
		t.Fatalf("tool list len = %d, want 2", len(list))
	}
	for _, item := range list {
		fn := item["function"].(map[string]any)
		if fn["name"] == "get_quote" {
			t.Fatal("get_quote leaked into fishing tool list")
		}
	}
	if out := v.Dispatch(context.Background(), "get_region_weather", `{}`); !strings.Contains(out, `"ok"`) {
		t.Fatalf("whitelisted dispatch failed: %s", out)
	}
	out := v.Dispatch(context.Background(), "get_quote", `{}`)
	if !strings.Contains(out, "not available in topic") || strings.Contains(out, `"ok"`) {
		t.Fatalf("get_quote must be rejected in fishing view, got %s", out)
	}
	if out := v.Dispatch(context.Background(), "nope", `{}`); !strings.Contains(out, "unknown tool") {
		t.Fatalf("unknown tool message = %s", out)
	}
	// 全集不受视图影响。
	if out := r.Dispatch(context.Background(), "get_quote", `{}`); !strings.Contains(out, `"ok"`) {
		t.Fatalf("full registry dispatch broken: %s", out)
	}
}
