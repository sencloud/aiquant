package live

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/llm"
)

// Executor 跑一次"system prompt + user prompt → 多轮 tool 调用 → 最终文本"，
// 是 chat.Service.Run 的极简变体：
//
//   - 不写 ai_chat_sessions / ai_chat_messages 表（直播无对话回顾需求）
//   - 不扣任何用户喜点（直播是系统服务，成本走运营账）
//   - 不发 SSE 事件（runner 后台异步执行）
//
// MaxLoops 默认 6 轮 tool calling，超出则强制停止并把当前 finalText 返回。
type Executor struct {
	llm   *llm.DeepSeek
	tools *tool.Registry

	MaxLoops    int
	Temperature float64
}

func NewExecutor(d *llm.DeepSeek, reg *tool.Registry) *Executor {
	return &Executor{
		llm:         d,
		tools:       reg,
		MaxLoops:    6,
		Temperature: 0.45,
	}
}

// ExecResult 是单次执行结果。
type ExecResult struct {
	FinalText  string
	ToolCalls  int
	DurationMs int64
}

// Run 执行一次完整的 tool calling loop。
// systemPrompt 已经包含"直播 persona"风格 + 输出契约提示。
func (e *Executor) Run(ctx context.Context, systemPrompt, userPrompt string) (*ExecResult, error) {
	if e.llm == nil {
		return nil, errors.New("llm not configured")
	}
	if e.tools == nil {
		return nil, errors.New("tools not configured")
	}
	start := time.Now()
	maxLoops := e.MaxLoops
	if maxLoops <= 0 {
		maxLoops = 6
	}

	msgs := []llm.MessageWithTools{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: userPrompt},
	}
	tools := e.tools.ToolListJSON()

	var (
		totalTools int
		finalText  string
	)

LOOPS:
	for loop := 0; loop < maxLoops; loop++ {
		var (
			roundTC []llm.ToolCall
			roundFT string
		)
		err := e.llm.ChatStream(ctx, llm.StreamRequest{
			Messages:    msgs,
			Tools:       tools,
			Temperature: e.Temperature,
		}, func(ev llm.StreamEvent) error {
			switch ev.Type {
			case "tool_calls":
				roundTC = ev.ToolCalls
				roundFT = ev.FinalText
			case "done":
				roundFT = ev.FinalText
			case "error":
				return errors.New(ev.ErrorMsg)
			}
			return nil
		})
		if err != nil {
			return nil, fmt.Errorf("llm stream loop %d: %w", loop, err)
		}

		// assistant 这一轮入栈
		msgs = append(msgs, llm.MessageWithTools{
			Role:      "assistant",
			Content:   roundFT,
			ToolCalls: roundTC,
		})
		finalText = roundFT

		if len(roundTC) == 0 {
			break LOOPS
		}

		// 依次跑本轮 tool calls
		for _, tc := range roundTC {
			totalTools++
			res := e.tools.Dispatch(ctx, tc.Function.Name, tc.Function.Arguments)
			msgs = append(msgs, llm.MessageWithTools{
				Role:       "tool",
				Content:    res,
				ToolCallID: tc.ID,
				Name:       tc.Function.Name,
			})
		}
	}

	return &ExecResult{
		FinalText:  strings.TrimSpace(finalText),
		ToolCalls:  totalTools,
		DurationMs: time.Since(start).Milliseconds(),
	}, nil
}
