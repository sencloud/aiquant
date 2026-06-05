package live

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/llm"
)

// HostAction 是主持人 LLM 决策的输出契约。每轮主持人发言由这个结构驱动:
//
//   * Action 决定该条消息的 Role(open/ask/switch/react_prompt/close)
//   * TargetPersona 当 Action ∈ {ask, switch, react_prompt} 时必填
//   * FocusSymbol / FocusName 当 Action ∈ {ask, switch} 时必填
//   * Content 是主持人实际开口的话(口语化、20-80 字)
type HostAction struct {
	Action        string `json:"action"`
	TargetPersona string `json:"target_persona,omitempty"`
	FocusSymbol   string `json:"focus_symbol,omitempty"`
	FocusName     string `json:"focus_name,omitempty"`
	Content       string `json:"content"`
}

// HostPlanner 用 LLM 决策主持人下一步动作。
//
// 设计取舍:
//   * 不调 tools(host 只做编排,不查数据,避免每条决策都 10+ 秒延迟)
//   * 单轮 ChatStream + 严格 JSON 契约
//   * 候选股票池由 runner 在开播时提前拉好(20 只热门),作为 prompt 上下文塞进去
type HostPlanner struct {
	llm *llm.DeepSeek
}

func NewHostPlanner(d *llm.DeepSeek) *HostPlanner {
	return &HostPlanner{llm: d}
}

// PlanInput 是 Plan 的入参。
type PlanInput struct {
	Host             PersonaRef       // 本场主持人(决定 prompt 里"你是谁")
	Guests           []PersonaRef     // 当场嘉宾
	Phase            string           // pre/intraday/post
	Now              time.Time
	CandidatePool    []CandidateStock // 当日热门股票池(供主持人切换 focus 时挑选)
	History          []Message        // 最近 N 条消息(给上下文)
	CurrentFocus     string           // 当前焦点(可空)
	CurrentFocusName string
	// PinnedSymbol 非空表示本场是"指定个股专场"(用户手动建的房间):
	// 主持人必须全程锁定这只票,禁止 switch 到候选池其它股票,候选池也不展示。
	PinnedSymbol     string
	PinnedName       string
	// PendingUserText 非空表示观众(房间创建者)刚发了一条尚未被回应的话,
	// 主持人本轮必须优先回应它(点名嘉宾或自己接话)。
	PendingUserText  string
	PendingUserName  string
	MessageCount     int             // 房间至今总消息数(用于判断该不该收尾)
	SoftCloseAfterN  int             // 软上限:超过这个数主持人会倾向 close
}

// CandidateStock 是一只候选股票的轻量元信息。
type CandidateStock struct {
	Symbol string `json:"symbol"`
	Name   string `json:"name"`
	Reason string `json:"reason,omitempty"` // 「龙虎榜净流入 4.2 亿」等
}

// Plan 调一次 LLM 拿到 HostAction。
func (p *HostPlanner) Plan(ctx context.Context, in PlanInput) (*HostAction, error) {
	if p.llm == nil {
		return nil, errors.New("host planner: llm not configured")
	}
	sys := p.systemPrompt(in)
	user := p.userPrompt(in)

	msgs := []llm.MessageWithTools{
		{Role: "system", Content: sys},
		{Role: "user", Content: user},
	}

	var finalText string
	err := p.llm.ChatStream(ctx, llm.StreamRequest{
		Messages:    msgs,
		Temperature: 0.7, // 主持人想要点变化,不希望每轮都问同一只
	}, func(ev llm.StreamEvent) error {
		if ev.Type == "done" {
			finalText = ev.FinalText
		}
		if ev.Type == "error" {
			return errors.New(ev.ErrorMsg)
		}
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("host plan llm: %w", err)
	}
	act, err := parseHostAction(finalText)
	if err != nil {
		return nil, fmt.Errorf("host plan parse: %w (raw=%q)", err, snippet(finalText, 200))
	}
	return act, nil
}

func (p *HostPlanner) systemPrompt(in PlanInput) string {
	var b strings.Builder

	// 本场主持人的人设(从 Hosts 池查回 Style)
	style := FindHostStyle(in.Host.ID)
	if style == "" {
		// fallback:Hosts 池意外缺少该 id,给一个最小化人设让 LLM 仍可工作
		style = fmt.Sprintf("你是「%s」,本场直播间主持人,沉稳控场,引导嘉宾对话。", in.Host.Name)
	}
	b.WriteString(style)
	b.WriteString("\n\n")

	b.WriteString("# 输出契约(必须严格遵守)\n")
	b.WriteString("你的每一次发言都必须以一个**纯 JSON 对象**返回,前后不要任何解释或 markdown 围栏。\n")
	b.WriteString("JSON 字段:\n")
	b.WriteString(`{
  "action": "open|ask|switch|topic|react_prompt|close",
  "target_persona": "<嘉宾 persona id,见下方嘉宾列表>(action 为 ask/switch/topic/react_prompt 时必填)",
  "focus_symbol": "<ts_code 如 600519.SH>(action 为 ask/switch 时必填,其他时禁止填)",
  "focus_name": "<股票中文名>(action 为 ask/switch 时必填,其他时禁止填)",
  "content": "<主持人这次的口播,30-90 字,口语化,可以提问/调侃/串联前文,可适度用 emoji>"
}`)
	b.WriteString("\n\n# Action 含义\n")
	b.WriteString("- `open`:开场白(全场第一条)。content 含问候 + 介绍今天主题 + 第一个话题切入。这条**也必须填 focus_symbol/focus_name + target_persona**,等于「我点名第一位嘉宾就这只票发言」。\n")
	b.WriteString("- `ask`:就**当前 focus**点名某嘉宾发言。focus_symbol/focus_name 沿用当前焦点(也可重新填一次)。\n")
	b.WriteString("- `switch`:**切换 focus 到新股票**,顺便点名。一只票聊 3-5 条就应切换,避免单股聊太久。\n")
	b.WriteString("- `topic`:**抛一个非个股的宏观/行业/国际/政策话题**,点名嘉宾发表看法。例如:「美联储下次议息」「半导体行业景气」「房地产新政」「日股创新高」「AI 算力投资」等。**focus_symbol/focus_name 必须留空**,这是和 ask 的关键区别。每 4-6 条之间至少穿插 1 条 topic,否则全场聊个股会枯燥。\n")
	b.WriteString("- `react_prompt`:不指定新焦点,诱导嘉宾之间互动(如「巴菲特你同意达里奥刚才的看法吗」)。focus_symbol/focus_name 沿用当前焦点。当感觉某嘉宾观点有争议时用。\n")
	b.WriteString("- `close`:收尾陈词(全场最后一条)。当 message_count ≥ 软上限时主动出此 action。content 含致谢 + 总结 + 下场预告。**close 时 focus_symbol/target_persona 必须留空**。\n\n")

	b.WriteString("# 内容禁忌(违反将被丢弃后重新生成)\n")
	b.WriteString("- 严禁与你最近 3 条发言**雷同或极度相似**(开头 40 字符不能与之前任何一条一样),换角度、换嘉宾、换股票或换话题\n")
	b.WriteString("- 不要给买卖建议(那是嘉宾的活)\n")
	b.WriteString("- 不要长篇大论自我表达\n")
	b.WriteString("- 不要一直问同一只票超过 4 轮,要主动 switch 或 topic\n\n")

	if in.PinnedSymbol != "" {
		b.WriteString("\n# 本场是「指定个股专场」(重要)\n")
		b.WriteString(fmt.Sprintf("- 本场全程锁定 %s(%s)。所有 ask/switch/react_prompt 的 focus 都必须是这只票。\n",
			in.PinnedName, in.PinnedSymbol))
		b.WriteString("- **严禁 switch 到其它股票**,也不要谈与它无关的个股。\n")
		b.WriteString("- 可以用 `topic` 穿插与它强相关的宏观 / 行业 / 政策话题(如所在行业景气、上下游、对标公司),但聊完要拉回这只票。\n\n")
	}

	if in.PendingUserText != "" {
		b.WriteString("\n# 有观众提问(最高优先级)\n")
		b.WriteString("- 直播间的观众刚发言提问,本轮你**必须优先回应**:用 `ask`(或 `react_prompt`)点名一位最合适的嘉宾,针对观众的问题作答;content 里先简短转述/承接观众的问题再点名。\n")
		b.WriteString("- **不要无视观众**,也不要在有未回应观众提问时 close。\n\n")
	}

	b.WriteString("# 嘉宾列表(target_persona 只能用以下 id)\n")
	for _, g := range in.Guests {
		b.WriteString(fmt.Sprintf("- `%s` (%s)\n", g.ID, g.Name))
	}
	return b.String()
}

func (p *HostPlanner) userPrompt(in PlanInput) string {
	var b strings.Builder
	phaseLabel := map[string]string{
		PhasePre: "盘前", PhaseIntraday: "盘中", PhasePost: "盘后",
	}[in.Phase]
	if phaseLabel == "" {
		phaseLabel = in.Phase
	}
	b.WriteString(fmt.Sprintf("当前时间:%s(北京时间,%s时段)\n",
		in.Now.Format("2006-01-02 15:04"), phaseLabel))
	b.WriteString(fmt.Sprintf("房间至今消息数:%d(软上限 %d,达到后请考虑 close)\n\n",
		in.MessageCount, in.SoftCloseAfterN))

	if in.CurrentFocus != "" {
		b.WriteString(fmt.Sprintf("当前焦点股票:%s(%s)\n\n",
			in.CurrentFocusName, in.CurrentFocus))
	} else {
		b.WriteString("当前焦点股票:无\n\n")
	}

	if in.PendingUserText != "" {
		name := in.PendingUserName
		if name == "" {
			name = "观众"
		}
		b.WriteString(fmt.Sprintf("‼️ 观众【%s】刚提问(请本轮优先回应,点名嘉宾作答):\n  「%s」\n\n",
			name, condense(in.PendingUserText, 200)))
	}

	if len(in.CandidatePool) > 0 && in.PinnedSymbol == "" {
		b.WriteString("候选股票池(可切换 focus 时从中选,优先选还没聊过的):\n")
		for _, c := range in.CandidatePool {
			reason := c.Reason
			if reason == "" {
				reason = "热门"
			}
			b.WriteString(fmt.Sprintf("- %s(%s)— %s\n", c.Name, c.Symbol, reason))
		}
		b.WriteString("\n")
	}

	if len(in.History) > 0 {
		b.WriteString("# 最近对话历史(由旧到新):\n")
		for _, m := range in.History {
			line := fmt.Sprintf("[%s · %s]", m.PersonaName, roleLabel(m.Role))
			if m.FocusSymbol.Valid && m.FocusSymbol.String != "" {
				focusName := m.FocusSymbol.String
				if m.FocusName.Valid && m.FocusName.String != "" {
					focusName = m.FocusName.String
				}
				line += fmt.Sprintf("(聊%s)", focusName)
			}
			b.WriteString(line + "\n  ")
			b.WriteString(condense(m.Content, 200))
			b.WriteString("\n\n")
		}

		// 列出你最近 3 条 host 发言全文 — 让 LLM 直观看到"不要写跟这些一样"
		b.WriteString("# 你(主持人)最近 3 条发言(禁止与之雷同):\n")
		shown := 0
		for i := len(in.History) - 1; i >= 0 && shown < 3; i-- {
			m := in.History[i]
			if m.Persona != in.Host.ID {
				continue
			}
			shown++
			b.WriteString(fmt.Sprintf("  ⛔ %s\n", condense(m.Content, 120)))
		}
		b.WriteString("\n")
	} else {
		if in.PinnedSymbol != "" {
			b.WriteString(fmt.Sprintf(
				"# 当前是开场第一条。本场为用户**指定股票【%s(%s)】的专场**:\n"+
					"请用 open action 开场,focus_symbol 必须填 \"%s\"、focus_name 填 \"%s\","+
					"开场即点名第一位嘉宾针对这只票发言,整场围绕它展开。\n",
				in.PinnedName, in.PinnedSymbol, in.PinnedSymbol, in.PinnedName))
		} else {
			b.WriteString("# 当前是开场第一条,请用 open action 开场。\n")
		}
	}
	b.WriteString("\n请给出你下一条主持人发言的 JSON。")
	return b.String()
}

// parseHostAction 解析 LLM 返回的 JSON(允许前后空白 / 单层 ```json 围栏)。
func parseHostAction(raw string) (*HostAction, error) {
	s := strings.TrimSpace(raw)
	// 去掉 ```json ... ``` 围栏
	if strings.HasPrefix(s, "```") {
		s = strings.TrimPrefix(s, "```json")
		s = strings.TrimPrefix(s, "```")
		s = strings.TrimSuffix(s, "```")
		s = strings.TrimSpace(s)
	}
	// 截到第一个 { ... 最后一个 } 之间
	l := strings.Index(s, "{")
	r := strings.LastIndex(s, "}")
	if l < 0 || r < 0 || r <= l {
		return nil, errors.New("no JSON object found")
	}
	s = s[l : r+1]
	var act HostAction
	if err := json.Unmarshal([]byte(s), &act); err != nil {
		return nil, err
	}
	act.Action = strings.ToLower(strings.TrimSpace(act.Action))
	switch act.Action {
	case "open", "ask", "switch", "topic", "react_prompt", "close":
		// ok
	default:
		return nil, fmt.Errorf("unknown action: %q", act.Action)
	}
	if strings.TrimSpace(act.Content) == "" {
		return nil, errors.New("empty content")
	}
	// 契约保险:topic / close 不带 focus(LLM 偶尔违反约定,这里硬清空)
	if act.Action == "topic" || act.Action == "close" {
		act.FocusSymbol = ""
		act.FocusName = ""
	}
	return &act, nil
}

func roleLabel(role string) string {
	switch role {
	case RoleHostOpen:
		return "开场"
	case RoleHostAsk:
		return "提问"
	case RoleHostSwitch:
		return "切话题"
	case RoleHostClose:
		return "收尾"
	case RoleGuestAnswer:
		return "应答"
	case RoleGuestReact:
		return "插话"
	case RoleUser:
		return "观众提问"
	}
	return role
}

func condense(s string, max int) string {
	s = strings.TrimSpace(s)
	if len([]rune(s)) <= max {
		return s
	}
	rs := []rune(s)
	return string(rs[:max]) + "…"
}

func snippet(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}
