package live

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

// GuestSpeaker 用 LLM 生成嘉宾应答。
//
// 与 host_planner 区别:
//   * host 是决策(JSON 输出),不调 tools
//   * guest 是观点(自然语言),**必须调 tools** 拉真实数据后才能开口
//
// guest 复用 Executor(它就是 tool calling loop 的封装),最多 5 轮 tool calls。
type GuestSpeaker struct {
	exec *Executor
}

func NewGuestSpeaker(e *Executor) *GuestSpeaker {
	return &GuestSpeaker{exec: e}
}

// SpeakInput 是 Speak 的入参。
type SpeakInput struct {
	Guest        PersonaRef
	Phase        string
	Now          time.Time
	FocusSymbol  string
	FocusName    string
	History      []Message // 近 N 条上下文(含 host 刚问的那条)
	HostQuestion string    // host 刚问的具体内容(冗余,但显式提示效果更好)
	IsReact      bool      // true=对前一条嘉宾发言插话/反驳;false=正式回答 host
	ReactTo      string    // IsReact 时:前一条嘉宾的名字(便于自然引用「我同意/不同意 老张刚说的」)
}

// SpeakResult 是 Speak 的返回。
type SpeakResult struct {
	Content     string
	Annotations []Annotation // 可空 — 嘉宾本次发言提到的 K 线价位标注
	ToolCalls   int
	DurationMs  int64
}

// Speak 生成嘉宾应答。返回的 Content 已 trim。
//
// 输出契约:LLM 最终回答必须是 JSON {"content","annotations":[...]};
// 解析失败时 fallback 把整段当 content,annotations 留空 — 不影响直播继续。
func (s *GuestSpeaker) Speak(ctx context.Context, in SpeakInput) (*SpeakResult, error) {
	if s.exec == nil {
		return nil, errors.New("guest speaker: executor not configured")
	}
	style := FindGuestStyle(in.Guest.ID)
	if style == "" {
		return nil, fmt.Errorf("guest speaker: unknown persona id %q", in.Guest.ID)
	}

	sys := s.systemPrompt(in.Guest, style)
	user := s.userPrompt(in)

	res, err := s.exec.Run(ctx, sys, user)
	if err != nil {
		return nil, fmt.Errorf("guest exec: %w", err)
	}
	raw := strings.TrimSpace(res.FinalText)
	if raw == "" {
		return nil, errors.New("guest speaker: empty output")
	}

	content, annots := parseGuestOutput(raw)
	if content == "" {
		return nil, errors.New("guest speaker: empty content after parse")
	}
	return &SpeakResult{
		Content:     content,
		Annotations: annots,
		ToolCalls:   res.ToolCalls,
		DurationMs:  res.DurationMs,
	}, nil
}

// parseGuestOutput 解析 LLM 输出:
//
//	* 期望:JSON {"content": "...", "annotations": [{type,price,label}, ...]}
//	* 容错 1:外层 ```json ... ``` 围栏 → 剥掉
//	* 容错 2:JSON 解析失败 → 把整段当 content,annotations 留空(直播继续,只是没有 K 线标注)
//	* 验证 annotations 每条 type / price / label 合法,过滤掉非法 type
func parseGuestOutput(raw string) (string, []Annotation) {
	s := strings.TrimSpace(raw)
	// 剥 ```json 围栏
	if strings.HasPrefix(s, "```") {
		s = strings.TrimPrefix(s, "```json")
		s = strings.TrimPrefix(s, "```")
		s = strings.TrimSuffix(s, "```")
		s = strings.TrimSpace(s)
	}

	// 截取第一个 { 到最后一个 }
	l := strings.Index(s, "{")
	r := strings.LastIndex(s, "}")
	if l < 0 || r < 0 || r <= l {
		// 完全不是 JSON — 整段当 content
		return strings.TrimSpace(raw), nil
	}
	body := s[l : r+1]

	var out struct {
		Content     string       `json:"content"`
		Annotations []Annotation `json:"annotations"`
	}
	if err := json.Unmarshal([]byte(body), &out); err != nil {
		// JSON 形似但解析失败 — 整段当 content,标注丢弃
		return strings.TrimSpace(raw), nil
	}
	content := strings.TrimSpace(out.Content)
	if content == "" {
		// 字段没有 content — fallback 把整段当 content
		content = strings.TrimSpace(raw)
	}

	// 验证 annotations:type 必须合法、price 必须正、label 非空
	cleaned := make([]Annotation, 0, len(out.Annotations))
	for _, a := range out.Annotations {
		t := strings.ToLower(strings.TrimSpace(a.Type))
		if !AnnotationAllowedTypes[t] {
			continue
		}
		if a.Price <= 0 {
			continue
		}
		lbl := strings.TrimSpace(a.Label)
		if lbl == "" {
			continue
		}
		// 截断到 8 个 rune,避免 LLM 写长 label
		rs := []rune(lbl)
		if len(rs) > 8 {
			lbl = string(rs[:8])
		}
		cleaned = append(cleaned, Annotation{
			Type:  t,
			Price: a.Price,
			Label: lbl,
		})
	}
	return content, cleaned
}

func (s *GuestSpeaker) systemPrompt(guest PersonaRef, style string) string {
	var b strings.Builder
	b.WriteString(fmt.Sprintf("你正在做客一个国际财经直播间,你的人设是「%s」。\n\n", guest.Name))
	b.WriteString(style)
	b.WriteString("\n\n# 直播间共同规则\n")
	b.WriteString("- 涉及具体数字(股价/涨跌幅/估值/财报)时**必须先用工具拉真实数据**,不准凭记忆给数字\n")
	b.WriteString("- 纯宏观/国际/政策/行业逻辑性讨论可以**不用工具**,直接基于你的人设方法论发表看法\n")
	b.WriteString("- 措辞像直播间发言而非研报。可适度口语化,但不要刻意填充语气词\n")
	b.WriteString("- 篇幅 100-260 字,**简短有力**优于冗长\n\n")

	b.WriteString("# 关键铁律(违反将让你的发言被丢弃)\n\n")

	b.WriteString("**1. 严禁复读自己 — 不许把人设方法论当固定台词重复念**\n")
	b.WriteString("   - 你是一个真人,不是 chatbot。真人不会每次开口都讲一遍\"我的投资框架\"\n")
	b.WriteString("   - **不要重复你这场已经说过的话、案例、口头禅、关键句**(下方会列出)\n")
	b.WriteString("   - 把方法论当**默认背景**而不是**台词**:不要总说\"按我的 X 思维\",直接基于此思维给具体看法\n")
	b.WriteString("   - **不要每次开场都讲一个寓言/类比/箴言**;一场直播里这类比喻最多用 1 次\n\n")

	b.WriteString("**2. 每次发言必须有\"本次特有内容\" — 至少 2 个具体锚点**\n")
	b.WriteString("   - 锚点 = 本次工具实际拉到的具体数字 / 新闻标题 / 事件名 / 行业数据\n")
	b.WriteString("   - 例如不要只说\"估值偏贵\",要说\"**PE 38 倍,处于近 5 年 85% 分位**\"\n")
	b.WriteString("   - 例如不要只说\"消费在改善\",要说\"**社零 4 月同比 +4.5%,化妆品 +6.8%**\"\n")
	b.WriteString("   - 没有具体锚点的纯方法论表态会被视为套话\n\n")

	b.WriteString("**3. 严禁鹦鹉学舌别人 — 不许复述其他嘉宾的话**\n")
	b.WriteString("   - 不要说\"刚才 XX 说...我也这么认为\"这种空洞跟话\n")
	b.WriteString("   - 可以**简短表态后**立刻给**自己独立观点**(同意+补充新角度 / 反驳+给反例 / 换维度切入)\n\n")

	b.WriteString("**4. 给意见要落到具体价位数字,不要口水话**\n")
	b.WriteString("   - 涉及买卖判断:支撑位 / 压力位 / 止损位 / 目标价 都给具体数字\n")
	b.WriteString("   - 禁止\"等回踩\"\"逢低介入\"\"逢高减仓\"这类零信息量表达\n\n")

	b.WriteString("# 富文本格式(content 字段内可用,但克制)\n")
	b.WriteString("- 可以用 `**加粗**` 强调关键数字 / 关键判断,例如:`**PE 23 倍**`、`**短线压力位 1850**`\n")
	b.WriteString("- 可以用 `- 项目` 列举要点(最多 3-4 项,不要长列表)\n")
	b.WriteString("- 可适度使用 emoji 表达情绪/方向(如 📈 📉 ⚠️ 💡 🎯),每段最多 1-2 个,不要堆\n")
	b.WriteString("- **禁止**用 `#` `##` 大标题(这是聊天,不是报告)\n")
	b.WriteString("- **禁止**用 markdown 表格 / 代码块\n")
	b.WriteString("- **禁止**在 content 内部加前缀「我:」之类的角色标记。直接说话。\n\n")

	// ── 输出契约(JSON)— 嘉宾发言与 K 线共振的关键 ──
	b.WriteString("# 输出契约(最终回答必须严格遵守 — 中间 tool calls 不受此约束)\n")
	b.WriteString("你最后一次回答必须是一个**纯 JSON 对象**,前后无任何说明或 markdown 围栏。结构:\n")
	b.WriteString("```\n")
	b.WriteString(`{
  "content": "<你的发言原文,markdown + emoji 允许,即上面规定的口语化点评>",
  "annotations": [
    {"type": "support|resistance|stop|target|note", "price": <number>, "label": "<≤8字短标签>"}
  ]
}`)
	b.WriteString("\n```\n\n")

	b.WriteString("# annotations 字段说明 — 这是「K 线主图共振」的核心\n")
	b.WriteString("- 你的发言里**只要提到任何具体价位**(支撑位 / 压力位 / 止损位 / 目标价 / 关键位 / 当前价等),\n")
	b.WriteString("  就必须在 annotations 数组里同时给出对应条目,前端会**自动在 K 线主图画出水平线 + label**\n")
	b.WriteString("- type 取值:\n")
	b.WriteString("    `support` 支撑位(K 线主图画绿色实线)\n")
	b.WriteString("    `resistance` 压力位(画红色实线)\n")
	b.WriteString("    `stop` 止损位(画橙色虚线)\n")
	b.WriteString("    `target` 目标位(画青色虚线)\n")
	b.WriteString("    `note` 其他重要位/关键位(画黄色虚线)\n")
	b.WriteString("- price 是浮点数,**单位与个股股价一致**(不要给百分比、不要单位字符)\n")
	b.WriteString("- label ≤ 8 个字,如「短线压力」「中期止损」「TP1」等;前端会自动拼前缀 `<你名字>·<label>`\n")
	b.WriteString("- 如果本次发言是纯宏观/纯方法论/纯闲聊**没提到具体价位**,annotations 留空数组 `[]`\n")
	b.WriteString("- annotations 最多 4 条(超出忽略)\n\n")

	b.WriteString("# 关于 content 字段内的「价位口播」\n")
	b.WriteString("- 你可以照常在 content 里口播价位(例如「**短线支撑 128.5,目标 145**」),\n")
	b.WriteString("  这样观众既能在文字里看到、又能在 K 线上看到 — 两边对齐是设计目标\n")
	return b.String()
}

func (s *GuestSpeaker) userPrompt(in SpeakInput) string {
	var b strings.Builder
	phaseLabel := map[string]string{
		PhasePre: "盘前", PhaseIntraday: "盘中", PhasePost: "盘后",
	}[in.Phase]
	if phaseLabel == "" {
		phaseLabel = in.Phase
	}
	b.WriteString(fmt.Sprintf("当前时间:%s(%s时段)\n", in.Now.Format("2006-01-02 15:04"), phaseLabel))
	if in.FocusSymbol != "" {
		display := in.FocusSymbol
		if in.FocusName != "" {
			display = in.FocusName + "(" + in.FocusSymbol + ")"
		}
		b.WriteString(fmt.Sprintf("讨论的票:%s\n\n", display))
	} else {
		// topic 类话题(无具体个股)— 用主持人最近一条话作为话题指引
		b.WriteString("本轮是非个股的宏观/行业/国际/政策话题,**不必调 get_quote 拉个股数据**;\n")
		b.WriteString("可以基于你的人设方法论,结合工具(search_chinese_news / search_global_events / get_industry_money_flow 等)谈大势与判断。\n\n")
	}

	if len(in.History) > 0 {
		b.WriteString("# 直播间近期对话\n")
		for _, m := range in.History {
			line := fmt.Sprintf("[%s] ", m.PersonaName)
			b.WriteString(line)
			b.WriteString(condense(m.Content, 220))
			b.WriteString("\n\n")
		}

		// 列出"你自己"这场已经发过的内容 — 显式禁区,防止 LLM 把人设当固定台词
		ownLines := []Message{}
		for _, m := range in.History {
			if m.Persona == in.Guest.ID {
				ownLines = append(ownLines, m)
			}
		}
		if len(ownLines) > 0 {
			b.WriteString("# ⛔ 你(本人)本场已经说过的内容,**禁止与之雷同 / 复读 / 换皮重说**:\n")
			// 倒序取最近 3 条,前面长度不超过 150
			start := len(ownLines) - 3
			if start < 0 {
				start = 0
			}
			for _, m := range ownLines[start:] {
				b.WriteString(fmt.Sprintf("  - %s\n", condense(m.Content, 150)))
			}
			b.WriteString("\n要求:本次发言换一个角度 / 换一组数据 / 换一个具体案例,不要再讲已经讲过的方法论与口头禅。\n\n")
		}
	}

	if in.IsReact {
		if in.ReactTo != "" {
			b.WriteString(fmt.Sprintf("# 你的任务\n请就「%s」刚才的观点表态(同意/反驳/补充新角度)。\n", in.ReactTo))
		} else {
			b.WriteString("# 你的任务\n请基于直播间最近的讨论,自发说一段你的看法。\n")
		}
		b.WriteString("可以先表态再补数据;**但至少要带 1 个具体数字/事实锚点**(本次拉到的或刚才讨论里的),不要只讲方法论。\n")
	} else {
		b.WriteString("# 你的任务\n")
		if strings.TrimSpace(in.HostQuestion) != "" {
			b.WriteString("主持人刚刚的提问:\n  ")
			b.WriteString(in.HostQuestion)
			b.WriteString("\n\n")
		}
		b.WriteString("请用你的人设视角回应,**先用工具拉真实数据**,再给 100-260 字的具体点评。\n")
		b.WriteString("**硬要求**:回答里至少要出现 **2 个具体数字 / 事实锚点**(股价、涨跌幅、PE、营收、新闻标题、政策名…),没有数据支撑的纯方法论表态视为无效。\n")
	}
	return b.String()
}
