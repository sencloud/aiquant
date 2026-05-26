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
	Guests           []PersonaRef    // 当场嘉宾
	Phase            string          // pre/intraday/post
	Now              time.Time
	CandidatePool    []CandidateStock // 当日热门股票池(供主持人切换 focus 时挑选)
	History          []Message        // 最近 N 条消息(给上下文)
	CurrentFocus     string           // 当前焦点(可空)
	CurrentFocusName string
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
	b.WriteString(HostStyle)
	b.WriteString("\n\n")
	b.WriteString("# 输出契约(必须严格遵守)\n")
	b.WriteString("你的每一次发言都必须以一个**纯 JSON 对象**返回,前后不要任何解释或 markdown 围栏。\n")
	b.WriteString("JSON 字段:\n")
	b.WriteString(`{
  "action": "open|ask|switch|react_prompt|close",
  "target_persona": "<嘉宾 persona id,见下方嘉宾列表>(action 为 ask/switch/react_prompt 时必填)",
  "focus_symbol": "<ts_code 如 600519.SH>(action 为 ask/switch 时必填)",
  "focus_name": "<股票中文名>(action 为 ask/switch 时必填)",
  "content": "<主持人这次的口播,20-80 字,口语化,可以提问/调侃/串联前文>"
}`)
	b.WriteString("\n\n# Action 含义\n")
	b.WriteString("- `open`:开场白(全场第一条)。content 含问候 + 介绍今天主题 + 第一个话题切入。这条**也必须填 focus_symbol/focus_name + target_persona**,等于「我点名第一位嘉宾就这只票发言」。\n")
	b.WriteString("- `ask`:就**当前 focus**点名某嘉宾发言。\n")
	b.WriteString("- `switch`:**切换 focus 到新股票**,顺便点名。每聊 4-8 条左右就应切换,避免一只票聊太久。\n")
	b.WriteString("- `react_prompt`:不指定新焦点,诱导嘉宾之间互动(如「小马你同意老张刚才的看法吗」)。当感觉某嘉宾观点有争议时用。\n")
	b.WriteString("- `close`:收尾陈词(全场最后一条)。当 message_count ≥ 软上限时主动出此 action。content 含致谢 + 总结 + 下场预告。**close 时 focus_symbol/target_persona 必须留空**。\n\n")
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

	if len(in.CandidatePool) > 0 {
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
	} else {
		b.WriteString("# 当前是开场第一条,请用 open action 开场。\n")
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
	case "open", "ask", "switch", "react_prompt", "close":
		// ok
	default:
		return nil, fmt.Errorf("unknown action: %q", act.Action)
	}
	if strings.TrimSpace(act.Content) == "" {
		return nil, errors.New("empty content")
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
