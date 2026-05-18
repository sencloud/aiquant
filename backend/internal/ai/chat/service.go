package chat

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
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
	ClientReqID string // 幂等键（暂未使用，预留）
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
	minCost := cfg.BaseChatCredits
	if in.DeepMode {
		minCost += cfg.DeepBonusCredits
	}
	if balance < minCost {
		_ = emit("error", map[string]any{
			"code":    "AI.INSUFFICIENT_BALANCE",
			"message": fmt.Sprintf("喜点不足（当前 %d，至少 %d）", balance, minCost),
			"balance": balance,
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
	if sys := buildSystemPrompt(in.SystemHint); sys != "" {
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

		if len(roundToolCalls) == 0 {
			finalAssistant = roundFinalText
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
	refID := strconv.FormatInt(sess.ID, 10) + "/" + strconv.FormatInt(time.Now().UnixNano(), 10)
	entry, lerr := s.d.Ledger.Apply(ctx, billing.ApplyParams{
		UserID:  in.UserID,
		Delta:   -totalCredits,
		Reason:  billing.ReasonConsumeAI,
		RefType: "ai_session",
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

// buildSystemPrompt 注入"我是中国 A 股助理"等基础人设。
func buildSystemPrompt(extra string) string {
	base := "你是面向中国 A 股市场的智能投研助理。回答用户问题时优先调用提供的 tool 拉真实数据；" +
		"涉及行情、估值、新闻、量化指标时不要凭空猜测。所有金额和指标都基于工具返回的实际数据，必要时主动调用 search_instrument 解析中文标的名称。" +
		"输出语言：简体中文。"
	if extra != "" {
		return base + "\n\n额外指令：" + extra
	}
	return base
}
