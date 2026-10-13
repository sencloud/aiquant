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

// 兴趣圈（方案五）新增的四个主题：id 必须能解析、必须有人设与首页提问，
// 且不允许它们暴露任何行情 / 钓鱼工具。
func TestInterestCirclesRegistered(t *testing.T) {
	for _, id := range []string{Cat, Coffee, Camping, Hanfu} {
		tp, err := Resolve(id)
		if err != nil {
			t.Fatalf("Resolve(%q) = %v", id, err)
		}
		if tp.Name == "" || tp.Role == "" {
			t.Fatalf("%s: 缺 name / role", id)
		}
		if len(tp.Personas) == 0 || tp.Persona(tp.DefaultPersona).ID != tp.DefaultPersona {
			t.Fatalf("%s: 默认人设没落在人设表里", id)
		}
		if len(tp.HomeSuggestions) == 0 {
			t.Fatalf("%s: 没有首页提问", id)
		}
		if tp.AcceptSystemHint {
			t.Fatalf("%s: 不应接受客户端 system_hint", id)
		}
		if !strings.HasPrefix(tp.ChatReason, id+".") {
			t.Fatalf("%s: ChatReason = %q", id, tp.ChatReason)
		}
		// 客户端换圈时可能还带着别的人设 id，必须回落到本主题默认人设。
		if p := tp.Persona("default"); p.ID != tp.DefaultPersona {
			t.Fatalf("%s: 未知人设未回落，得到 %q", id, p.ID)
		}
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
	// 养猫 / 咖啡 / 汉服不联网查任何东西；露营只查天气。
	for _, id := range []string{Cat, Coffee, Hanfu} {
		if got := MustGet(id).AllowedTools(all); len(got) != 0 {
			t.Fatalf("%s 不该暴露工具，得到 %v", id, got)
		}
	}
	if got := strings.Join(MustGet(Camping).AllowedTools(all), ","); got != "get_region_weather" {
		t.Fatalf("camping tools = %s", got)
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
