package xel

import (
	"errors"
	"math"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

type fnSpec struct {
	min, max int // max<0 表示不限
	// lazy 为 true 的函数自己求值参数（map/filter 等需要逐元素绑定 item）。
	lazy bool
	doc  string
}

// funcs 是白名单函数表（名字 → 参数个数）。实现见 call()。
var funcs = map[string]fnSpec{
	"round":        {1, 2, false, "round(x, n=0) 四舍五入到 n 位小数"},
	"floor":        {1, 1, false, "floor(x)"},
	"ceil":         {1, 1, false, "ceil(x)"},
	"abs":          {1, 1, false, "abs(x)"},
	"pow":          {2, 2, false, "pow(x, y)"},
	"sqrt":         {1, 1, false, "sqrt(x)"},
	"clamp":        {3, 3, false, "clamp(x, lo, hi)"},
	"min":          {1, -1, false, "min(数组) 或 min(a, b, ...)"},
	"max":          {1, -1, false, "max(数组) 或 max(a, b, ...)"},
	"sum":          {1, 2, true, "sum(数组[, 元素表达式或字段名])"},
	"avg":          {1, 2, true, "avg(数组[, 元素表达式或字段名])"},
	"count":        {1, 2, true, "count(数组[, 条件])"},
	"map":          {2, 2, true, "map(数组, 元素表达式或字段名)；元素里用 item、index"},
	"filter":       {2, 2, true, "filter(数组, 条件)；条件里用 item、index"},
	"sort_by":      {2, 3, true, "sort_by(数组, 元素表达式或字段名, 'asc'|'desc')"},
	"zip_with":     {3, 3, true, "zip_with(数组a, 数组b, 表达式)；表达式里用 x、y、index"},
	"len":          {1, 1, false, "len(数组 / 字符串 / 对象)"},
	"range":        {2, 2, false, "range(开始, 结束)：[开始, 结束) 的整数数组，最多 1000 个"},
	"group_sum":    {3, 3, true, "group_sum(数组, 分组字段或表达式, 数值字段或表达式)：[{key, value}]，按 value 降序"},
	"first":        {1, 1, false, "first(数组)"},
	"last":         {1, 1, false, "last(数组)"},
	"slice":        {2, 3, false, "slice(数组, 开始[, 结束])，负数从末尾数"},
	"reverse":      {1, 1, false, "reverse(数组)"},
	"join":         {1, 2, false, "join(数组, 分隔符=', ')"},
	"contains":     {2, 2, false, "contains(字符串或数组, 值)"},
	"fmt":          {1, 2, false, "fmt(x[, 小数位])：千分位"},
	"pct":          {1, 2, false, "pct(x, 小数位=2)：x 已是百分数，正数带 +"},
	"str":          {1, 1, false, "str(x)"},
	"num":          {1, 1, false, "num(x)：字符串转数字，失败为 null"},
	"today":        {0, 0, false, "today()：北京时间今天 'YYYY-MM-DD'"},
	"now":          {0, 0, false, "now()：当前毫秒时间戳"},
	"date":         {1, 1, false, "date(毫秒时间戳)：'YYYY-MM-DD'（北京时间）"},
	"date_add":     {2, 2, false, "date_add('YYYY-MM-DD', 天数)"},
	"month_start":  {0, 0, false, "month_start()：本月 1 日 0 点的毫秒时间戳（北京时间）"},
	"days_between": {2, 2, false, "days_between('YYYY-MM-DD', 'YYYY-MM-DD')"},
}

// FuncDocs 返回函数说明（排序），给生成 prompt 用。
func FuncDocs() []string {
	out := make([]string, 0, len(funcs))
	for _, f := range funcs {
		out = append(out, f.doc)
	}
	sort.Strings(out)
	return out
}

var errArray = errors.New("数组太大")

func (ev *evaluator) call(c callNode) (any, error) {
	f := funcs[c.name]
	if f.lazy {
		return ev.callLazy(c)
	}
	args := make([]any, len(c.args))
	for i, a := range c.args {
		v, err := ev.eval(a)
		if err != nil {
			return nil, err
		}
		args[i] = v
	}
	num := func(i int) (float64, bool) {
		if i >= len(args) {
			return 0, false
		}
		f, ok := args[i].(float64)
		return f, ok && !math.IsNaN(f)
	}
	switch c.name {
	case "round":
		x, ok := num(0)
		if !ok {
			return nil, nil
		}
		n := 0.0
		if len(args) > 1 {
			if n, ok = num(1); !ok {
				return nil, nil
			}
		}
		d := int(clampF(n, 0, 6))
		p := math.Pow10(d)
		return math.Round(x*p) / p, nil
	case "floor", "ceil", "abs", "sqrt":
		x, ok := num(0)
		if !ok {
			return nil, nil
		}
		switch c.name {
		case "floor":
			return math.Floor(x), nil
		case "ceil":
			return math.Ceil(x), nil
		case "abs":
			return math.Abs(x), nil
		}
		if x < 0 {
			return nil, nil
		}
		return math.Sqrt(x), nil
	case "pow":
		x, ok1 := num(0)
		y, ok2 := num(1)
		if !ok1 || !ok2 {
			return nil, nil
		}
		r := math.Pow(x, y)
		if math.IsNaN(r) || math.IsInf(r, 0) {
			return nil, nil
		}
		return r, nil
	case "clamp":
		x, ok1 := num(0)
		lo, ok2 := num(1)
		hi, ok3 := num(2)
		if !ok1 || !ok2 || !ok3 {
			return nil, nil
		}
		return clampF(x, lo, hi), nil
	case "min", "max":
		vals := args
		if len(args) == 1 {
			if arr, ok := args[0].([]any); ok {
				vals = arr
			}
		}
		var best float64
		found := false
		for _, v := range vals {
			f, ok := v.(float64)
			if !ok || math.IsNaN(f) {
				continue
			}
			if !found || (c.name == "min" && f < best) || (c.name == "max" && f > best) {
				best, found = f, true
			}
		}
		if !found {
			return nil, nil
		}
		return best, nil
	case "len":
		switch x := args[0].(type) {
		case string:
			return float64(utf8.RuneCountInString(x)), nil
		case []any:
			return float64(len(x)), nil
		case map[string]any:
			return float64(len(x)), nil
		}
		return 0.0, nil
	case "range":
		a, ok1 := num(0)
		b, ok2 := num(1)
		if !ok1 || !ok2 {
			return nil, nil
		}
		a, b = math.Trunc(a), math.Trunc(b)
		if b-a > 1000 {
			b = a + 1000
		}
		out := []any{}
		for x := a; x < b; x++ {
			out = append(out, x)
		}
		return out, nil
	case "first", "last":
		arr, ok := args[0].([]any)
		if !ok || len(arr) == 0 {
			return nil, nil
		}
		if c.name == "first" {
			return arr[0], nil
		}
		return arr[len(arr)-1], nil
	case "slice":
		arr, ok := args[0].([]any)
		if !ok {
			return nil, nil
		}
		s, ok := num(1)
		if !ok {
			return nil, nil
		}
		e := float64(len(arr))
		if len(args) > 2 {
			if e, ok = num(2); !ok {
				return nil, nil
			}
		}
		si, ei := normIdx(int(s), len(arr)), normIdx(int(e), len(arr))
		if si >= ei {
			return []any{}, nil
		}
		return append([]any{}, arr[si:ei]...), nil
	case "reverse":
		arr, ok := args[0].([]any)
		if !ok {
			return nil, nil
		}
		out := make([]any, len(arr))
		for i, v := range arr {
			out[len(arr)-1-i] = v
		}
		return out, nil
	case "join":
		arr, ok := args[0].([]any)
		if !ok {
			return nil, nil
		}
		sep := ", "
		if len(args) > 1 {
			if s, ok := args[1].(string); ok {
				sep = s
			}
		}
		parts := make([]string, 0, len(arr))
		for _, v := range arr {
			parts = append(parts, Str(v))
		}
		return strings.Join(parts, sep), nil
	case "contains":
		switch x := args[0].(type) {
		case string:
			s, ok := args[1].(string)
			return ok && strings.Contains(x, s), nil
		case []any:
			for _, v := range x {
				if equal(v, args[1]) {
					return true, nil
				}
			}
		}
		return false, nil
	case "fmt":
		x, ok := num(0)
		if !ok {
			return nil, nil
		}
		if len(args) > 1 {
			d, ok := num(1)
			if !ok {
				return nil, nil
			}
			return Fmt(x, int(clampF(d, 0, 6)), true), nil
		}
		return Fmt(x, 0, false), nil
	case "pct":
		x, ok := num(0)
		if !ok {
			return nil, nil
		}
		d := 2.0
		if len(args) > 1 {
			if d, ok = num(1); !ok {
				return nil, nil
			}
		}
		return Pct(x, int(clampF(d, 0, 6))), nil
	case "str":
		return Str(args[0]), nil
	case "num":
		switch x := args[0].(type) {
		case float64:
			return x, nil
		case string:
			return parseNum(x), nil
		}
		return nil, nil
	case "today":
		return ev.now().In(Shanghai).Format("2006-01-02"), nil
	case "now":
		return float64(ev.now().UnixMilli()), nil
	case "date":
		x, ok := num(0)
		if !ok {
			return nil, nil
		}
		return time.UnixMilli(int64(x)).In(Shanghai).Format("2006-01-02"), nil
	case "date_add":
		s, ok := args[0].(string)
		n, ok2 := num(1)
		if !ok || !ok2 {
			return nil, nil
		}
		t, err := time.ParseInLocation("2006-01-02", s, Shanghai)
		if err != nil {
			return nil, nil
		}
		return t.AddDate(0, 0, int(n)).Format("2006-01-02"), nil
	case "month_start":
		t := ev.now().In(Shanghai)
		return float64(time.Date(t.Year(), t.Month(), 1, 0, 0, 0, 0, Shanghai).UnixMilli()), nil
	case "days_between":
		a, ok1 := args[0].(string)
		b, ok2 := args[1].(string)
		if !ok1 || !ok2 {
			return nil, nil
		}
		ta, e1 := time.ParseInLocation("2006-01-02", a, Shanghai)
		tb, e2 := time.ParseInLocation("2006-01-02", b, Shanghai)
		if e1 != nil || e2 != nil {
			return nil, nil
		}
		return math.Round(tb.Sub(ta).Hours() / 24), nil
	}
	return nil, nil
}

func parseNum(s string) any {
	s = strings.TrimSpace(strings.ReplaceAll(s, ",", ""))
	if s == "" {
		return nil
	}
	toks, err := lex(s)
	if err != nil {
		return nil
	}
	neg := false
	if len(toks) == 3 && toks[0].kind == tPunct && toks[0].s == "-" {
		neg = true
		toks = toks[1:]
	}
	if len(toks) != 2 || toks[0].kind != tNum {
		return nil
	}
	if neg {
		return -toks[0].n
	}
	return toks[0].n
}

func normIdx(i, n int) int {
	if i < 0 {
		i += n
	}
	if i < 0 {
		return 0
	}
	if i > n {
		return n
	}
	return i
}

func clampF(x, lo, hi float64) float64 {
	if x < lo {
		return lo
	}
	if x > hi {
		return hi
	}
	return x
}

// elemFn 把 lambda 参数变成逐元素求值函数：字符串字面量是字段名简写。
func (ev *evaluator) elemFn(n Node) func(item any, idx int) (any, error) {
	if l, ok := n.(litNode); ok {
		if field, ok := l.v.(string); ok {
			return func(item any, _ int) (any, error) {
				if m, ok := item.(map[string]any); ok {
					return m[field], nil
				}
				return nil, nil
			}
		}
	}
	return func(item any, idx int) (any, error) {
		ev.scopes = append(ev.scopes, map[string]any{"item": item, "index": float64(idx)})
		defer func() { ev.scopes = ev.scopes[:len(ev.scopes)-1] }()
		return ev.eval(n)
	}
}

func (ev *evaluator) callLazy(c callNode) (any, error) {
	first, err := ev.eval(c.args[0])
	if err != nil {
		return nil, err
	}
	arr, ok := first.([]any)
	if !ok {
		switch c.name {
		case "count", "sum":
			return 0.0, nil
		case "map", "filter", "sort_by", "zip_with", "group_sum":
			return []any{}, nil
		}
		return nil, nil
	}
	if len(arr) > MaxArray {
		return nil, errArray
	}
	switch c.name {
	case "zip_with":
		second, err := ev.eval(c.args[1])
		if err != nil {
			return nil, err
		}
		brr, _ := second.([]any)
		if len(brr) > MaxArray {
			return nil, errArray
		}
		n := len(arr)
		if len(brr) < n {
			n = len(brr)
		}
		out := make([]any, 0, n)
		for i := 0; i < n; i++ {
			ev.scopes = append(ev.scopes, map[string]any{"x": arr[i], "y": brr[i], "index": float64(i)})
			v, err := ev.eval(c.args[2])
			ev.scopes = ev.scopes[:len(ev.scopes)-1]
			if err != nil {
				return nil, err
			}
			out = append(out, v)
		}
		return out, nil
	}
	var fn func(any, int) (any, error)
	if len(c.args) > 1 {
		fn = ev.elemFn(c.args[1])
	}
	vals := func() ([]any, error) {
		if fn == nil {
			return arr, nil
		}
		out := make([]any, len(arr))
		for i, it := range arr {
			v, err := fn(it, i)
			if err != nil {
				return nil, err
			}
			out[i] = v
		}
		return out, nil
	}
	switch c.name {
	case "group_sum":
		keyFn := ev.elemFn(c.args[1])
		valFn := ev.elemFn(c.args[2])
		sums := map[string]float64{}
		var order []string
		for i, it := range arr {
			k, err := keyFn(it, i)
			if err != nil {
				return nil, err
			}
			v, err := valFn(it, i)
			if err != nil {
				return nil, err
			}
			ks := Str(k)
			if _, seen := sums[ks]; !seen {
				order = append(order, ks)
				sums[ks] = 0
			}
			if f, ok := v.(float64); ok && !math.IsNaN(f) {
				sums[ks] += f
			}
		}
		sort.SliceStable(order, func(a, b int) bool {
			if sums[order[a]] != sums[order[b]] {
				return sums[order[a]] > sums[order[b]]
			}
			return order[a] < order[b]
		})
		out := make([]any, 0, len(order))
		for _, k := range order {
			out = append(out, map[string]any{"key": k, "value": sums[k]})
		}
		return out, nil
	case "map":
		return vals()
	case "filter":
		out := []any{}
		for i, it := range arr {
			v, err := fn(it, i)
			if err != nil {
				return nil, err
			}
			if Truthy(v) {
				out = append(out, it)
			}
		}
		return out, nil
	case "count":
		if fn == nil {
			return float64(len(arr)), nil
		}
		n := 0
		for i, it := range arr {
			v, err := fn(it, i)
			if err != nil {
				return nil, err
			}
			if Truthy(v) {
				n++
			}
		}
		return float64(n), nil
	case "sum", "avg":
		vs, err := vals()
		if err != nil {
			return nil, err
		}
		s, n := 0.0, 0
		for _, v := range vs {
			if f, ok := v.(float64); ok && !math.IsNaN(f) {
				s += f
				n++
			}
		}
		if c.name == "sum" {
			return s, nil
		}
		if n == 0 {
			return nil, nil
		}
		return s / float64(n), nil
	case "sort_by":
		keys, err := vals()
		if err != nil {
			return nil, err
		}
		desc := false
		if len(c.args) > 2 {
			d, err := ev.eval(c.args[2])
			if err != nil {
				return nil, err
			}
			desc = d == "desc"
		}
		idx := make([]int, len(arr))
		for i := range idx {
			idx[i] = i
		}
		sort.SliceStable(idx, func(a, b int) bool {
			c := compareAny(keys[idx[a]], keys[idx[b]])
			if desc {
				return c > 0
			}
			return c < 0
		})
		out := make([]any, len(arr))
		for i, k := range idx {
			out[i] = arr[k]
		}
		return out, nil
	}
	return nil, nil
}

// compareAny：数字 < 字符串 < 其他（null 排最后），同类按值比较。
func compareAny(a, b any) int {
	rank := func(v any) int {
		switch v.(type) {
		case float64:
			return 0
		case string:
			return 1
		case nil:
			return 3
		}
		return 2
	}
	ra, rb := rank(a), rank(b)
	if ra != rb {
		return ra - rb
	}
	switch x := a.(type) {
	case float64:
		return compareF(x, b.(float64))
	case string:
		return strings.Compare(x, b.(string))
	}
	return 0
}
