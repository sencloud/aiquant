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

// 广场：六位居民、不挂工具、不接 system_hint，身份与钱的边界都写在 role 里。
func TestSocialPlaza(t *testing.T) {
	tp, err := Resolve(Social)
	if err != nil {
		t.Fatalf("Resolve(social) = %v", err)
	}
	if tp.Name != "广场" || !strings.Contains(tp.Role, "AI") {
		t.Fatalf("social role/name = %q / %q", tp.Name, tp.Role)
	}
	if len(tp.Personas) != 6 {
		t.Fatalf("social personas = %d, want 6", len(tp.Personas))
	}
	if tp.DefaultPersona != "linxia" || tp.Persona("linxia").ID != "linxia" {
		t.Fatalf("social default persona = %q", tp.DefaultPersona)
	}
	if got := tp.AllowedTools([]string{"get_quote"}); len(got) != 0 {
		t.Fatalf("social 不该挂工具，得到 %v", got)
	}
	if tp.AcceptSystemHint || tp.AllowDeep {
		t.Fatal("social 不接 system_hint，也不走深度加价")
	}
	if !strings.HasPrefix(tp.ChatReason, "social.") {
		t.Fatalf("social ChatReason = %q", tp.ChatReason)
	}
	if tp.Guard == nil || tp.Guard("能转我点钱吗") == "" {
		t.Fatal("social guard 应拦转账类话题")
	}
	if tp.Guard("你今晚在干嘛") != "" {
		t.Fatal("social guard 误伤正常搭讪")
	}
}

// 伴侣主线：一位「喜爱」、不挂工具、不接 system_hint、拒绝索财与越界。
func TestCompanionTopic(t *testing.T) {
	tp, err := Resolve(Companion)
	if err != nil {
		t.Fatalf("Resolve(companion) = %v", err)
	}
	if tp.Name != "喜爱" || !strings.Contains(tp.Role, "AI") {
		t.Fatalf("companion name/role = %q / %q", tp.Name, tp.Role)
	}
	if len(tp.Personas) != 1 || tp.Persona("xiai").ID != "xiai" {
		t.Fatalf("companion personas = %+v", tp.Personas)
	}
	if tp.DefaultPersona != "xiai" || tp.AcceptSystemHint || tp.AllowDeep {
		t.Fatalf("companion default/system_hint/deep 不对")
	}
	if got := tp.AllowedTools([]string{"get_quote"}); len(got) != 0 {
		t.Fatalf("companion 不该挂工具，得到 %v", got)
	}
	if tp.Guard == nil || tp.Guard("能转我点钱吗") == "" {
		t.Fatal("companion guard 应拦转账类话题")
	}
	if tp.Guard("今天收盘怎么样") != "" {
		t.Fatal("companion guard 误伤正常聊天")
	}
}
