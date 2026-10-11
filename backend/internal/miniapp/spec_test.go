package miniapp

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
)

func TestTemplatesValidateAndDryRun(t *testing.T) {
	d := newTestDeps(t)
	tpls, errs := LoadTemplates(d.reg)
	for _, e := range errs {
		t.Error(e)
	}
	if len(tpls) != 6 {
		t.Fatalf("want 6 templates, got %d", len(tpls))
	}
	r := &Runner{F: NewFetcher(d.reg, FetcherOptions{})}
	for _, tp := range tpls {
		rep := r.DryRun(context.Background(), tp.compiled, 0, "ip:test")
		if len(rep.Problem) > 0 {
			t.Errorf("%s dry-run problems: %v", tp.ID, rep.Problem)
		}
	}
}

func mustSpec(t *testing.T, s string) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal([]byte(s), &m); err != nil {
		t.Fatal(err)
	}
	return m
}

const okSpec = `{"meta":{"title":"测试","icon":"apps"},"inputs":{"n":{"type":"number","label":"数量","default":2}},
 "computed":{"double":"inputs.n * 2"},
 "layout":{"type":"column","children":[{"type":"input","bind":"n"},{"type":"stat","label":"两倍","value":"=double"}]}}`

func TestValidateOKAndNormalizes(t *testing.T) {
	d := newTestDeps(t)
	c, issues := Validate(mustSpec(t, okSpec), "fishing", d.reg)
	if len(issues) > 0 {
		t.Fatal(issues)
	}
	meta := c.Raw["meta"].(map[string]any)
	if c.Raw["schema"] != SchemaID || c.Raw["topic"] != "fishing" || meta["disclaimer"] != Disclaimer("fishing") ||
		meta["card_size"] != "medium" || c.Raw["min_renderer"] != 1.0 {
		t.Fatalf("not normalized: %v", c.Raw)
	}
	if rf := c.Raw["refresh"].(map[string]any); rf["on_open"] != true || len(rf) != 1 {
		t.Fatalf("refresh %v", rf)
	}
}

func TestValidateRejects(t *testing.T) {
	d := newTestDeps(t)
	cases := map[string]struct {
		spec, topic, want string
	}{
		"unknown component": {`{"meta":{"title":"x"},"layout":{"type":"webview","url":"https://evil"}}`, "money", "不支持的组件"},
		"unknown top key":   {`{"meta":{"title":"x"},"script":"alert(1)","layout":{"type":"text","text":"a"}}`, "money", "不支持的顶层字段"},
		"wrong topic":       {`{"topic":"fishing","meta":{"title":"x"},"layout":{"type":"text","text":"a"}}`, "money", "当前主题"},
		"source other topic": {`{"meta":{"title":"x"},"data":{"f":{"source":"fishing.forecast","params":{"place":"千岛湖"}}},
			"layout":{"type":"text","text":"${data.f.place}"}}`, "money", "不属于当前主题"},
		"money source in fishing": {`{"meta":{"title":"x"},"data":{"q":{"source":"futures.dominant","params":{"product":"P"}}},
			"layout":{"type":"text","text":"a"}}`, "fishing", "不属于当前主题"},
		"unknown source": {`{"meta":{"title":"x"},"data":{"q":{"source":"http.get","params":{}}},"layout":{"type":"text","text":"a"}}`, "money", "没有数据源"},
		"unknown param":  {`{"meta":{"title":"x"},"data":{"q":{"source":"news.cn","params":{"query":"a","url":"x"}}},"layout":{"type":"text","text":"a"}}`, "money", "没有参数 url"},
		"missing param":  {`{"meta":{"title":"x"},"data":{"q":{"source":"news.cn","params":{}}},"layout":{"type":"text","text":"a"}}`, "money", "必填"},
		"bad expr":       {`{"meta":{"title":"x"},"layout":{"type":"stat","value":"=1 +"}}`, "money", "表达式错误"},
		"unknown func":   {`{"meta":{"title":"x"},"layout":{"type":"stat","value":"=fetch('http://x')"}}`, "money", "不支持的函数"},
		"unknown root":   {`{"meta":{"title":"x"},"layout":{"type":"stat","value":"=window.location"}}`, "money", "未知的名字"},
		"missing data":   {`{"meta":{"title":"x"},"layout":{"type":"stat","value":"=data.q.last"}}`, "money", "data 里没有"},
		"banned money":   {`{"meta":{"title":"建议买入提醒"},"layout":{"type":"text","text":"a"}}`, "money", "不允许的词"},
		"banned in tpl":  {`{"meta":{"title":"x"},"layout":{"type":"text","text":"明天必涨 ${1}"}}`, "money", "不允许的词"},
		"banned fishing": {`{"meta":{"title":"电鱼神器"},"layout":{"type":"text","text":"a"}}`, "fishing", "不允许的词"},
		"items not expr": {`{"meta":{"title":"x"},"layout":{"type":"list","items":"abc","item":{"type":"text","text":"a"}}}`, "money", "以 = 开头"},
		"bad input ref":  {`{"meta":{"title":"x"},"layout":{"type":"input","bind":"nope"}}`, "money", "inputs 里没有"},
		"computed cycle": {`{"meta":{"title":"x"},"computed":{"a":"b+1","b":"a+1"},"layout":{"type":"text","text":"a"}}`, "money", "循环"},
		"data cycle": {`{"meta":{"title":"x"},"data":{"a":{"source":"futures.quote","params":{"ts_code":"=data.b.ts_code"}},
			"b":{"source":"futures.quote","params":{"ts_code":"=data.a.ts_code"}}},"layout":{"type":"text","text":"a"}}`, "money", "循环依赖"},
		"data too deep": {`{"meta":{"title":"x"},"data":{"a":{"source":"futures.dominant","params":{"product":"P"}},
			"b":{"source":"futures.quote","params":{"ts_code":"=data.a.ts_code"}},
			"c":{"source":"market.daily_bars","params":{"symbol":"=data.b.ts_code"}}},"layout":{"type":"text","text":"a"}}`, "money", "层级太深"},
		"no layout":    {`{"meta":{"title":"x"}}`, "money", "缺少 layout"},
		"title long":   {`{"meta":{"title":"一二三四五六七八九十一二三四五六七八九十一"},"layout":{"type":"text","text":"a"}}`, "money", "太长"},
		"bad icon":     {`{"meta":{"title":"x","icon":"rocket"},"layout":{"type":"text","text":"a"}}`, "money", "只能是：apps"},
		"enum default": {`{"meta":{"title":"x"},"inputs":{"a":{"type":"enum","label":"a","options":["x"],"default":"y"}},"layout":{"type":"text","text":"a"}}`, "money", "options 之一"},
		"html prop":    {`{"meta":{"title":"x"},"layout":{"type":"text","text":"a","html":"<b>x</b>"}}`, "money", "没有属性 html"},
	}
	for name, tc := range cases {
		_, issues := Validate(mustSpec(t, tc.spec), tc.topic, d.reg)
		found := false
		for _, i := range issues {
			if strings.Contains(i.Msg, tc.want) {
				found = true
			}
		}
		if !found {
			t.Errorf("%s: want issue containing %q, got %v", name, tc.want, issues)
		}
	}
}

func TestValidateLimits(t *testing.T) {
	d := newTestDeps(t)
	var children []string
	for i := 0; i < MaxComponents+1; i++ {
		children = append(children, `{"type":"text","text":"a"}`)
	}
	spec := `{"meta":{"title":"x"},"layout":{"type":"column","children":[` + strings.Join(children, ",") + `]}}`
	if _, issues := Validate(mustSpec(t, spec), "money", d.reg); len(issues) == 0 {
		t.Fatal("want too many components")
	}
	big := `{"meta":{"title":"x"},"layout":{"type":"text","text":"` + strings.Repeat("a", MaxSpecBytes) + `"}}`
	if _, issues := ValidateJSON([]byte(big), "money", d.reg); len(issues) == 0 {
		t.Fatal("want too big")
	}
	if _, issues := ValidateJSON([]byte(`not json`), "money", d.reg); len(issues) == 0 {
		t.Fatal("want parse error")
	}
}

// FuzzValidate：任意输入都不能让校验器 panic。
func FuzzValidate(f *testing.F) {
	f.Add(okSpec)
	f.Add(`{"layout":{"type":"list","items":"=x","item":{"type":"list","items":"=y","item":{}}}}`)
	f.Add(`{"data":{"a":{"source":"news.cn","each":"=[1,2]","params":{"query":"=item"}}}}`)
	reg := BuiltinRegistry(BuiltinDeps{Tools: &fakeTools{}, History: fakeHistory})
	f.Fuzz(func(t *testing.T, s string) {
		_, _ = ValidateJSON([]byte(s), "money", reg)
	})
}
