package live

import (
	"context"
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
	Content    string
	ToolCalls  int
	DurationMs int64
}

// Speak 生成嘉宾应答。返回的 Content 已 trim。
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
	content := strings.TrimSpace(res.FinalText)
	if content == "" {
		return nil, errors.New("guest speaker: empty output")
	}
	// 去掉 LLM 偶尔加的 markdown 围栏
	content = strings.TrimPrefix(content, "```")
	content = strings.TrimSuffix(content, "```")
	content = strings.TrimSpace(content)
	return &SpeakResult{
		Content:    content,
		ToolCalls:  res.ToolCalls,
		DurationMs: res.DurationMs,
	}, nil
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

	b.WriteString("# 富文本格式(可用,但克制)\n")
	b.WriteString("- 可以用 `**加粗**` 强调关键数字 / 关键判断,例如:`**PE 23 倍**`、`**短线压力位 1850**`\n")
	b.WriteString("- 可以用 `- 项目` 列举要点(最多 3-4 项,不要长列表)\n")
	b.WriteString("- 可适度使用 emoji 表达情绪/方向(如 📈 📉 ⚠️ 💡 🎯),每段最多 1-2 个,不要堆\n")
	b.WriteString("- **禁止**用 `#` `##` 大标题(这是聊天,不是报告)\n")
	b.WriteString("- **禁止**用 markdown 表格 / 代码块\n")
	b.WriteString("- **禁止**输出 JSON、markdown 围栏 ```、前缀「我:」之类的角色标记。直接说话。\n")
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
