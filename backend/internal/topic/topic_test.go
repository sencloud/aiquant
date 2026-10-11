package topic

import (
	"errors"
	"strings"
	"testing"
)

func TestResolveDefaultsToMoney(t *testing.T) {
	tp, err := Resolve("")
	if err != nil || tp.ID != Money {
		t.Fatalf("Resolve(\"\") = %v, %v", tp, err)
	}
	if _, err := Resolve("stocks"); !errors.Is(err, ErrUnknownTopic) {
		t.Fatalf("unknown topic err = %v", err)
	}
	if !Valid("") || !Valid("fishing") || Valid("golf") {
		t.Fatal("Valid() mismatch")
	}
}

func TestToolWhitelists(t *testing.T) {
	all := []string{"get_quote", "search_instrument", "get_region_weather",
		"get_fishing_forecast", "get_fishing_regulations", "backtest_etf_rotation"}
	fish := strings.Join(MustGet(Fishing).AllowedTools(all), ",")
	if fish != "get_fishing_forecast,get_fishing_regulations,get_region_weather" {
		t.Fatalf("fishing tools = %s", fish)
	}
	money := MustGet(Money).AllowedTools(all)
	for _, n := range money {
		if n == "get_fishing_forecast" || n == "get_fishing_regulations" {
			t.Fatalf("money must not expose %s", n)
		}
	}
	if len(money) != 4 {
		t.Fatalf("money tools = %v", money)
	}
}

func TestMoneyPersonasMovedFromClient(t *testing.T) {
	m := MustGet(Money)
	if len(m.Personas) != 11 {
		t.Fatalf("money personas = %d, want 11", len(m.Personas))
	}
	if p := m.Persona("buffett"); !strings.Contains(p.Prompt, "巴菲特") {
		t.Fatalf("buffett prompt = %q", p.Prompt)
	}
	if p := m.Persona("does-not-exist"); p.ID != "default" {
		t.Fatalf("fallback persona = %q", p.ID)
	}
	if !m.AcceptSystemHint || MustGet(Fishing).AcceptSystemHint {
		t.Fatal("only money accepts system_hint")
	}
}

func TestFishingGuard(t *testing.T) {
	g := MustGet(Fishing).Guard
	if g("怎么用逆变器电鱼") == "" {
		t.Fatal("guard should flag 电鱼")
	}
	if g("秋天钓鲫鱼用什么饵") != "" {
		t.Fatal("guard false positive")
	}
}
