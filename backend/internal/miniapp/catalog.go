// Package miniapp 实现「对话生成小应用」：AI 只生成声明式 JSON（组件树 + 数据绑定 +
// 受限表达式），由 App 内置的原生渲染器绘制；数据只来自服务端白名单数据源。
//
// 运行时（打开、刷新）不调用大模型：只拉数据、求值表达式。大模型只在创建 /
// 修改时调用一次（见 gen.go）。
package miniapp

import "sort"

// SchemaID 是当前 spec 版本标识。
const SchemaID = "xiai.miniapp/1"

// RendererVersion 是服务端认识的最高客户端渲染器版本。
const RendererVersion = 1

// 限额（P0，已拍板）。
const (
	MaxAppsPerTopic    = 20
	MaxMountedPerTopic = 12
	MaxSpecBytes       = 64 << 10
	MaxComponents      = 40
	MaxComponentDepth  = 8
	MaxBindings        = 8
	MaxEach            = 5
	MaxInputs          = 10
	MaxComputed        = 24
	MaxVersionsKept    = 20
	MaxMessageRunes    = 500
)

// PropKind 是组件属性的取值类型。
type PropKind string

const (
	KTpl      PropKind = "template"  // 字符串模板，可含 ${表达式}
	KExpr     PropKind = "expr"      // 必须是 "=表达式"
	KValue    PropKind = "value"     // 字面量（数字 / 字符串 / 布尔）或 "=表达式"
	KEnum     PropKind = "enum"      // 枚举字符串
	KInt      PropKind = "int"       // 整数
	KChildren PropKind = "children"  // 组件数组
	KChild    PropKind = "component" // 单个组件
	KColumns  PropKind = "columns"   // 表格列 [{key,title,format?,digits?}]
	KSeries   PropKind = "series"    // 图表序列 [{name,y}]
	KStrList  PropKind = "strings"   // 字符串数组
	KInputRef PropKind = "input_ref" // inputs 里的键名
)

// Prop 是一个组件属性定义。
type Prop struct {
	Name     string   `json:"name"`
	Kind     PropKind `json:"kind"`
	Required bool     `json:"required,omitempty"`
	Enum     []string `json:"enum,omitempty"`
	Min      int      `json:"min,omitempty"`
	Max      int      `json:"max,omitempty"`
	Doc      string   `json:"doc,omitempty"`
}

// Component 是组件目录里的一项。
type Component struct {
	Type  string `json:"type"`
	Title string `json:"title"`
	Doc   string `json:"doc"`
	Props []Prop `json:"props"`
	// MinRenderer 是渲染该组件需要的最低客户端版本。
	MinRenderer int `json:"min_renderer"`
}

var visibleProp = Prop{Name: "visible", Kind: KValue, Doc: "可选；为假时不显示"}

// Components 是组件目录 v1（P0：布局 / text / stat / list / table / chart / kline / input）。
var Components = []Component{
	{Type: "column", Title: "纵向排列", Doc: "子组件从上到下排列", MinRenderer: 1, Props: []Prop{
		{Name: "children", Kind: KChildren, Required: true},
		{Name: "gap", Kind: KInt, Min: 0, Max: 32},
	}},
	{Type: "row", Title: "横向排列", Doc: "子组件从左到右平分宽度（适合 2–3 个 stat）", MinRenderer: 1, Props: []Prop{
		{Name: "children", Kind: KChildren, Required: true},
		{Name: "gap", Kind: KInt, Min: 0, Max: 32},
	}},
	{Type: "card", Title: "卡片", Doc: "带标题的分组容器", MinRenderer: 1, Props: []Prop{
		{Name: "title", Kind: KTpl},
		{Name: "subtitle", Kind: KTpl},
		{Name: "children", Kind: KChildren, Required: true},
	}},
	{Type: "text", Title: "文字", Doc: "纯文本，不支持 HTML / Markdown", MinRenderer: 1, Props: []Prop{
		{Name: "text", Kind: KTpl, Required: true},
		{Name: "style", Kind: KEnum, Enum: []string{"title", "subtitle", "body", "caption", "up", "down", "muted"}},
	}},
	{Type: "stat", Title: "数字", Doc: "大号数字 + 涨跌；A 股习惯红涨绿跌", MinRenderer: 1, Props: []Prop{
		{Name: "label", Kind: KTpl},
		{Name: "value", Kind: KValue, Required: true},
		{Name: "unit", Kind: KTpl},
		{Name: "digits", Kind: KInt, Min: 0, Max: 6, Doc: "value 是数字时的小数位（默认至多 2 位）"},
		{Name: "delta", Kind: KValue, Doc: "涨跌值"},
		{Name: "delta_format", Kind: KEnum, Enum: []string{"pct", "abs"}},
		{Name: "caption", Kind: KTpl},
		{Name: "tone", Kind: KEnum, Enum: []string{"auto", "up", "down", "neutral"}},
	}},
	{Type: "list", Title: "列表", Doc: "遍历数组，item 子组件里用 item / index 引用当前元素", MinRenderer: 1, Props: []Prop{
		{Name: "items", Kind: KExpr, Required: true},
		{Name: "item", Kind: KChild, Required: true},
		{Name: "max", Kind: KInt, Min: 1, Max: 50},
		{Name: "empty_text", Kind: KTpl},
	}},
	{Type: "table", Title: "表格", Doc: "rows 是对象数组，columns 指定列", MinRenderer: 1, Props: []Prop{
		{Name: "rows", Kind: KExpr, Required: true},
		{Name: "columns", Kind: KColumns, Required: true},
		{Name: "highlight_max", Kind: KStrList, Doc: "这些列的最大值高亮"},
		{Name: "max_rows", Kind: KInt, Min: 1, Max: 100},
		{Name: "empty_text", Kind: KTpl},
	}},
	{Type: "chart", Title: "图表", Doc: "折线 / 柱状 / 面积；x 是标签数组，series[].y 是数字数组", MinRenderer: 1, Props: []Prop{
		{Name: "kind", Kind: KEnum, Required: true, Enum: []string{"line", "bar", "area"}},
		{Name: "x", Kind: KExpr, Required: true},
		{Name: "series", Kind: KSeries, Required: true},
		{Name: "height", Kind: KInt, Min: 80, Max: 320},
	}},
	{Type: "kline", Title: "K 线", Doc: "bars 是 [{date,open,high,low,close}] 数组（market.daily_bars 的 items）", MinRenderer: 1, Props: []Prop{
		{Name: "bars", Kind: KExpr, Required: true},
		{Name: "height", Kind: KInt, Min: 120, Max: 360},
	}},
	{Type: "input", Title: "输入", Doc: "把 inputs 里的一个参数做成可编辑控件；用户改动自动保存、立即重算", MinRenderer: 1, Props: []Prop{
		{Name: "bind", Kind: KInputRef, Required: true},
		{Name: "style", Kind: KEnum, Enum: []string{"auto", "segmented", "dropdown"}},
	}},
}

var componentByType = func() map[string]*Component {
	m := map[string]*Component{}
	for i := range Components {
		c := &Components[i]
		c.Props = append(c.Props, visibleProp)
		m[c.Type] = c
	}
	return m
}()

// ComponentFor 查组件定义。
func ComponentFor(t string) *Component { return componentByType[t] }

// InputTypes 是 inputs 支持的参数类型。
var InputTypes = []string{"number", "text", "enum", "date", "bool", "list"}

// Icons 是 meta.icon 可选的内置图标名（客户端映射到 Material 图标）。
var Icons = []string{
	"apps", "insights", "show_chart", "candlestick", "bar_chart", "pie_chart", "calculate",
	"savings", "account_balance", "currency_exchange", "oil_barrel", "agriculture", "grain",
	"newspaper", "notifications", "cloud", "water_drop", "thermostat", "air", "sunny",
	"phishing", "set_meal", "water", "place", "map", "event", "timer", "scale", "science",
	"inventory", "checklist", "star",
}

var iconSet = func() map[string]bool {
	m := map[string]bool{}
	for _, i := range Icons {
		m[i] = true
	}
	return m
}()

// ColumnFormats 是 table 列格式。
var ColumnFormats = []string{"text", "num", "pct", "date"}

// Disclaimer 返回主题固定免责声明（spec 里的 meta.disclaimer 由服务端强制写入）。
func Disclaimer(topic string) string {
	switch topic {
	case "money":
		return "数据仅供参考，不构成投资建议"
	case "fishing":
		return "禁渔期与禁钓区以当地渔政部门公告为准"
	}
	return ""
}

// Topics 是支持小应用的主题。
var Topics = []string{"money", "fishing"}

// ValidTopic 判断主题。
func ValidTopic(t string) bool {
	for _, x := range Topics {
		if x == t {
			return true
		}
	}
	return false
}

// bannedWords：所有主题禁止出现在静态文案里的词。
var bannedWords = []string{"赌博", "博彩", "色情", "毒品", "枪支", "代开发票", "洗钱"}

// bannedByTopic：主题专属禁用词。喜爱钱不得出现荐股 / 买卖建议措辞（无投资咨询资质）；
// 喜爱钓鱼不得出现违法捕捞方式。
var bannedByTopic = map[string][]string{
	"money": {"买入", "卖出", "加仓", "减仓", "清仓", "满仓", "抄底", "逃顶", "目标价",
		"稳赚", "必涨", "必跌", "保本", "荐股", "建议买", "建议卖", "推荐买", "推荐卖", "内幕", "翻倍"},
	"fishing": {"电鱼", "炸鱼", "毒鱼", "绝户网", "偷钓"},
}

// BannedWords 返回某主题的禁用词（排序）。
func BannedWords(topic string) []string {
	out := append([]string{}, bannedWords...)
	out = append(out, bannedByTopic[topic]...)
	sort.Strings(out)
	return out
}
