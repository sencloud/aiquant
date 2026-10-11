// Package xel 是小应用的受限表达式语言（Xiai Expression Language）。
//
// 设计目标：让大模型生成的小应用能做“派生字段”（涨跌颜色、降雨合计、价差序列），
// 但**不是**可执行代码——没有循环、赋值、自定义函数，也不能联网或读写存储；
// 只有字面量、成员访问、运算符、三元、以及白名单函数。这是小应用过
// App Store 2.5.2 的关键：下发的是数据，不是程序。
//
// 同一套语义在 Dart 端（lib/miniapp/expr/xel.dart）再实现一遍：客户端负责
// 渲染时求值（计算器离线可用），服务端负责校验与试运行。两端共用
// testdata/conformance.json 用例，CI 各自跑一遍，保证结果逐字一致。
//
// 限制：表达式 ≤ MaxExprLen 字符、AST 深度 ≤ MaxDepth、单次求值 ≤ MaxSteps 步、
// 数组 ≤ MaxArray 元素。超限返回错误（渲染层显示为空，不会崩溃）。
package xel

import (
	"errors"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// 限制。
const (
	MaxExprLen = 512
	MaxDepth   = 32
	MaxSteps   = 10000
	MaxArray   = 5000
)

// Shanghai 是日期函数使用的固定时区（UTC+8，无夏令时）。
var Shanghai = time.FixedZone("CST", 8*3600)

// ─── AST ───────────────────────────────────────────────────────────────

// Node 是表达式语法树节点。
type Node interface{ node() }

type (
	litNode    struct{ v any }
	identNode  struct{ name string }
	memberNode struct {
		obj  Node
		name string
	}
	indexNode struct{ obj, idx Node }
	unaryNode struct {
		op string
		x  Node
	}
	binaryNode struct {
		op   string
		l, r Node
	}
	condNode struct{ c, a, b Node }
	callNode struct {
		name string
		args []Node
	}
	arrayNode struct{ elems []Node }
	objNode   struct {
		keys []string
		vals []Node
	}
)

func (litNode) node()    {}
func (identNode) node()  {}
func (memberNode) node() {}
func (indexNode) node()  {}
func (unaryNode) node()  {}
func (binaryNode) node() {}
func (condNode) node()   {}
func (callNode) node()   {}
func (arrayNode) node()  {}
func (objNode) node()    {}

// Expr 是编译好的表达式。
type Expr struct {
	Src  string
	root Node
}

// ─── 词法 ───────────────────────────────────────────────────────────────

type tokKind int

const (
	tEOF tokKind = iota
	tNum
	tStr
	tIdent
	tPunct
)

type token struct {
	kind tokKind
	s    string
	n    float64
	pos  int
}

var puncts = []string{"&&", "||", "??", "==", "!=", "<=", ">=",
	"(", ")", "[", "]", "{", "}", ",", ".", ":", "?", "+", "-", "*", "/", "%", "!", "<", ">"}

func lex(src string) ([]token, error) {
	var out []token
	i := 0
	for i < len(src) {
		c := src[i]
		switch {
		case c == ' ' || c == '\t' || c == '\n' || c == '\r':
			i++
		case c >= '0' && c <= '9':
			j := i
			for j < len(src) && (src[j] >= '0' && src[j] <= '9') {
				j++
			}
			if j < len(src) && src[j] == '.' && j+1 < len(src) && src[j+1] >= '0' && src[j+1] <= '9' {
				j++
				for j < len(src) && (src[j] >= '0' && src[j] <= '9') {
					j++
				}
			}
			n, err := strconv.ParseFloat(src[i:j], 64)
			if err != nil {
				return nil, fmt.Errorf("位置 %d：数字格式不正确", i)
			}
			out = append(out, token{kind: tNum, n: n, pos: i})
			i = j
		case c == '\'' || c == '"':
			q := c
			j := i + 1
			var sb strings.Builder
			closed := false
			for j < len(src) {
				if src[j] == '\\' && j+1 < len(src) {
					switch src[j+1] {
					case 'n':
						sb.WriteByte('\n')
					case 't':
						sb.WriteByte('\t')
					default:
						sb.WriteByte(src[j+1])
					}
					j += 2
					continue
				}
				if src[j] == q {
					closed = true
					j++
					break
				}
				sb.WriteByte(src[j])
				j++
			}
			if !closed {
				return nil, fmt.Errorf("位置 %d：字符串缺少结束引号", i)
			}
			out = append(out, token{kind: tStr, s: sb.String(), pos: i})
			i = j
		case c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'):
			j := i
			for j < len(src) && (src[j] == '_' || (src[j] >= 'a' && src[j] <= 'z') ||
				(src[j] >= 'A' && src[j] <= 'Z') || (src[j] >= '0' && src[j] <= '9')) {
				j++
			}
			out = append(out, token{kind: tIdent, s: src[i:j], pos: i})
			i = j
		default:
			matched := false
			for _, p := range puncts {
				if strings.HasPrefix(src[i:], p) {
					out = append(out, token{kind: tPunct, s: p, pos: i})
					i += len(p)
					matched = true
					break
				}
			}
			if !matched {
				r, _ := utf8.DecodeRuneInString(src[i:])
				return nil, fmt.Errorf("位置 %d：不支持的字符 %q", i, r)
			}
		}
	}
	out = append(out, token{kind: tEOF, pos: len(src)})
	return out, nil
}

// ─── 语法 ───────────────────────────────────────────────────────────────

type parser struct {
	toks []token
	i    int
}

func (p *parser) peek() token { return p.toks[p.i] }
func (p *parser) next() token { t := p.toks[p.i]; p.i++; return t }
func (p *parser) isP(s string) bool {
	t := p.peek()
	return t.kind == tPunct && t.s == s
}
func (p *parser) expect(s string) error {
	if !p.isP(s) {
		return fmt.Errorf("位置 %d：缺少 %q", p.peek().pos, s)
	}
	p.i++
	return nil
}

// depthOf 计算语法树深度。
func depthOf(n Node) int {
	max := 0
	child := func(c Node) {
		if d := depthOf(c); d > max {
			max = d
		}
	}
	switch v := n.(type) {
	case memberNode:
		child(v.obj)
	case indexNode:
		child(v.obj)
		child(v.idx)
	case unaryNode:
		child(v.x)
	case binaryNode:
		child(v.l)
		child(v.r)
	case condNode:
		child(v.c)
		child(v.a)
		child(v.b)
	case callNode:
		for _, a := range v.args {
			child(a)
		}
	case arrayNode:
		for _, a := range v.elems {
			child(a)
		}
	case objNode:
		for _, a := range v.vals {
			child(a)
		}
	}
	return max + 1
}

// Compile 编译表达式源码（不含开头的 "="）。
func Compile(src string) (*Expr, error) {
	if len(src) > MaxExprLen {
		return nil, fmt.Errorf("表达式超过 %d 字符", MaxExprLen)
	}
	if strings.TrimSpace(src) == "" {
		return nil, errors.New("表达式为空")
	}
	toks, err := lex(src)
	if err != nil {
		return nil, err
	}
	p := &parser{toks: toks}
	n, err := p.parseExpr()
	if err != nil {
		return nil, err
	}
	if p.peek().kind != tEOF {
		return nil, fmt.Errorf("位置 %d：多余的内容", p.peek().pos)
	}
	if depthOf(n) > MaxDepth {
		return nil, errors.New("表达式嵌套太深")
	}
	return &Expr{Src: src, root: n}, nil
}

func (p *parser) parseExpr() (Node, error) {
	c, err := p.parseBinary(0)
	if err != nil {
		return nil, err
	}
	if p.isP("?") {
		p.i++
		a, err := p.parseExpr()
		if err != nil {
			return nil, err
		}
		if err := p.expect(":"); err != nil {
			return nil, err
		}
		b, err := p.parseExpr()
		if err != nil {
			return nil, err
		}
		return condNode{c, a, b}, nil
	}
	return c, nil
}

var precedence = []map[string]bool{
	{"??": true},
	{"||": true},
	{"&&": true},
	{"==": true, "!=": true},
	{"<": true, "<=": true, ">": true, ">=": true},
	{"+": true, "-": true},
	{"*": true, "/": true, "%": true},
}

func (p *parser) parseBinary(level int) (Node, error) {
	if level >= len(precedence) {
		return p.parseUnary()
	}
	l, err := p.parseBinary(level + 1)
	if err != nil {
		return nil, err
	}
	for {
		t := p.peek()
		if t.kind != tPunct || !precedence[level][t.s] {
			return l, nil
		}
		p.i++
		r, err := p.parseBinary(level + 1)
		if err != nil {
			return nil, err
		}
		l = binaryNode{t.s, l, r}
	}
}

func (p *parser) parseUnary() (Node, error) {
	if p.isP("!") || p.isP("-") {
		op := p.next().s
		x, err := p.parseUnary()
		if err != nil {
			return nil, err
		}
		return unaryNode{op, x}, nil
	}
	return p.parsePostfix()
}

func (p *parser) parsePostfix() (Node, error) {
	n, err := p.parsePrimary()
	if err != nil {
		return nil, err
	}
	for {
		switch {
		case p.isP("."):
			p.i++
			t := p.next()
			if t.kind != tIdent {
				return nil, fmt.Errorf("位置 %d：. 后面应是字段名", t.pos)
			}
			n = memberNode{n, t.s}
		case p.isP("["):
			p.i++
			idx, err := p.parseExpr()
			if err != nil {
				return nil, err
			}
			if err := p.expect("]"); err != nil {
				return nil, err
			}
			n = indexNode{n, idx}
		default:
			return n, nil
		}
	}
}

func (p *parser) parsePrimary() (Node, error) {
	t := p.next()
	switch t.kind {
	case tNum:
		return litNode{t.n}, nil
	case tStr:
		return litNode{t.s}, nil
	case tIdent:
		switch t.s {
		case "true":
			return litNode{true}, nil
		case "false":
			return litNode{false}, nil
		case "null":
			return litNode{nil}, nil
		}
		if p.isP("(") {
			p.i++
			f, ok := funcs[t.s]
			if !ok {
				return nil, fmt.Errorf("不支持的函数 %s()", t.s)
			}
			var args []Node
			for !p.isP(")") {
				a, err := p.parseExpr()
				if err != nil {
					return nil, err
				}
				args = append(args, a)
				if p.isP(",") {
					p.i++
					continue
				}
				if !p.isP(")") {
					return nil, fmt.Errorf("位置 %d：参数之间缺少逗号", p.peek().pos)
				}
			}
			p.i++
			if len(args) < f.min || (f.max >= 0 && len(args) > f.max) {
				return nil, fmt.Errorf("%s() 参数个数不对", t.s)
			}
			return callNode{t.s, args}, nil
		}
		return identNode{t.s}, nil
	case tPunct:
		switch t.s {
		case "(":
			n, err := p.parseExpr()
			if err != nil {
				return nil, err
			}
			if err := p.expect(")"); err != nil {
				return nil, err
			}
			return n, nil
		case "[":
			var elems []Node
			for !p.isP("]") {
				e, err := p.parseExpr()
				if err != nil {
					return nil, err
				}
				elems = append(elems, e)
				if p.isP(",") {
					p.i++
					continue
				}
				if !p.isP("]") {
					return nil, fmt.Errorf("位置 %d：数组元素之间缺少逗号", p.peek().pos)
				}
			}
			p.i++
			return arrayNode{elems}, nil
		case "{":
			var o objNode
			for !p.isP("}") {
				k := p.next()
				if k.kind != tStr && k.kind != tIdent {
					return nil, fmt.Errorf("位置 %d：对象的键应是字符串", k.pos)
				}
				if err := p.expect(":"); err != nil {
					return nil, err
				}
				v, err := p.parseExpr()
				if err != nil {
					return nil, err
				}
				o.keys = append(o.keys, k.s)
				o.vals = append(o.vals, v)
				if p.isP(",") {
					p.i++
					continue
				}
				if !p.isP("}") {
					return nil, fmt.Errorf("位置 %d：对象成员之间缺少逗号", p.peek().pos)
				}
			}
			p.i++
			return o, nil
		}
	}
	if t.kind == tEOF {
		return nil, errors.New("表达式不完整")
	}
	return nil, fmt.Errorf("位置 %d：意外的 %q", t.pos, t.s)
}

// Roots 返回表达式里引用到的顶层标识符（去重、排序），用于校验和依赖分析。
// 函数名不算；lambda 里的 item/index/x/y 也会出现在结果里。
func (e *Expr) Roots() []string {
	set := map[string]bool{}
	walk(e.root, func(n Node) {
		if id, ok := n.(identNode); ok {
			set[id.name] = true
		}
	})
	out := make([]string, 0, len(set))
	for k := range set {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// DataRefs 返回 data.<alias> 形式引用到的别名（去重、排序）。
func (e *Expr) DataRefs() []string {
	set := map[string]bool{}
	walk(e.root, func(n Node) {
		switch m := n.(type) {
		case memberNode:
			if id, ok := m.obj.(identNode); ok && id.name == "data" {
				set[m.name] = true
			}
		case indexNode:
			if id, ok := m.obj.(identNode); ok && id.name == "data" {
				if l, ok := m.idx.(litNode); ok {
					if s, ok := l.v.(string); ok {
						set[s] = true
					}
				}
			}
		}
	})
	out := make([]string, 0, len(set))
	for k := range set {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func walk(n Node, f func(Node)) {
	if n == nil {
		return
	}
	f(n)
	switch v := n.(type) {
	case memberNode:
		walk(v.obj, f)
	case indexNode:
		walk(v.obj, f)
		walk(v.idx, f)
	case unaryNode:
		walk(v.x, f)
	case binaryNode:
		walk(v.l, f)
		walk(v.r, f)
	case condNode:
		walk(v.c, f)
		walk(v.a, f)
		walk(v.b, f)
	case callNode:
		for _, a := range v.args {
			walk(a, f)
		}
	case arrayNode:
		for _, a := range v.elems {
			walk(a, f)
		}
	case objNode:
		for _, a := range v.vals {
			walk(a, f)
		}
	}
}

// ─── 求值 ───────────────────────────────────────────────────────────────

// Env 是求值环境。Vars 的值必须是 JSON 形态：nil / bool / float64 / string /
// []any / map[string]any。Now 为空时用 time.Now（测试注入固定时间）。
type Env struct {
	Vars map[string]any
	Now  func() time.Time
}

type evaluator struct {
	env    *Env
	steps  int
	scopes []map[string]any
}

// ErrSteps 求值步数超限。
var ErrSteps = errors.New("表达式计算量超限")

// Eval 求值。错误（超限、数组过大）时返回 nil 和错误；
// 访问不存在的字段不算错误，结果为 nil。
func (e *Expr) Eval(env *Env) (any, error) {
	ev := &evaluator{env: env}
	return ev.eval(e.root)
}

func (ev *evaluator) lookup(name string) any {
	for i := len(ev.scopes) - 1; i >= 0; i-- {
		if v, ok := ev.scopes[i][name]; ok {
			return v
		}
	}
	if ev.env != nil && ev.env.Vars != nil {
		return ev.env.Vars[name]
	}
	return nil
}

func (ev *evaluator) now() time.Time {
	if ev.env != nil && ev.env.Now != nil {
		return ev.env.Now()
	}
	return time.Now()
}

func (ev *evaluator) eval(n Node) (any, error) {
	ev.steps++
	if ev.steps > MaxSteps {
		return nil, ErrSteps
	}
	switch v := n.(type) {
	case litNode:
		return v.v, nil
	case identNode:
		return ev.lookup(v.name), nil
	case memberNode:
		o, err := ev.eval(v.obj)
		if err != nil {
			return nil, err
		}
		if m, ok := o.(map[string]any); ok {
			return m[v.name], nil
		}
		return nil, nil
	case indexNode:
		o, err := ev.eval(v.obj)
		if err != nil {
			return nil, err
		}
		i, err := ev.eval(v.idx)
		if err != nil {
			return nil, err
		}
		return index(o, i), nil
	case unaryNode:
		x, err := ev.eval(v.x)
		if err != nil {
			return nil, err
		}
		if v.op == "!" {
			return !Truthy(x), nil
		}
		if f, ok := x.(float64); ok {
			return -f, nil
		}
		return nil, nil
	case binaryNode:
		return ev.binary(v)
	case condNode:
		c, err := ev.eval(v.c)
		if err != nil {
			return nil, err
		}
		if Truthy(c) {
			return ev.eval(v.a)
		}
		return ev.eval(v.b)
	case arrayNode:
		out := make([]any, 0, len(v.elems))
		for _, e := range v.elems {
			x, err := ev.eval(e)
			if err != nil {
				return nil, err
			}
			out = append(out, x)
		}
		return out, nil
	case objNode:
		out := make(map[string]any, len(v.keys))
		for i, k := range v.keys {
			x, err := ev.eval(v.vals[i])
			if err != nil {
				return nil, err
			}
			out[k] = x
		}
		return out, nil
	case callNode:
		return ev.call(v)
	}
	return nil, nil
}

func index(o, i any) any {
	switch c := o.(type) {
	case []any:
		f, ok := i.(float64)
		if !ok || f != math.Trunc(f) {
			return nil
		}
		k := int(f)
		if k < 0 {
			k += len(c)
		}
		if k < 0 || k >= len(c) {
			return nil
		}
		return c[k]
	case map[string]any:
		if s, ok := i.(string); ok {
			return c[s]
		}
	}
	return nil
}

func (ev *evaluator) binary(v binaryNode) (any, error) {
	l, err := ev.eval(v.l)
	if err != nil {
		return nil, err
	}
	switch v.op {
	case "&&":
		if !Truthy(l) {
			return false, nil
		}
		r, err := ev.eval(v.r)
		if err != nil {
			return nil, err
		}
		return Truthy(r), nil
	case "||":
		if Truthy(l) {
			return true, nil
		}
		r, err := ev.eval(v.r)
		if err != nil {
			return nil, err
		}
		return Truthy(r), nil
	case "??":
		if l != nil {
			return l, nil
		}
		return ev.eval(v.r)
	}
	r, err := ev.eval(v.r)
	if err != nil {
		return nil, err
	}
	switch v.op {
	case "==":
		return equal(l, r), nil
	case "!=":
		return !equal(l, r), nil
	case "+":
		ls, lIsS := l.(string)
		rs, rIsS := r.(string)
		if lIsS || rIsS {
			if !lIsS {
				ls = Str(l)
			}
			if !rIsS {
				rs = Str(r)
			}
			return ls + rs, nil
		}
	case "<", "<=", ">", ">=":
		lf, lok := l.(float64)
		rf, rok := r.(float64)
		if lok && rok {
			return cmpOp(v.op, compareF(lf, rf)), nil
		}
		ls, lok := l.(string)
		rs, rok := r.(string)
		if lok && rok {
			return cmpOp(v.op, strings.Compare(ls, rs)), nil
		}
		return false, nil
	}
	lf, lok := l.(float64)
	rf, rok := r.(float64)
	if !lok || !rok {
		return nil, nil
	}
	switch v.op {
	case "+":
		return lf + rf, nil
	case "-":
		return lf - rf, nil
	case "*":
		return lf * rf, nil
	case "/":
		if rf == 0 {
			return nil, nil
		}
		return lf / rf, nil
	case "%":
		if rf == 0 {
			return nil, nil
		}
		return math.Mod(lf, rf), nil
	}
	return nil, nil
}

func compareF(a, b float64) int {
	switch {
	case a < b:
		return -1
	case a > b:
		return 1
	}
	return 0
}

func cmpOp(op string, c int) bool {
	switch op {
	case "<":
		return c < 0
	case "<=":
		return c <= 0
	case ">":
		return c > 0
	}
	return c >= 0
}

func equal(a, b any) bool {
	switch x := a.(type) {
	case nil:
		return b == nil
	case bool:
		y, ok := b.(bool)
		return ok && x == y
	case float64:
		y, ok := b.(float64)
		return ok && x == y
	case string:
		y, ok := b.(string)
		return ok && x == y
	}
	return false
}

// Truthy：nil / false / 0 / "" / NaN 为假，其余（包括空数组）为真。
func Truthy(v any) bool {
	switch x := v.(type) {
	case nil:
		return false
	case bool:
		return x
	case float64:
		return x != 0 && !math.IsNaN(x)
	case string:
		return x != ""
	}
	return true
}

// ─── 字符串化与格式化（两端必须逐字一致）──────────────────────────────

// Str 把值转成展示用字符串：nil→""；数字见 NumStr；数组用 ", " 连接标量；对象→""。
func Str(v any) string {
	switch x := v.(type) {
	case nil:
		return ""
	case bool:
		if x {
			return "true"
		}
		return "false"
	case float64:
		return NumStr(x)
	case string:
		return x
	case []any:
		parts := make([]string, 0, len(x))
		for _, e := range x {
			switch e.(type) {
			case []any, map[string]any:
				continue
			}
			parts = append(parts, Str(e))
		}
		return strings.Join(parts, ", ")
	}
	return ""
}

// NumStr：整数（|x|<1e15）不带小数；否则保留至多 6 位小数（四舍五入、去掉末尾 0）；
// |x| ≥ 1e9 的非整数取整。NaN / Inf → ""。
func NumStr(x float64) string {
	if math.IsNaN(x) || math.IsInf(x, 0) {
		return ""
	}
	if x == math.Trunc(x) && math.Abs(x) < 1e15 {
		return strconv.FormatFloat(x, 'f', 0, 64)
	}
	if math.Abs(x) >= 1e9 {
		return fixed(x, 0, false)
	}
	return trimZeros(fixed(x, 6, false))
}

// fixed 用“乘 10^d 后四舍五入（远离 0）”的整数法格式化，避免两端
// 浮点格式化对 .5 的处理差异。group=true 时整数部分加千分位。
func fixed(x float64, d int, group bool) string {
	if math.IsNaN(x) || math.IsInf(x, 0) {
		return ""
	}
	if d < 0 {
		d = 0
	}
	if d > 6 {
		d = 6
	}
	neg := x < 0
	scaled := math.Round(math.Abs(x) * math.Pow10(d))
	digits := strconv.FormatFloat(scaled, 'f', 0, 64)
	for len(digits) <= d {
		digits = "0" + digits
	}
	intPart := digits[:len(digits)-d]
	frac := digits[len(digits)-d:]
	if group {
		intPart = groupThousands(intPart)
	}
	s := intPart
	if d > 0 {
		s += "." + frac
	}
	if neg && scaled != 0 {
		s = "-" + s
	}
	return s
}

func groupThousands(s string) string {
	if len(s) <= 3 {
		return s
	}
	var b strings.Builder
	pre := len(s) % 3
	if pre > 0 {
		b.WriteString(s[:pre])
	}
	for i := pre; i < len(s); i += 3 {
		if b.Len() > 0 {
			b.WriteByte(',')
		}
		b.WriteString(s[i : i+3])
	}
	return b.String()
}

func trimZeros(s string) string {
	if !strings.Contains(s, ".") {
		return s
	}
	s = strings.TrimRight(s, "0")
	s = strings.TrimSuffix(s, ".")
	if s == "-0" {
		return "0"
	}
	return s
}

// Fmt 是 fmt(x, d)：千分位；给 d 时固定 d 位小数，不给时至多 2 位并去掉末尾 0。
func Fmt(x float64, d int, hasD bool) string {
	if !hasD {
		return trimZeros(fixed(x, 2, true))
	}
	return fixed(x, d, true)
}

// Pct 是 pct(x, d=2)：x 已经是百分数（1.23 表示 1.23%），正数带 "+"。
func Pct(x float64, d int) string {
	s := fixed(x, d, false)
	if s == "" {
		return ""
	}
	if x > 0 && strings.Trim(s, "0.") != "" {
		s = "+" + s
	}
	return s + "%"
}

// ─── 模板 ───────────────────────────────────────────────────────────────

// Template 是 "文字 ${表达式} 文字" 形式的字符串模板。
type Template struct {
	parts []tplPart
}

type tplPart struct {
	lit  string
	expr *Expr
}

// CompileTemplate 编译模板。没有 ${} 的字符串也是合法模板（纯文本）。
func CompileTemplate(s string) (*Template, error) {
	t := &Template{}
	i := 0
	for i < len(s) {
		j := strings.Index(s[i:], "${")
		if j < 0 {
			t.parts = append(t.parts, tplPart{lit: s[i:]})
			break
		}
		if j > 0 {
			t.parts = append(t.parts, tplPart{lit: s[i : i+j]})
		}
		start := i + j + 2
		end, err := matchBrace(s, start)
		if err != nil {
			return nil, err
		}
		e, err := Compile(s[start:end])
		if err != nil {
			return nil, fmt.Errorf("模板 ${%s}：%w", s[start:end], err)
		}
		t.parts = append(t.parts, tplPart{expr: e})
		i = end + 1
	}
	return t, nil
}

func matchBrace(s string, start int) (int, error) {
	depth := 0
	var quote byte
	for k := start; k < len(s); k++ {
		c := s[k]
		if quote != 0 {
			if c == '\\' {
				k++
				continue
			}
			if c == quote {
				quote = 0
			}
			continue
		}
		switch c {
		case '\'', '"':
			quote = c
		case '{':
			depth++
		case '}':
			if depth == 0 {
				return k, nil
			}
			depth--
		}
	}
	return 0, errors.New("模板里的 ${ 缺少结束的 }")
}

// Exprs 返回模板里的全部表达式。
func (t *Template) Exprs() []*Expr {
	var out []*Expr
	for _, p := range t.parts {
		if p.expr != nil {
			out = append(out, p.expr)
		}
	}
	return out
}

// Literal 返回模板里的纯文字部分（用于敏感词检查）。
func (t *Template) Literal() string {
	var b strings.Builder
	for _, p := range t.parts {
		b.WriteString(p.lit)
	}
	return b.String()
}

// Render 渲染模板；单个表达式出错时该段为空。
func (t *Template) Render(env *Env) (string, error) {
	var b strings.Builder
	var firstErr error
	for _, p := range t.parts {
		if p.expr == nil {
			b.WriteString(p.lit)
			continue
		}
		v, err := p.expr.Eval(env)
		if err != nil && firstErr == nil {
			firstErr = err
		}
		b.WriteString(Str(v))
	}
	return b.String(), firstErr
}
