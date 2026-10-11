package miniapp

import (
	"encoding/json"
	"fmt"
	"math"
	"regexp"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/sencloud/finme-backend/internal/miniapp/xel"
)

// Issue 是一条校验问题（Path 用 JSON 路径，喂回模型做自动修复）。
type Issue struct {
	Path string `json:"path"`
	Msg  string `json:"msg"`
}

func (i Issue) String() string { return i.Path + "：" + i.Msg }

// InputDef 是一个用户参数定义。
type InputDef struct {
	Key      string
	Type     string
	Label    string
	Default  any
	Options  []string
	Min, Max *float64
	MaxItems int
	Fields   map[string]string // list 元素字段 → number/text
}

// ParamVal 是数据绑定的一个参数：字面量或表达式。
type ParamVal struct {
	Lit  any
	Expr *xel.Expr
}

// Binding 是一个数据绑定。
type Binding struct {
	Alias  string
	Source *Source
	Params map[string]ParamVal
	Each   *xel.Expr
	Deps   []string
	Level  int
}

// Compiled 是校验通过的 spec。
type Compiled struct {
	Raw      map[string]any // 规整后的 spec（入库 / 下发）
	Topic    string
	Title    string
	Icon     string
	Summary  string
	Inputs   map[string]*InputDef
	Bindings map[string]*Binding
	Levels   [][]string
	Computed []string // 拓扑序
	Exprs    map[string]*xel.Expr
	// Checks 是试运行时要检查“结果不能为空”的关键表达式（路径 → 表达式）。
	Checks map[string]*xel.Expr
	// UserScoped 表示用到了用户私有数据源。
	UserScoped bool
	// MinRenderer 是需要的最低客户端渲染器版本。
	MinRenderer int
}

var (
	keyRe   = regexp.MustCompile(`^[a-z][a-z0-9_]{0,23}$`)
	topKeys = map[string]bool{"schema": true, "min_renderer": true, "topic": true, "meta": true,
		"inputs": true, "data": true, "computed": true, "refresh": true, "card_view": true, "layout": true}
	reservedRoots = map[string]bool{"inputs": true, "data": true, "state": true, "item": true,
		"index": true, "x": true, "y": true}
)

type validator struct {
	topic   string
	reg     *Registry
	issues  []Issue
	c       *Compiled
	nComp   int
	banned  []string
	compKey map[string]bool
}

func (v *validator) add(path, format string, a ...any) {
	if len(v.issues) < 40 {
		v.issues = append(v.issues, Issue{Path: path, Msg: fmt.Sprintf(format, a...)})
	}
}

// ValidateJSON 解析并校验 spec 字节。
func ValidateJSON(b []byte, topic string, reg *Registry) (*Compiled, []Issue) {
	if len(b) > MaxSpecBytes {
		return nil, []Issue{{Path: "$", Msg: fmt.Sprintf("spec 超过 %d KB", MaxSpecBytes>>10)}}
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, []Issue{{Path: "$", Msg: "不是合法的 JSON 对象：" + err.Error()}}
	}
	return Validate(m, topic, reg)
}

// Validate 校验并规整 spec。返回的 Compiled 只有在 issues 为空时有效。
func Validate(m map[string]any, topic string, reg *Registry) (*Compiled, []Issue) {
	v := &validator{topic: topic, reg: reg, banned: BannedWords(topic), compKey: map[string]bool{},
		c: &Compiled{Raw: m, Topic: topic, Inputs: map[string]*InputDef{}, Bindings: map[string]*Binding{},
			Exprs: map[string]*xel.Expr{}, Checks: map[string]*xel.Expr{}, MinRenderer: 1}}
	if m == nil {
		return nil, []Issue{{Path: "$", Msg: "spec 为空"}}
	}
	// 自动补齐 / 强制字段，减少无谓的修复轮次。
	if _, ok := m["schema"]; !ok {
		m["schema"] = SchemaID
	}
	if _, ok := m["topic"]; !ok {
		m["topic"] = topic
	}
	for k := range m {
		if !topKeys[k] {
			v.add(k, "不支持的顶层字段")
		}
	}
	if m["schema"] != SchemaID {
		v.add("schema", "必须是 %q", SchemaID)
	}
	if m["topic"] != topic {
		v.add("topic", "必须是 %q（当前主题）", topic)
	}
	v.meta(m)
	v.inputs(m)
	// computed 的名字要先知道，data 参数和组件里都可能引用。
	if cm, ok := m["computed"].(map[string]any); ok {
		for k := range cm {
			v.compKey[k] = true
		}
	}
	v.data(m)
	v.computed(m)
	v.refresh(m)
	if lay, ok := m["layout"]; ok {
		v.component("layout", lay, 1, false)
	} else {
		v.add("layout", "缺少 layout（打开小应用后的完整界面）")
	}
	if cv, ok := m["card_view"]; ok && cv != nil {
		v.component("card_view", cv, 1, false)
	}
	if v.nComp > MaxComponents {
		v.add("layout", "组件太多（%d 个，上限 %d）", v.nComp, MaxComponents)
	}
	m["min_renderer"] = float64(v.c.MinRenderer)
	if b, _ := json.Marshal(m); len(b) > MaxSpecBytes {
		v.add("$", "spec 超过 %d KB", MaxSpecBytes>>10)
	}
	if len(v.issues) > 0 {
		return nil, v.issues
	}
	return v.c, nil
}

func (v *validator) str(path string, x any, required bool, maxRunes int) string {
	s, ok := x.(string)
	if x == nil || (ok && strings.TrimSpace(s) == "") {
		if required {
			v.add(path, "必填")
		}
		return ""
	}
	if !ok {
		v.add(path, "应为字符串")
		return ""
	}
	s = strings.TrimSpace(s)
	if maxRunes > 0 && utf8.RuneCountInString(s) > maxRunes {
		v.add(path, "太长（最多 %d 字）", maxRunes)
	}
	v.checkBanned(path, s)
	return s
}

func (v *validator) checkBanned(path, s string) {
	for _, w := range v.banned {
		if strings.Contains(s, w) {
			v.add(path, "包含不允许的词「%s」%s", w, bannedHint(v.topic))
			return
		}
	}
}

func bannedHint(topic string) string {
	if topic == "money" {
		return "（小应用只展示数据，不能给出买卖建议）"
	}
	return ""
}

func (v *validator) meta(m map[string]any) {
	meta, ok := m["meta"].(map[string]any)
	if !ok {
		v.add("meta", "缺少 meta")
		return
	}
	for k := range meta {
		switch k {
		case "title", "icon", "summary", "card_size", "disclaimer":
		default:
			v.add("meta."+k, "不支持的字段")
		}
	}
	v.c.Title = v.str("meta.title", meta["title"], true, 20)
	v.c.Summary = v.str("meta.summary", meta["summary"], false, 60)
	icon, _ := meta["icon"].(string)
	if icon == "" {
		icon = "apps"
	}
	if !iconSet[icon] {
		v.add("meta.icon", "只能是：%s", strings.Join(Icons, " / "))
	}
	v.c.Icon = icon
	meta["icon"] = icon
	cs, _ := meta["card_size"].(string)
	switch cs {
	case "":
		meta["card_size"] = "medium"
	case "small", "medium", "large":
	default:
		v.add("meta.card_size", "只能是 small / medium / large")
	}
	meta["disclaimer"] = Disclaimer(v.topic)
}

func num(x any) (float64, bool) {
	f, ok := x.(float64)
	return f, ok && !math.IsNaN(f) && !math.IsInf(f, 0)
}

func (v *validator) inputs(m map[string]any) {
	raw, ok := m["inputs"]
	if !ok || raw == nil {
		return
	}
	in, ok := raw.(map[string]any)
	if !ok {
		v.add("inputs", "应为对象 {参数名: 定义}")
		return
	}
	if len(in) > MaxInputs {
		v.add("inputs", "参数太多（上限 %d）", MaxInputs)
	}
	for key, d := range in {
		p := "inputs." + key
		if !keyRe.MatchString(key) {
			v.add(p, "参数名只能用小写字母、数字、下划线，且以字母开头")
		}
		dm, ok := d.(map[string]any)
		if !ok {
			v.add(p, "应为对象")
			continue
		}
		def := &InputDef{Key: key}
		def.Type, _ = dm["type"].(string)
		def.Label = v.str(p+".label", dm["label"], true, 12)
		for k := range dm {
			switch k {
			case "type", "label", "default", "options", "min", "max", "step", "unit", "max_items", "item", "placeholder":
			default:
				v.add(p+"."+k, "不支持的字段")
			}
		}
		def.Default = dm["default"]
		switch def.Type {
		case "number":
			if f, ok := num(dm["min"]); ok {
				def.Min = &f
			}
			if f, ok := num(dm["max"]); ok {
				def.Max = &f
			}
			if def.Default == nil {
				def.Default = 0.0
			}
			if _, ok := num(def.Default); !ok {
				v.add(p+".default", "应为数字")
			}
			v.str(p+".unit", dm["unit"], false, 6)
		case "text":
			if def.Default == nil {
				def.Default = ""
			}
			if s, ok := def.Default.(string); !ok || utf8.RuneCountInString(s) > 40 {
				v.add(p+".default", "应为 40 字以内的字符串")
			}
		case "enum":
			opts, _ := dm["options"].([]any)
			if len(opts) == 0 || len(opts) > 12 {
				v.add(p+".options", "需要 1–12 个选项")
			}
			for i, o := range opts {
				s := v.str(fmt.Sprintf("%s.options[%d]", p, i), o, true, 16)
				def.Options = append(def.Options, s)
			}
			if def.Default == nil && len(def.Options) > 0 {
				def.Default = def.Options[0]
			}
			if s, _ := def.Default.(string); !contains(def.Options, s) {
				v.add(p+".default", "必须是 options 之一")
			}
		case "date":
			if def.Default == nil {
				def.Default = ""
			}
			if _, ok := def.Default.(string); !ok {
				v.add(p+".default", "应为 YYYY-MM-DD 字符串（空串表示今天）")
			}
		case "bool":
			if def.Default == nil {
				def.Default = false
			}
			if _, ok := def.Default.(bool); !ok {
				v.add(p+".default", "应为 true / false")
			}
		case "list":
			def.MaxItems = 5
			if f, ok := num(dm["max_items"]); ok && f >= 1 && f <= 10 {
				def.MaxItems = int(f)
			}
			item, _ := dm["item"].(map[string]any)
			if len(item) == 0 || len(item) > 4 {
				v.add(p+".item", "需要 1–4 个字段，例如 {\"name\": {\"type\": \"text\"}}")
			}
			def.Fields = map[string]string{}
			for fk, fd := range item {
				fm, _ := fd.(map[string]any)
				ft, _ := fm["type"].(string)
				if !keyRe.MatchString(fk) || (ft != "text" && ft != "number") {
					v.add(p+".item."+fk, "字段类型只能是 text / number")
				}
				def.Fields[fk] = ft
			}
			if def.Default == nil {
				def.Default = []any{}
			}
			arr, ok := def.Default.([]any)
			if !ok || len(arr) > def.MaxItems {
				v.add(p+".default", "应为不超过 %d 项的数组", def.MaxItems)
			}
			for i, e := range arr {
				em, ok := e.(map[string]any)
				if !ok {
					v.add(fmt.Sprintf("%s.default[%d]", p, i), "应为对象")
					continue
				}
				for k, val := range em {
					switch def.Fields[k] {
					case "text":
						v.str(fmt.Sprintf("%s.default[%d].%s", p, i, k), val, false, 30)
					case "number":
						if _, ok := num(val); !ok {
							v.add(fmt.Sprintf("%s.default[%d].%s", p, i, k), "应为数字")
						}
					default:
						v.add(fmt.Sprintf("%s.default[%d].%s", p, i, k), "item 里没有这个字段")
					}
				}
			}
		default:
			v.add(p+".type", "只能是 %s", strings.Join(InputTypes, " / "))
		}
		dm["default"] = def.Default
		v.c.Inputs[key] = def
	}
}

func contains(xs []string, s string) bool {
	for _, x := range xs {
		if x == s {
			return true
		}
	}
	return false
}

// compileExpr 编译 "=表达式" 并检查引用的根标识符。
func (v *validator) compileExpr(path, src string) *xel.Expr {
	e, err := xel.Compile(src)
	if err != nil {
		v.add(path, "表达式错误：%v", err)
		return nil
	}
	for _, r := range e.Roots() {
		if !reservedRoots[r] && !v.compKey[r] {
			v.add(path, "未知的名字 %q（可用 inputs / data / state / item / index 或 computed 里定义的名字）", r)
		}
	}
	for _, a := range e.DataRefs() {
		if _, ok := v.c.Raw["data"].(map[string]any)[a]; !ok {
			v.add(path, "data 里没有 %q", a)
		}
	}
	v.c.Exprs[path] = e
	return e
}

func (v *validator) tpl(path string, x any, required bool, maxRunes int) {
	s, ok := x.(string)
	if x == nil || (ok && s == "") {
		if required {
			v.add(path, "必填")
		}
		return
	}
	if !ok {
		if _, isNum := num(x); isNum {
			return
		}
		v.add(path, "应为字符串")
		return
	}
	t, err := xel.CompileTemplate(s)
	if err != nil {
		v.add(path, "%v", err)
		return
	}
	lit := t.Literal()
	if maxRunes > 0 && utf8.RuneCountInString(lit) > maxRunes {
		v.add(path, "文字太长（最多 %d 字）", maxRunes)
	}
	v.checkBanned(path, lit)
	for i, e := range t.Exprs() {
		v.compileExpr(fmt.Sprintf("%s${%d}", path, i), e.Src)
	}
}

// value：字面量或 "=表达式"。
func (v *validator) value(path string, x any) *xel.Expr {
	if s, ok := x.(string); ok {
		if strings.HasPrefix(s, "=") {
			return v.compileExpr(path, s[1:])
		}
		v.tpl(path, s, false, 200)
		return nil
	}
	switch x.(type) {
	case float64, bool, nil:
		return nil
	}
	v.add(path, "应为数字、字符串、布尔或 \"=表达式\"")
	return nil
}

func (v *validator) expr(path string, x any) *xel.Expr {
	s, ok := x.(string)
	if !ok || !strings.HasPrefix(s, "=") {
		v.add(path, "必须是以 = 开头的表达式，例如 \"=data.news.items\"")
		return nil
	}
	return v.compileExpr(path, s[1:])
}

func (v *validator) data(m map[string]any) {
	raw, ok := m["data"]
	if !ok || raw == nil {
		m["data"] = map[string]any{}
		return
	}
	dm, ok := raw.(map[string]any)
	if !ok {
		v.add("data", "应为对象 {别名: {source, params}}")
		m["data"] = map[string]any{}
		return
	}
	if len(dm) > MaxBindings {
		v.add("data", "数据绑定太多（上限 %d）", MaxBindings)
	}
	for alias, b := range dm {
		p := "data." + alias
		if !keyRe.MatchString(alias) {
			v.add(p, "别名只能用小写字母、数字、下划线，且以字母开头")
		}
		bm, ok := b.(map[string]any)
		if !ok {
			v.add(p, "应为对象 {source, params}")
			continue
		}
		for k := range bm {
			if k != "source" && k != "params" && k != "each" {
				v.add(p+"."+k, "不支持的字段（只有 source / params / each）")
			}
		}
		id, _ := bm["source"].(string)
		src := v.reg.Get(id)
		if src == nil {
			v.add(p+".source", "没有数据源 %q", id)
			continue
		}
		if !src.AllowedIn(v.topic) {
			v.add(p+".source", "数据源 %q 不属于当前主题", id)
			continue
		}
		if src.UserScoped {
			v.c.UserScoped = true
		}
		bind := &Binding{Alias: alias, Source: src, Params: map[string]ParamVal{}}
		if each, ok := bm["each"]; ok && each != nil {
			s, _ := each.(string)
			s = strings.TrimPrefix(s, "=")
			if s == "" {
				v.add(p+".each", "应为表达式，例如 \"=inputs.places\"")
			} else {
				bind.Each = v.compileExpr(p+".each", s)
			}
		}
		params, _ := bm["params"].(map[string]any)
		if bm["params"] != nil && params == nil {
			v.add(p+".params", "应为对象")
		}
		lits := map[string]any{}
		known := map[string]ParamDef{}
		for _, pd := range src.Params {
			known[pd.Name] = pd
		}
		for k, pv := range params {
			pp := p + ".params." + k
			if _, ok := known[k]; !ok {
				v.add(pp, "数据源 %s 没有参数 %s", id, k)
				continue
			}
			if s, ok := pv.(string); ok && strings.HasPrefix(s, "=") {
				bind.Params[k] = ParamVal{Expr: v.compileExpr(pp, s[1:])}
				continue
			}
			bind.Params[k] = ParamVal{Lit: pv}
			lits[k] = pv
		}
		// 只有全是字面量的必填参数能在校验期检查；表达式参数在试运行里检查。
		for _, pd := range src.Params {
			if _, ok := bind.Params[pd.Name]; !ok && pd.Required {
				v.add(p+".params."+pd.Name, "必填")
			}
		}
		for k, lv := range lits {
			if _, err := coerceParam(known[k], lv); err != nil {
				v.add(p+".params."+k, "%v", err)
			}
		}
		deps := map[string]bool{}
		collect := func(e *xel.Expr) {
			if e == nil {
				return
			}
			for _, d := range e.DataRefs() {
				deps[d] = true
			}
		}
		collect(bind.Each)
		for _, pv := range bind.Params {
			collect(pv.Expr)
		}
		for d := range deps {
			bind.Deps = append(bind.Deps, d)
		}
		sort.Strings(bind.Deps)
		v.c.Bindings[alias] = bind
	}
	// 分层：依赖深度 ≤ 2（第 0 层直接取数，第 1 层用第 0 层结果）。
	level := map[string]int{}
	var visit func(a string, stack map[string]bool) int
	visit = func(a string, stack map[string]bool) int {
		if l, ok := level[a]; ok {
			return l
		}
		b := v.c.Bindings[a]
		if b == nil {
			return 0
		}
		if stack[a] {
			v.add("data."+a, "数据绑定之间循环依赖")
			return 0
		}
		stack[a] = true
		l := 0
		for _, d := range b.Deps {
			if d == a {
				v.add("data."+a, "不能引用自己")
				continue
			}
			if dl := visit(d, stack) + 1; dl > l {
				l = dl
			}
		}
		delete(stack, a)
		level[a] = l
		b.Level = l
		return l
	}
	maxL := 0
	for a := range v.c.Bindings {
		if l := visit(a, map[string]bool{}); l > maxL {
			maxL = l
		}
	}
	if maxL > 1 {
		v.add("data", "数据绑定依赖层级太深（最多两层：先取 A，再用 A 的结果取 B）")
	}
	v.c.Levels = make([][]string, maxL+1)
	for a, l := range level {
		if l <= maxL {
			v.c.Levels[l] = append(v.c.Levels[l], a)
		}
	}
	for _, lv := range v.c.Levels {
		sort.Strings(lv)
	}
}

func (v *validator) computed(m map[string]any) {
	raw, ok := m["computed"]
	if !ok || raw == nil {
		return
	}
	cm, ok := raw.(map[string]any)
	if !ok {
		v.add("computed", "应为对象 {名字: 表达式}")
		return
	}
	if len(cm) > MaxComputed {
		v.add("computed", "派生字段太多（上限 %d）", MaxComputed)
	}
	exprs := map[string]*xel.Expr{}
	for k, x := range cm {
		p := "computed." + k
		if !keyRe.MatchString(k) || reservedRoots[k] {
			v.add(p, "名字只能用小写字母、数字、下划线，且不能是 inputs / data / state / item / index / x / y")
			continue
		}
		s, ok := x.(string)
		if !ok {
			v.add(p, "应为表达式字符串")
			continue
		}
		if e := v.compileExpr(p, strings.TrimPrefix(s, "=")); e != nil {
			exprs[k] = e
		}
	}
	// 拓扑排序；检测循环。
	state := map[string]int{}
	var order []string
	var visit func(k string) bool
	visit = func(k string) bool {
		switch state[k] {
		case 1:
			return false
		case 2:
			return true
		}
		state[k] = 1
		e := exprs[k]
		if e != nil {
			for _, r := range e.Roots() {
				if _, ok := exprs[r]; ok {
					if !visit(r) {
						return false
					}
				}
			}
		}
		state[k] = 2
		order = append(order, k)
		return true
	}
	keys := make([]string, 0, len(exprs))
	for k := range exprs {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		if !visit(k) {
			v.add("computed."+k, "派生字段之间循环引用")
			return
		}
	}
	v.c.Computed = order
}

func (v *validator) refresh(m map[string]any) {
	r, _ := m["refresh"].(map[string]any)
	onOpen := true
	if b, ok := r["on_open"].(bool); ok {
		onOpen = b
	}
	// P0 不支持定时刷新 / 推送：其余字段静默丢弃。
	m["refresh"] = map[string]any{"on_open": onOpen}
}

func (v *validator) component(path string, x any, depth int, inList bool) {
	v.nComp++
	if depth > MaxComponentDepth {
		v.add(path, "组件嵌套太深（最多 %d 层）", MaxComponentDepth)
		return
	}
	cm, ok := x.(map[string]any)
	if !ok {
		v.add(path, "组件应为对象 {type, ...}")
		return
	}
	t, _ := cm["type"].(string)
	def := ComponentFor(t)
	if def == nil {
		names := make([]string, 0, len(Components))
		for _, c := range Components {
			names = append(names, c.Type)
		}
		v.add(path+".type", "不支持的组件 %q（可用：%s）", t, strings.Join(names, " / "))
		return
	}
	if def.MinRenderer > v.c.MinRenderer {
		v.c.MinRenderer = def.MinRenderer
	}
	props := map[string]Prop{}
	for _, p := range def.Props {
		props[p.Name] = p
	}
	for k := range cm {
		if k == "type" {
			continue
		}
		if _, ok := props[k]; !ok {
			v.add(path+"."+k, "组件 %s 没有属性 %s", t, k)
		}
	}
	for _, p := range def.Props {
		pp := path + "." + p.Name
		val, present := cm[p.Name]
		if !present || val == nil {
			if p.Required {
				v.add(pp, "必填")
			}
			continue
		}
		switch p.Kind {
		case KTpl:
			v.tpl(pp, val, p.Required, 200)
		case KExpr:
			if e := v.expr(pp, val); e != nil && !inList && isCheckProp(t, p.Name) {
				v.c.Checks[pp] = e
			}
		case KValue:
			if e := v.value(pp, val); e != nil && !inList && t == "stat" && p.Name == "value" {
				v.c.Checks[pp] = e
			}
		case KEnum:
			if s, _ := val.(string); !contains(p.Enum, s) {
				v.add(pp, "只能是 %s", strings.Join(p.Enum, " / "))
			}
		case KInt:
			f, ok := num(val)
			if !ok || f != math.Trunc(f) || int(f) < p.Min || int(f) > p.Max {
				v.add(pp, "应为 %d–%d 的整数", p.Min, p.Max)
			}
		case KChildren:
			arr, ok := val.([]any)
			if !ok {
				v.add(pp, "应为组件数组")
				continue
			}
			if len(arr) == 0 {
				v.add(pp, "至少一个子组件")
			}
			for i, ch := range arr {
				v.component(fmt.Sprintf("%s[%d]", pp, i), ch, depth+1, inList)
			}
		case KChild:
			v.component(pp, val, depth+1, inList || t == "list")
		case KColumns:
			arr, ok := val.([]any)
			if !ok || len(arr) == 0 || len(arr) > 8 {
				v.add(pp, "应为 1–8 列的数组")
				continue
			}
			for i, c := range arr {
				cp := fmt.Sprintf("%s[%d]", pp, i)
				col, ok := c.(map[string]any)
				if !ok {
					v.add(cp, "应为 {key, title}")
					continue
				}
				for k := range col {
					if k != "key" && k != "title" && k != "format" && k != "digits" {
						v.add(cp+"."+k, "不支持的字段")
					}
				}
				v.str(cp+".key", col["key"], true, 32)
				v.str(cp+".title", col["title"], true, 10)
				if f, ok := col["format"]; ok {
					if s, _ := f.(string); !contains(ColumnFormats, s) {
						v.add(cp+".format", "只能是 %s", strings.Join(ColumnFormats, " / "))
					}
				}
				if d, ok := col["digits"]; ok {
					if f, ok := num(d); !ok || f < 0 || f > 6 {
						v.add(cp+".digits", "应为 0–6")
					}
				}
			}
		case KSeries:
			arr, ok := val.([]any)
			if !ok || len(arr) == 0 || len(arr) > 4 {
				v.add(pp, "应为 1–4 个序列")
				continue
			}
			for i, s := range arr {
				sp := fmt.Sprintf("%s[%d]", pp, i)
				sm, ok := s.(map[string]any)
				if !ok {
					v.add(sp, "应为 {name, y}")
					continue
				}
				for k := range sm {
					if k != "name" && k != "y" {
						v.add(sp+"."+k, "不支持的字段")
					}
				}
				v.str(sp+".name", sm["name"], true, 10)
				if e := v.expr(sp+".y", sm["y"]); e != nil && !inList {
					v.c.Checks[sp+".y"] = e
				}
			}
		case KStrList:
			arr, ok := val.([]any)
			if !ok {
				v.add(pp, "应为字符串数组")
				continue
			}
			for i, s := range arr {
				v.str(fmt.Sprintf("%s[%d]", pp, i), s, true, 32)
			}
		case KInputRef:
			s, _ := val.(string)
			if _, ok := v.c.Inputs[s]; !ok {
				v.add(pp, "inputs 里没有 %q", s)
			}
		}
	}
}

func isCheckProp(t, prop string) bool {
	switch t + "." + prop {
	case "list.items", "table.rows", "chart.x", "kline.bars":
		return true
	}
	return false
}
