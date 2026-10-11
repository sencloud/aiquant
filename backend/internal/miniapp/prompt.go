package miniapp

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/sencloud/finme-backend/internal/miniapp/xel"
)

var topicNames = map[string]string{"money": "喜爱钱（量化 / 行情 / 期货 / 基金）", "fishing": "喜爱钓鱼（淡水钓）"}

// SystemPrompt 根据组件目录、本主题数据源和函数表生成系统提示。能力清单全部由
// 注册表自动生成：新增数据源后模型自动就知道，不用手改 prompt。
func SystemPrompt(topic string, reg *Registry, example *Template) string {
	var b strings.Builder
	fmt.Fprintf(&b, `你是「喜爱」App 的小应用工坊。用户在「%s」主题里，用对话描述想要的小工具，你把它做成一个声明式的小应用 spec（JSON）。
spec 由 App 内置的原生组件渲染，数据只能来自下面列出的数据源。你不能写代码、不能访问任意网址、不能执行脚本。

## 你的输出
只输出一个 JSON 对象，三选一：
1. 信息不够、无法合理假设时，最多问一次、最多 3 个问题，每个问题给 2–4 个选项：
   {"action":"ask","message":"一句话说明","questions":[{"q":"问题","options":["选项1","选项2"]}]}
2. 可以做时，输出完整 spec：
   {"action":"spec","summary":"这次做了 / 改了什么（≤40 字）","spec":{...}}
3. 需求超出能力（自动下单、交易、爬网页、任意网址、发消息、定时推送、聊天机器人、违法内容等）时：
   {"action":"refuse","message":"说明哪部分做不到，并给出最接近的可行做法"}
优先直接做：能用合理默认值的就用默认值，并把关键参数做成 inputs（用户之后可以自己改），不要为小事反复提问。
修改已有小应用时，在当前 spec 基础上改，输出改完后的完整 spec。

## spec 结构
{
  "schema": "%s", "topic": "%s",
  "meta": {"title": "≤20 字", "icon": "图标名", "summary": "≤60 字", "card_size": "small|medium|large"},
  "inputs": {"参数名": {"type": "number|text|enum|date|bool|list", "label": "≤12 字", "default": 默认值, ...}},
  "data": {"别名": {"source": "数据源 id", "params": {"参数": 字面量或"=表达式"}, "each": "=数组表达式（可选，最多 5 项，params 里用 item）"}},
  "computed": {"名字": "表达式"},
  "refresh": {"on_open": true},
  "card_view": 组件（发现页上的小卡片，最多 3 个数字 / 一句话，建议 row + stat）,
  "layout": 组件（打开后的完整界面，通常是 column）
}
- inputs：number 可带 min/max/step/unit；enum 要 options（字符串数组）；list 要 item（字段 → {"type":"text|number"}）和 max_items（≤10）；date 默认 "" 表示今天。
- data：同一层并发取数；第二层可以用第一层结果（例如先 futures.dominant 拿 ts_code，再用 "=data.main.ts_code" 取行情）；最多两层、最多 %d 个绑定。
- computed：可以互相引用（不能循环）；在表达式里直接用名字引用（例如 px.last），不用加前缀。

## 表达式（受限，不是 JavaScript）
- 写在 "=..." 里（组件属性、data 参数），或写在字符串模板 "文字 ${表达式} 文字" 里。
- 可用名字：inputs.xxx、data.别名.字段、computed 里的名字、state；list 的 item 子组件和 map/filter 里用 item、index；zip_with 里用 x、y。
- 运算：+ - * / %% 比较 == != && || ! 三元 a ? b : c 空值合并 a ?? b；数组 [..]、对象 {'k': v}、下标 a[0]、a[-1]（最后一个）。
- 访问不存在的字段得到 null，不会报错；除以 0 得 null。
- 函数（只能用这些）：
`, topicNames[topic], SchemaID, topic, MaxBindings)
	for _, d := range xel.FuncDocs() {
		b.WriteString("  - " + d + "\n")
	}
	b.WriteString("- map/filter/sum/avg/count/sort_by/group_sum 的第二个参数可以写字段名字符串（'close'），等价于 item.close。\n\n## 组件（只能用这些，属性不能多写）\n")
	for _, c := range Components {
		var props []string
		for _, p := range c.Props {
			if p.Name == "visible" {
				continue
			}
			s := p.Name + ":" + string(p.Kind)
			if len(p.Enum) > 0 {
				s += "(" + strings.Join(p.Enum, "|") + ")"
			}
			if p.Kind == KInt {
				s += fmt.Sprintf("(%d–%d)", p.Min, p.Max)
			}
			if p.Required {
				s += "*"
			}
			props = append(props, s)
		}
		fmt.Fprintf(&b, "- %s（%s）：%s。属性 %s\n", c.Type, c.Title, c.Doc, strings.Join(props, ", "))
	}
	b.WriteString(`所有组件都可加 visible（"=条件"）。属性类型：template=可含 ${} 的字符串；expr=必须是 "=表达式"；value=字面量或 "=表达式"；带 * 的必填。
table 的 columns 是 [{"key":"字段","title":"列名","format":"text|num|pct|date","digits":0-6}]；chart 的 series 是 [{"name":"名字","y":"=数字数组"}]。
组件总数 ≤ 40，嵌套 ≤ 8 层。图标 icon 可选：` + strings.Join(Icons, " / ") + "\n\n## 本主题可用数据源（只能用这些）\n")
	for _, s := range reg.ForTopic(topic) {
		var ps []string
		for _, p := range s.Params {
			x := p.Name + ":" + p.Type
			if p.Required {
				x += "*"
			}
			if p.Doc != "" {
				x += "（" + p.Doc + "）"
			}
			ps = append(ps, x)
		}
		params := "无参数"
		if len(ps) > 0 {
			params = "参数 " + strings.Join(ps, "；")
		}
		priv := ""
		if s.UserScoped {
			priv = "【用户私人数据，只读当前用户】"
		}
		fmt.Fprintf(&b, "- %s：%s%s。%s。输出示例 %s\n", s.ID, s.Doc, priv, params, s.Output)
	}
	b.WriteString("\n## 规则\n")
	b.WriteString("- 文字简洁、口语化，用简体中文。标题不要加“小应用”字样。\n")
	b.WriteString("- 不要在文字里编造数据；所有数字都来自数据源或用户输入的计算。\n")
	if topic == "money" {
		b.WriteString("- 这是数据工具，不是投资建议：禁止出现买入、卖出、加仓、减仓、抄底、目标价、稳赚、必涨等措辞；可以展示价格、涨跌、价差、均值偏离等客观数据。\n")
		b.WriteString("- 期货先用 futures.dominant 拿主力合约 ts_code，不要自己编合约月份。\n")
	} else {
		b.WriteString("- 不要出现电鱼、炸鱼、毒鱼、绝户网等违法捕捞方式；涉及禁渔时提示以当地渔政公告为准。\n")
	}
	b.WriteString("- 列表、表格、图表、K 线的表达式必须对上数据源输出示例里的字段名。\n")
	if example != nil {
		ex, _ := json.Marshal(example.Spec)
		fmt.Fprintf(&b, "\n## 完整示例（%s）\n%s\n", example.Title, ex)
	}
	return b.String()
}
