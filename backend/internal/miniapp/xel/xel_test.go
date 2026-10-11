package xel

import (
	"encoding/json"
	"math"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"
)

type confCase struct {
	Expr *string `json:"expr"`
	Tpl  *string `json:"tpl"`
	Want any     `json:"want"`
	Err  bool    `json:"err"`
}

type confFile struct {
	Now   string         `json:"now"`
	Vars  map[string]any `json:"vars"`
	Cases []confCase     `json:"cases"`
}

func loadConf(t *testing.T) confFile {
	t.Helper()
	b, err := os.ReadFile("testdata/conformance.json")
	if err != nil {
		t.Fatal(err)
	}
	var c confFile
	if err := json.Unmarshal(b, &c); err != nil {
		t.Fatal(err)
	}
	return c
}

func near(a, b any) bool {
	fa, ok1 := a.(float64)
	fb, ok2 := b.(float64)
	if ok1 && ok2 {
		return fa == fb || math.Abs(fa-fb) < 1e-9*math.Max(1, math.Abs(fb))
	}
	aa, ok1 := a.([]any)
	bb, ok2 := b.([]any)
	if ok1 && ok2 {
		if len(aa) != len(bb) {
			return false
		}
		for i := range aa {
			if !near(aa[i], bb[i]) {
				return false
			}
		}
		return true
	}
	return reflect.DeepEqual(a, b)
}

// TestConformance 与 Dart 端 test/miniapp_xel_test.dart 共用同一份用例。
func TestConformance(t *testing.T) {
	c := loadConf(t)
	now, err := time.Parse(time.RFC3339, c.Now)
	if err != nil {
		t.Fatal(err)
	}
	env := &Env{Vars: c.Vars, Now: func() time.Time { return now }}
	for i, tc := range c.Cases {
		switch {
		case tc.Expr != nil:
			e, err := Compile(*tc.Expr)
			if tc.Err {
				if err == nil {
					t.Errorf("#%d %q: want compile error", i, *tc.Expr)
				}
				continue
			}
			if err != nil {
				t.Errorf("#%d %q: compile: %v", i, *tc.Expr, err)
				continue
			}
			got, err := e.Eval(env)
			if err != nil {
				t.Errorf("#%d %q: eval: %v", i, *tc.Expr, err)
				continue
			}
			if !near(got, tc.Want) {
				t.Errorf("#%d %q = %#v, want %#v", i, *tc.Expr, got, tc.Want)
			}
		case tc.Tpl != nil:
			tp, err := CompileTemplate(*tc.Tpl)
			if tc.Err {
				if err == nil {
					t.Errorf("#%d tpl %q: want error", i, *tc.Tpl)
				}
				continue
			}
			if err != nil {
				t.Errorf("#%d tpl %q: %v", i, *tc.Tpl, err)
				continue
			}
			got, _ := tp.Render(env)
			if got != tc.Want {
				t.Errorf("#%d tpl %q = %q, want %q", i, *tc.Tpl, got, tc.Want)
			}
		}
	}
}

func TestLimits(t *testing.T) {
	if _, err := Compile(strings.Repeat("1+", 300) + "1"); err == nil {
		t.Fatal("want too long")
	}
	if _, err := Compile(strings.Repeat("[", 40) + "1" + strings.Repeat("]", 40)); err == nil {
		t.Fatal("want too deep")
	}
	// 嵌套 map 撑爆步数。
	big := make([]any, 200)
	for i := range big {
		big[i] = float64(i)
	}
	e, err := Compile("map(xs, sum(map(xs, item + 1)))")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := e.Eval(&Env{Vars: map[string]any{"xs": big}}); err != ErrSteps {
		t.Fatalf("want ErrSteps, got %v", err)
	}
	huge := make([]any, MaxArray+1)
	e, _ = Compile("count(xs)")
	if _, err := e.Eval(&Env{Vars: map[string]any{"xs": huge}}); err == nil {
		t.Fatal("want array too big")
	}
}

func TestRootsAndDataRefs(t *testing.T) {
	e, err := Compile("data.main.ts_code + px.x + data['wx'].a + map(inputs.places, item.name)")
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(e.DataRefs(), ","); got != "main,wx" {
		t.Fatalf("data refs %s", got)
	}
	if got := strings.Join(e.Roots(), ","); got != "data,inputs,item,px" {
		t.Fatalf("roots %s", got)
	}
}

func FuzzCompileEval(f *testing.F) {
	for _, s := range []string{"1+2", "map(xs, item*2)", "a ? b : c", "fmt(x, 2)", "'${'", "{'a':[1,2]}"} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, src string) {
		e, err := Compile(src)
		if err != nil {
			return
		}
		_, _ = e.Eval(&Env{Vars: map[string]any{"xs": []any{1.0, 2.0}, "x": 1.5}})
		tp, err := CompileTemplate(src)
		if err == nil {
			_, _ = tp.Render(&Env{})
		}
	})
}
