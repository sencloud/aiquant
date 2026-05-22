package chat

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/llm"
	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/users"
)

// Emitter 是 SSE 事件下发的回调（由 HTTP 层注入）。
type Emitter func(event string, data any) error

// Deps 集中聊天服务依赖。
type Deps struct {
	Sessions *SessionRepo
	Tools    *tool.Registry
	LLM      *llm.DeepSeek
	Ledger   *billing.LedgerRepo
	Users    *users.Service
	Cfg      platform.AIConfig
}

// Service 是 /v1/ai/chat 的核心。
type Service struct {
	d Deps
}

// New 构造。Tools / LLM 任一为 nil 都会让所有 chat 请求即时返回 error。
func New(d Deps) *Service { return &Service{d: d} }

// Configured AI Chat 是否可用（缺 LLM key 等）。
func (s *Service) Configured() bool {
	return s.d.LLM != nil && s.d.Tools != nil
}

// ChatInput 是 HTTP 层调进来的入参。
type ChatInput struct {
	UserID      int64
	SessionUUID string
	Persona     string
	UserText    string
	DeepMode    bool   // 启用 reasoner 模型 + 加价
	SystemHint  string // 个性化 system prompt（可选）
	ClientReqID string // 幂等键（与 reason+ref_type 三元组幂等扣费）
	// BillingReason 决定 ledger entry 的 reason 列：
	//   - 空（默认）→ billing.ReasonConsumeAI（来自 /v1/ai/chat 用户主动对话）
	//   - billing.ReasonConsumeDing → DING runner / run-now 的统一扣费
	// 其余取值会被拒绝。
	BillingReason string

	// PortfolioContext 是客户端在用户主动「@组合」/ 进入"诊断报告/解套止盈"
	// 等需要 AI 看持仓的入口时附带的当前组合快照。
	// 为空表示本次对话不附带；非空时拼到 system prompt 的「附加上下文」段落。
	PortfolioContext *PortfolioContext
}

// PortfolioContext 是 ChatInput 携带的"用户当前组合快照"。
//
// 字段尽量贴近客户端 PortfolioSummary 序列化结果，省得多一层映射。
type PortfolioContext struct {
	Name             string             `json:"name"`
	Currency         string             `json:"currency,omitempty"`
	AsOfMs           int64              `json:"as_of_ms,omitempty"`
	TotalMarketValue float64            `json:"total_market_value"`
	TotalCost        float64            `json:"total_cost"`
	TotalPnL         float64            `json:"total_pnl"`
	TotalPnLPct      float64            `json:"total_pnl_pct"`
	DayPnL           float64            `json:"day_pnl,omitempty"`
	DayPnLPct        float64            `json:"day_pnl_pct,omitempty"`
	Holdings         []PortfolioHolding `json:"holdings"`
}

// PortfolioHolding 是单只标的快照。
type PortfolioHolding struct {
	TsCode       string  `json:"ts_code"`
	Symbol       string  `json:"symbol,omitempty"`
	Name         string  `json:"name"`
	Industry     string  `json:"industry,omitempty"`
	Quantity     float64 `json:"quantity"`
	AvgCost      float64 `json:"avg_cost"`
	CurrentPrice float64 `json:"current_price"`
	MarketValue  float64 `json:"market_value"`
	PnL          float64 `json:"pnl"`
	PnLPct       float64 `json:"pnl_pct"`
	Weight       float64 `json:"weight_pct"`
	DayChangePct float64 `json:"day_change_pct,omitempty"`
}

// ErrInsufficientBalance 暴露给上层用于 HTTP 401/402 风格响应。
var ErrInsufficientBalance = errors.New("insufficient balance")

// CollectResult 把 [Run] 派发的事件聚合成一份最终结果，供 DING runner /
// 同步 run-now 等无 SSE 出口的调用方使用。
type CollectResult struct {
	SessionUUID  string
	FinalText    string
	ToolCalls    int
	Credits      int64
	BalanceAfter int64
	ErrorCode    string
	ErrorMessage string
}

// RunCollect 复用 [Run] 的 tool calling loop 与扣费逻辑，但把 SSE 事件折叠
// 成一份 [CollectResult]。任何 error 事件都会被记到 result 上而非作为返回
// error 抛出（除非底层 LLM/扣费失败）。
func (s *Service) RunCollect(ctx context.Context, in ChatInput) (*CollectResult, error) {
	out := &CollectResult{}
	emit := func(event string, data any) error {
		m, _ := data.(map[string]any)
		if m == nil {
			return nil
		}
		switch event {
		case "session":
			if v, ok := m["session_id"].(string); ok {
				out.SessionUUID = v
			}
		case "done":
			if v, ok := m["final_text"].(string); ok {
				out.FinalText = v
			}
			if v, ok := m["tool_calls"].(int); ok {
				out.ToolCalls = v
			}
			if v, ok := m["credits"].(int64); ok {
				out.Credits = v
			}
			if v, ok := m["balance_after"].(int64); ok {
				out.BalanceAfter = v
			}
		case "error":
			if v, ok := m["code"].(string); ok {
				out.ErrorCode = v
			}
			if v, ok := m["message"].(string); ok {
				out.ErrorMessage = v
			}
		}
		return nil
	}
	if err := s.Run(ctx, in, emit); err != nil {
		return out, err
	}
	return out, nil
}

// Run 是核心入口：跑一次完整的 SSE 对话（可能包含若干轮 tool 调用）。
//
// 它负责：
//   1. 加载或新建 session；
//   2. 余额预检（必须 ≥ baseCost，深度 +deepBonus）；
//   3. 把 user 消息落库；
//   4. 进入 tool calling loop（每轮 ChatStream 流式输出文本/工具调用）；
//   5. 每个 tool 调用 → emit tool_call / 调度 / emit tool_result / 落库；
//   6. 累计 tool 数 → 在 done 之前一次性扣费；
//   7. emit session/done/error 事件。
func (s *Service) Run(ctx context.Context, in ChatInput, emit Emitter) error {
	if !s.Configured() {
		_ = emit("error", map[string]any{"code": "AI.NOT_CONFIGURED", "message": "AI 服务未启用"})
		return errors.New("ai chat not configured")
	}
	if in.UserText == "" {
		_ = emit("error", map[string]any{"code": "AI.EMPTY_INPUT", "message": "消息内容为空"})
		return errors.New("empty user text")
	}
	cfg := s.d.Cfg

	balance, err := s.d.Users.CreditBalance(ctx, in.UserID)
	if err != nil {
		_ = emit("error", map[string]any{"code": "AI.BALANCE_READ", "message": err.Error()})
		return err
	}
	// 预扣费乐观估算 = base + deep + perTool * estTools。
	// estTools 取一个能覆盖大部分对话的常见上限（默认 6），避免出现「跑完 N 个
	// tool call 才报喜点不足」的体验问题。即使最终实际工具数少于 estTools，
	// 真实扣费在 LOOPS 结束后按 totalToolCalls 计算，不会多扣。
	const estimatedToolCalls = 6
	estCost := cfg.BaseChatCredits
	if in.DeepMode {
		estCost += cfg.DeepBonusCredits
	}
	estCost += cfg.PerToolCredits * int64(estimatedToolCalls)
	minCost := cfg.BaseChatCredits
	if in.DeepMode {
		minCost += cfg.DeepBonusCredits
	}
	if balance < estCost {
		_ = emit("error", map[string]any{
			"code": "AI.INSUFFICIENT_BALANCE",
			"message": fmt.Sprintf(
				"喜点不足，当前余额 %d，本次对话预估最多需要 %d（基础 %d + 工具 %d × %d）。请先充值再继续。",
				balance, estCost, minCost,
				cfg.PerToolCredits, estimatedToolCalls,
			),
			"balance":  balance,
			"estimate": estCost,
		})
		return ErrInsufficientBalance
	}

	sess, err := s.d.Sessions.CreateOrLoad(ctx, in.UserID, in.SessionUUID, in.Persona)
	if err != nil {
		_ = emit("error", map[string]any{"code": "AI.SESSION", "message": err.Error()})
		return err
	}
	if err := emit("session", map[string]any{
		"session_id": sess.UUID,
		"persona":    sess.PersonaID,
		"balance":    balance,
	}); err != nil {
		return err
	}
	if _, err := s.d.Sessions.AppendUser(ctx, sess.ID, in.UserText); err != nil {
		_ = emit("error", map[string]any{"code": "AI.PERSIST", "message": err.Error()})
		return err
	}
	_ = s.d.Sessions.SetTitleIfEmpty(ctx, sess.ID, in.UserText)

	maxCtx := cfg.MaxContextMsgs
	if maxCtx <= 0 {
		maxCtx = 12
	}
	historyMsgs, err := s.d.Sessions.LoadHistory(ctx, sess.ID, maxCtx)
	if err != nil {
		_ = emit("error", map[string]any{"code": "AI.HISTORY", "message": err.Error()})
		return err
	}
	llmMsgs := []llm.MessageWithTools{}
	if sys := buildSystemPrompt(in.SystemHint, in.PortfolioContext); sys != "" {
		llmMsgs = append(llmMsgs, llm.MessageWithTools{Role: "system", Content: sys})
	}
	for _, m := range historyMsgs {
		llmMsgs = append(llmMsgs, mapMessageToLLM(m))
	}

	tools := s.d.Tools.ToolListJSON()
	maxLoops := cfg.MaxToolLoops
	if maxLoops <= 0 {
		maxLoops = 6
	}
	model := s.d.LLM.Chat
	if in.DeepMode {
		model = s.d.LLM.Reason
	}

	totalToolCalls := 0
	var lastUsage *llm.Usage
	finalAssistant := ""

LOOPS:
	for loop := 0; loop < maxLoops; loop++ {
		req := llm.StreamRequest{
			Model:    model,
			Messages: llmMsgs,
			Tools:    tools,
		}

		var roundToolCalls []llm.ToolCall
		var roundFinalText string
		err := s.d.LLM.ChatStream(ctx, req, func(ev llm.StreamEvent) error {
			switch ev.Type {
			case "text_delta":
				return emit("text_delta", map[string]any{"delta": ev.TextDelta})
			case "tool_calls":
				roundToolCalls = ev.ToolCalls
				roundFinalText = ev.FinalText
			case "done":
				lastUsage = ev.Usage
				roundFinalText = ev.FinalText
			case "error":
				return emit("error", map[string]any{"code": "AI.STREAM", "message": ev.ErrorMsg})
			}
			return nil
		})
		if err != nil {
			_ = emit("error", map[string]any{"code": "AI.STREAM", "message": err.Error()})
			return err
		}

		// 把 assistant 这一轮入库（带 tool_calls 或纯文本）
		if _, err := s.d.Sessions.AppendAssistant(ctx, sess.ID, roundFinalText, roundToolCalls, lastUsage, 0); err != nil {
			_ = emit("error", map[string]any{"code": "AI.PERSIST", "message": err.Error()})
			return err
		}
		llmMsgs = append(llmMsgs, llm.MessageWithTools{
			Role:      "assistant",
			Content:   roundFinalText,
			ToolCalls: roundToolCalls,
		})

		// 始终记录最后一轮的文本，供循环自然用尽时返回。
		finalAssistant = roundFinalText

		if len(roundToolCalls) == 0 {
			break LOOPS
		}

		for _, tc := range roundToolCalls {
			totalToolCalls++
			if err := emit("tool_call", map[string]any{
				"id":        tc.ID,
				"name":      tc.Function.Name,
				"arguments": tc.Function.Arguments,
			}); err != nil {
				return err
			}
			result := s.d.Tools.Dispatch(ctx, tc.Function.Name, tc.Function.Arguments)
			if _, err := s.d.Sessions.AppendTool(ctx, sess.ID, tc.ID, tc.Function.Name, result); err != nil {
				_ = emit("error", map[string]any{"code": "AI.PERSIST", "message": err.Error()})
				return err
			}
			llmMsgs = append(llmMsgs, llm.MessageWithTools{
				Role:       "tool",
				Content:    result,
				ToolCallID: tc.ID,
				Name:       tc.Function.Name,
			})
			if err := emit("tool_result", map[string]any{
				"id":     tc.ID,
				"name":   tc.Function.Name,
				"result": result,
			}); err != nil {
				return err
			}
		}
	}

	totalCredits := cfg.BaseChatCredits
	if in.DeepMode {
		totalCredits += cfg.DeepBonusCredits
	}
	totalCredits += cfg.PerToolCredits * int64(totalToolCalls)

	reason := billing.ReasonConsumeAI
	refType := "ai_session"
	if in.BillingReason == billing.ReasonConsumeDing {
		reason = billing.ReasonConsumeDing
		refType = "ding_run"
	}
	// 优先使用调用方传入的幂等键（DING 的 task uuid + startedAt）；
	// 客户端 SSE 调用没传则用 session+nano 兜底（每条新消息一笔流水）。
	refID := strings.TrimSpace(in.ClientReqID)
	if refID == "" {
		refID = strconv.FormatInt(sess.ID, 10) + "/" + strconv.FormatInt(time.Now().UnixNano(), 10)
	}
	entry, lerr := s.d.Ledger.Apply(ctx, billing.ApplyParams{
		UserID:  in.UserID,
		Delta:   -totalCredits,
		Reason:  reason,
		RefType: refType,
		RefID:   refID,
		Remark:  fmt.Sprintf("loops=%d tools=%d deep=%t", maxLoops, totalToolCalls, in.DeepMode),
	})
	newBalance := balance - totalCredits
	if lerr != nil && !errors.Is(lerr, billing.ErrLedgerDuplicate) {
		_ = emit("error", map[string]any{"code": "AI.CHARGE", "message": lerr.Error()})
		return lerr
	}
	if entry != nil {
		newBalance = entry.BalanceAfter
	}
	_ = emit("done", map[string]any{
		"session_id":    sess.UUID,
		"final_text":    finalAssistant,
		"tool_calls":    totalToolCalls,
		"credits":       totalCredits,
		"balance_after": newBalance,
		"deep_mode":     in.DeepMode,
	})
	return nil
}

// mapMessageToLLM 把数据库行转成 LLM 协议的 message。
func mapMessageToLLM(m Message) llm.MessageWithTools {
	out := llm.MessageWithTools{
		Role:    m.Role,
		Content: m.Content,
	}
	if m.ToolCallsJSON.Valid && m.ToolCallsJSON.String != "" {
		var calls []llm.ToolCall
		if err := json.Unmarshal([]byte(m.ToolCallsJSON.String), &calls); err == nil {
			out.ToolCalls = calls
		}
	}
	if m.ToolCallID.Valid {
		out.ToolCallID = m.ToolCallID.String
	}
	if m.ToolName.Valid {
		out.Name = m.ToolName.String
	}
	return out
}

// buildSystemPrompt 注入"我是中国 A 股助理"等基础人设；
// 如有 portfolio context，再追加一段"用户当前组合快照"。
//
// 顶部强制注入「真实当前时间」段落：LLM 训练截止日远早于当前，且模型默认
// 会用训练时的"今天"来推断"近 30 天 / 最新一期"等时间窗口。客户端没办法
// 每次都在 user prompt 里写日期，因此一律在 system 这里钉死真实当下，并
// 要求 LLM 不再自行猜测时间。
func buildSystemPrompt(extra string, ctx *PortfolioContext) string {
	var b strings.Builder
	b.WriteString(renderNowBlock())
	b.WriteString("\n\n")
	b.WriteString("你是面向中国 A 股 / ETF / 期货 / 期权市场的智能投研助理。回答用户问题时优先调用提供的 tool 拉真实数据；")
	b.WriteString("涉及行情、估值、新闻、量化指标、合约信息时不要凭空猜测。所有金额和指标都基于工具返回的实际数据。")
	b.WriteString("\n- 解析中文标的名称用 search_instrument。")
	b.WriteString("\n- 涉及期货 / 期权的「主力合约」「近月合约」时（无论是 IF/IC/IH/IM/T、RB/CU/AU/原油 等期货，还是 50ETF期权/沪深300期权/豆粕期权/铜期权/沪深300股指期权 等四类期权 — ETF期权 / 商品期权 / 股指期权 / 期货），**必须先调用 get_dominant_contract 拿真实代码**，再用该 ts_code 调 get_quote / get_option_quote，绝对禁止凭印象猜某月份是主力。")
	b.WriteString("\n输出语言：简体中文。")
	if extra != "" {
		b.WriteString("\n\n额外指令：")
		b.WriteString(extra)
	}
	if ctx != nil && len(ctx.Holdings) > 0 {
		b.WriteString("\n\n")
		b.WriteString(renderPortfolioBlock(ctx))
	}
	return b.String()
}

// shanghaiLoc 缓存上海时区（中国大陆所有交易所统一使用）。
var shanghaiLoc = func() *time.Location {
	loc, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		// 离线环境（Linux 容器可能没装 tzdata）回退到固定 +08:00
		return time.FixedZone("CST", 8*3600)
	}
	return loc
}()

// renderNowBlock 输出注入 system prompt 顶部的「真实当前时间」段落。
//
// 让 LLM 严格按这个时间理解"今天 / 最近一周 / 上月 / 本季度 / 近 3 年"
// 等相对时间表达，禁止用训练时的时间。
func renderNowBlock() string {
	now := time.Now().In(shanghaiLoc)
	weekdayCN := []string{"周日", "周一", "周二", "周三", "周四", "周五", "周六"}[now.Weekday()]
	dateStr := now.Format("2006-01-02 15:04")
	yearStr := now.Format("2006")
	threeYearsAgo := now.AddDate(-3, 0, 0).Format("2006-01-02")
	oneMonthAgo := now.AddDate(0, -1, 0).Format("2006-01-02")

	var b strings.Builder
	b.WriteString("【真实当前时间（务必以此为准，禁止使用模型训练时的『今天』）】\n")
	b.WriteString(fmt.Sprintf("- 现在：%s（%s，时区 Asia/Shanghai）\n", dateStr, weekdayCN))
	b.WriteString(fmt.Sprintf("- 当前年份：%s\n", yearStr))
	b.WriteString(fmt.Sprintf("- 近 1 个月 = %s ~ %s\n", oneMonthAgo, now.Format("2006-01-02")))
	b.WriteString(fmt.Sprintf("- 近 3 年   = %s ~ %s\n", threeYearsAgo, now.Format("2006-01-02")))
	b.WriteString("规则：除非用户消息里给出明确日期，否则所有『今天 / 最近 / 上周 / 本月 / 上月 / 本季度 / 年初至今 / 近 N 年』 都以上述时间为参照。任何回答里出现『截至 20xx 年』 必须等于『当前年份』。")
	return b.String()
}

// renderPortfolioBlock 把组合快照按可读 markdown 表格渲染，让 LLM 能识别。
func renderPortfolioBlock(c *PortfolioContext) string {
	var b strings.Builder
	b.WriteString("【已附带用户当前组合快照（仅参考，不要把字段解释为下单建议来源）】\n")
	if c.Name != "" {
		b.WriteString("组合名：" + c.Name)
		if c.Currency != "" {
			b.WriteString("（" + c.Currency + "）")
		}
		b.WriteString("\n")
	}
	if c.AsOfMs > 0 {
		b.WriteString(fmt.Sprintf("数据时间：%s\n",
			time.UnixMilli(c.AsOfMs).Format("2006-01-02 15:04")))
	}
	b.WriteString(fmt.Sprintf(
		"汇总：总市值 %.2f｜总成本 %.2f｜总盈亏 %.2f (%.2f%%)",
		c.TotalMarketValue, c.TotalCost, c.TotalPnL, c.TotalPnLPct))
	if c.DayPnL != 0 || c.DayPnLPct != 0 {
		b.WriteString(fmt.Sprintf("｜当日盈亏 %.2f (%.2f%%)", c.DayPnL, c.DayPnLPct))
	}
	b.WriteString(fmt.Sprintf("｜共 %d 只标的\n\n", len(c.Holdings)))
	b.WriteString("| 代码 | 名称 | 行业 | 数量 | 成本 | 现价 | 市值 | 权重% | 盈亏 | 盈亏% | 当日% |\n")
	b.WriteString("|------|------|------|------|------|------|------|-------|------|-------|-------|\n")
	for _, h := range c.Holdings {
		b.WriteString(fmt.Sprintf(
			"| %s | %s | %s | %s | %s | %s | %s | %.2f | %s | %.2f | %.2f |\n",
			h.TsCode, h.Name, h.Industry,
			fmtNum(h.Quantity), fmtNum(h.AvgCost), fmtNum(h.CurrentPrice),
			fmtNum(h.MarketValue), h.Weight,
			fmtNum(h.PnL), h.PnLPct, h.DayChangePct,
		))
	}
	b.WriteString("\n回答时如果用户提到「我的持仓 / 解套 / 止盈 / 当前组合」，请直接基于此表分析；" +
		"如需补行情/新闻/财报数据再调相应工具。")
	return b.String()
}

// fmtNum 数字简短渲染：整数无小数，小数保留 2 位。
func fmtNum(v float64) string {
	if v == float64(int64(v)) {
		return strconv.FormatInt(int64(v), 10)
	}
	return strconv.FormatFloat(v, 'f', 2, 64)
}
