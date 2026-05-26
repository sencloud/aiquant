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
	b.WriteString(fmt.Sprintf("你正在做客 A 股财经直播间「直播间」,你的人设是「%s」。\n\n", guest.Name))
	b.WriteString(style)
	b.WriteString("\n\n# 直播间共同规则\n")
	b.WriteString("- 你必须使用工具拉取真实数据后再发表观点;**不准凭记忆给价格、估值、新闻**\n")
	b.WriteString("- 措辞像直播间发言,不像研报。可以口语化、可以有「嗯」「你看」「说实话」等填充语\n")
	b.WriteString("- 篇幅 150-350 字,**不要写成 markdown 长报告**,不要分一级二级标题\n")
	b.WriteString("- 但**关键数字必须出现**:涉及个股至少要给当前价、当日涨跌幅;涉及估值要给 PE/PB/ROE\n")
	b.WriteString("- 如果给买卖建议,要直接说价位:支撑位/压力位/止损位/目标价,具体数字而不是「等回踩」\n")
	b.WriteString("- 不要复述别人的话(不要「刚才老张说...我也认为...」这样的句式);可以**简短表态后给自己独立观点**\n")
	b.WriteString("- 不要输出 JSON、不要 markdown 围栏、不要前缀「我:」之类的角色标记。直接说话。\n")
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
	}

	if len(in.History) > 0 {
		b.WriteString("# 直播间近期对话\n")
		for _, m := range in.History {
			line := fmt.Sprintf("[%s] ", m.PersonaName)
			b.WriteString(line)
			b.WriteString(condense(m.Content, 220))
			b.WriteString("\n\n")
		}
	}

	if in.IsReact {
		if in.ReactTo != "" {
			b.WriteString(fmt.Sprintf("# 你的任务\n请就「%s」刚才的观点表态(同意/反驳/补充)。", in.ReactTo))
		} else {
			b.WriteString("# 你的任务\n请基于直播间最近的讨论,自发说一段你的看法。")
		}
		b.WriteString("不必先工具调用再说话——可以先表态再补数据。\n")
	} else {
		b.WriteString("# 你的任务\n")
		if strings.TrimSpace(in.HostQuestion) != "" {
			b.WriteString("主持人刚刚的提问:\n  ")
			b.WriteString(in.HostQuestion)
			b.WriteString("\n\n")
		}
		b.WriteString("请用你的人设视角回应。**先用工具拉真实数据**,再给出 150-350 字的口语化点评。\n")
	}
	return b.String()
}
