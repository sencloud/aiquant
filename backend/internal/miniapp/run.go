package miniapp

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/sencloud/finme-backend/internal/miniapp/xel"
)

// ResolveInputs 把用户保存的参数与默认值合并，并按定义校验 / 纠正类型。
// 不合法的值回落到默认值，不报错（参数是用户自己的，坏值不该让小应用打不开）。
func ResolveInputs(c *Compiled, user map[string]any, now time.Time) map[string]any {
	out := map[string]any{}
	for k, d := range c.Inputs {
		v, ok := user[k]
		if !ok || !inputOK(d, v) {
			v = d.Default
		}
		if d.Type == "number" {
			f, _ := v.(float64)
			if d.Min != nil && f < *d.Min {
				f = *d.Min
			}
			if d.Max != nil && f > *d.Max {
				f = *d.Max
			}
			v = f
		}
		if d.Type == "date" {
			if s, _ := v.(string); s == "" {
				v = now.In(shanghai).Format("2006-01-02")
			}
		}
		out[k] = v
	}
	return out
}

func inputOK(d *InputDef, v any) bool {
	switch d.Type {
	case "number":
		_, ok := num(v)
		return ok
	case "text":
		s, ok := v.(string)
		return ok && utf8.RuneCountInString(s) <= 40
	case "enum":
		s, ok := v.(string)
		return ok && contains(d.Options, s)
	case "date":
		s, ok := v.(string)
		if !ok {
			return false
		}
		if s == "" {
			return true
		}
		_, err := time.Parse("2006-01-02", s)
		return err == nil
	case "bool":
		_, ok := v.(bool)
		return ok
	case "list":
		arr, ok := v.([]any)
		if !ok || len(arr) > d.MaxItems {
			return false
		}
		for _, e := range arr {
			m, ok := e.(map[string]any)
			if !ok {
				return false
			}
			for k, fv := range m {
				switch d.Fields[k] {
				case "text":
					s, ok := fv.(string)
					if !ok || utf8.RuneCountInString(s) > 30 {
						return false
					}
				case "number":
					if _, ok := num(fv); !ok {
						return false
					}
				default:
					return false
				}
			}
		}
		return true
	}
	return false
}

// SourceStat 是一次运行里单个数据源调用的统计（落 mini_app_runs.sources_json）。
type SourceStat struct {
	Alias  string `json:"alias"`
	Source string `json:"source"`
	Cached bool   `json:"cached,omitempty"`
	Ms     int64  `json:"ms"`
	Error  string `json:"error,omitempty"`
}

// RunResult 是一次取数结果；客户端用 Data 求值 computed 并渲染。
type RunResult struct {
	Inputs    map[string]any    `json:"inputs"`
	Data      map[string]any    `json:"data"`
	Errors    map[string]string `json:"errors,omitempty"`
	FetchedAt int64             `json:"fetched_at"`
	Cost      int               `json:"cost"`
	Stats     []SourceStat      `json:"-"`
}

// Runner 执行数据绑定。
type Runner struct {
	F   *Fetcher
	Now func() time.Time
}

func (r *Runner) now() time.Time {
	if r.Now != nil {
		return r.Now()
	}
	return time.Now()
}

// Run 按层级取数：同一层并发，第 1 层可以引用第 0 层的结果。
func (r *Runner) Run(ctx context.Context, c *Compiled, userInputs, state map[string]any, uid int64, who string) *RunResult {
	now := r.now()
	res := &RunResult{
		Inputs:    ResolveInputs(c, userInputs, now),
		Data:      map[string]any{},
		Errors:    map[string]string{},
		FetchedAt: now.UnixMilli(),
	}
	if state == nil {
		state = map[string]any{}
	}
	var mu sync.Mutex
	for _, level := range c.Levels {
		var wg sync.WaitGroup
		for _, alias := range level {
			b := c.Bindings[alias]
			wg.Add(1)
			go func(b *Binding) {
				defer wg.Done()
				mu.Lock()
				env := &xel.Env{Vars: map[string]any{"inputs": res.Inputs, "data": copyMap(res.Data), "state": state},
					Now: func() time.Time { return now }}
				mu.Unlock()
				val, errs, stats, cost := r.runBinding(ctx, b, env, uid, who)
				mu.Lock()
				res.Data[b.Alias] = val
				for k, e := range errs {
					res.Errors[k] = e
				}
				res.Stats = append(res.Stats, stats...)
				res.Cost += cost
				mu.Unlock()
			}(b)
		}
		wg.Wait()
	}
	sort.Slice(res.Stats, func(i, j int) bool { return res.Stats[i].Alias < res.Stats[j].Alias })
	if len(res.Errors) == 0 {
		res.Errors = nil
	}
	return res
}

func copyMap(m map[string]any) map[string]any {
	out := make(map[string]any, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}

func (r *Runner) runBinding(ctx context.Context, b *Binding, env *xel.Env, uid int64, who string) (any, map[string]string, []SourceStat, int) {
	errs := map[string]string{}
	var stats []SourceStat
	cost := 0
	one := func(key string, env *xel.Env) any {
		params := map[string]any{}
		for k, pv := range b.Params {
			if pv.Expr == nil {
				params[k] = pv.Lit
				continue
			}
			v, err := pv.Expr.Eval(env)
			if err != nil {
				errs[key] = fmt.Sprintf("参数 %s 计算失败：%v", k, err)
				return nil
			}
			if v == nil {
				continue
			}
			params[k] = v
		}
		st := SourceStat{Alias: key, Source: b.Source.ID}
		fr, err := r.F.Fetch(ctx, b.Source, Call{UserID: uid, Params: params}, who)
		if err != nil {
			st.Error = err.Error()
			stats = append(stats, st)
			errs[key] = err.Error()
			return nil
		}
		st.Cached, st.Ms = fr.Cached, fr.Took.Milliseconds()
		stats = append(stats, st)
		cost += fr.Cost
		return fr.Value
	}
	if b.Each == nil {
		return one(b.Alias, env), errs, stats, cost
	}
	ev, err := b.Each.Eval(env)
	if err != nil {
		errs[b.Alias] = "each 计算失败：" + err.Error()
		return []any{}, errs, stats, cost
	}
	arr, _ := ev.([]any)
	if len(arr) > MaxEach {
		arr = arr[:MaxEach]
	}
	out := make([]any, len(arr))
	for i, item := range arr {
		vars := copyMap(env.Vars)
		vars["item"] = item
		vars["index"] = float64(i)
		out[i] = one(fmt.Sprintf("%s[%d]", b.Alias, i), &xel.Env{Vars: vars, Now: env.Now})
	}
	return out, errs, stats, cost
}

// EvalComputed 在服务端求值 computed（试运行用；客户端渲染时自己再算一遍）。
func EvalComputed(c *Compiled, vars map[string]any, now time.Time) (map[string]any, map[string]string) {
	out := map[string]any{}
	errs := map[string]string{}
	env := &xel.Env{Vars: vars, Now: func() time.Time { return now }}
	for _, k := range c.Computed {
		e := c.Exprs["computed."+k]
		if e == nil {
			continue
		}
		v, err := e.Eval(env)
		if err != nil {
			errs[k] = err.Error()
		}
		vars[k] = v
		out[k] = v
	}
	return out, errs
}

// ─── 试运行 ─────────────────────────────────────────────────────────────

// DryRunReport 是试运行结果。
type DryRunReport struct {
	Run     *RunResult
	Problem []string // 需要模型修复的问题（数据源报错、关键表达式为空）
	Shapes  map[string]any
}

// DryRun 用默认参数取一次数，并检查关键表达式（列表 / 表格 / 图表 / K 线 / 数字）结果不为空。
// 只把“结构摘要”（字段名、类型、条数）回给模型，不回传任何原文，避免数据里夹带指令。
func (r *Runner) DryRun(ctx context.Context, c *Compiled, uid int64, who string) *DryRunReport {
	run := r.Run(ctx, c, nil, nil, uid, who)
	rep := &DryRunReport{Run: run, Shapes: map[string]any{}}
	failed := map[string]bool{}
	keys := make([]string, 0, len(run.Errors))
	for k := range run.Errors {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		rep.Problem = append(rep.Problem, fmt.Sprintf("数据绑定 data.%s 取数失败：%s", k, run.Errors[k]))
		failed[strings.SplitN(k, "[", 2)[0]] = true
	}
	for alias, v := range run.Data {
		rep.Shapes[alias] = Shape(v, 0)
	}
	vars := map[string]any{"inputs": run.Inputs, "data": run.Data, "state": map[string]any{}}
	cvals, cerrs := EvalComputed(c, vars, r.now())
	for _, k := range c.Computed {
		e := c.Exprs["computed."+k]
		if msg, ok := cerrs[k]; ok {
			rep.Problem = append(rep.Problem, fmt.Sprintf("computed.%s 计算失败：%s", k, msg))
			continue
		}
		if e == nil || cvals[k] != nil || c.UserScoped {
			continue
		}
		skip := false
		for _, a := range e.DataRefs() {
			if failed[a] {
				skip = true
			}
		}
		if !skip {
			rep.Problem = append(rep.Problem, fmt.Sprintf("computed.%s = %q 结果为 null，检查字段名是否与数据结构一致", k, e.Src))
		}
	}
	env := &xel.Env{Vars: vars, Now: r.now}
	paths := make([]string, 0, len(c.Checks))
	for p := range c.Checks {
		paths = append(paths, p)
	}
	sort.Strings(paths)
	for _, p := range paths {
		e := c.Checks[p]
		// 依赖的数据源已经失败的，不重复报“为空”。
		skip := false
		for _, a := range e.DataRefs() {
			if failed[a] {
				skip = true
			}
		}
		if skip {
			continue
		}
		v, err := e.Eval(env)
		if err != nil {
			rep.Problem = append(rep.Problem, fmt.Sprintf("%s 的表达式 %q 计算失败：%v", p, e.Src, err))
			continue
		}
		if isEmpty(v) && !c.UserScoped {
			rep.Problem = append(rep.Problem, fmt.Sprintf("%s 的表达式 %q 结果为空，检查字段名是否与数据结构一致", p, e.Src))
		}
	}
	return rep
}

func isEmpty(v any) bool {
	switch x := v.(type) {
	case nil:
		return true
	case []any:
		return len(x) == 0
	case string:
		return x == ""
	case float64:
		return math.IsNaN(x)
	}
	return false
}

// Shape 返回值的结构摘要：对象列出字段与类型，数组给出长度与首元素结构；不含任何原文。
func Shape(v any, depth int) any {
	if depth > 4 {
		return "…"
	}
	switch x := v.(type) {
	case nil:
		return "null"
	case bool:
		return "boolean"
	case float64:
		return "number"
	case string:
		return "string"
	case []any:
		out := map[string]any{"array_len": len(x)}
		if len(x) > 0 {
			out["item"] = Shape(x[0], depth+1)
		}
		return out
	case map[string]any:
		out := map[string]any{}
		for k, e := range x {
			out[k] = Shape(e, depth+1)
		}
		return out
	}
	return "unknown"
}
