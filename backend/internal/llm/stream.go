package llm

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/sencloud/finme-backend/internal/ai/tool"
)

// ToolCall 是 OpenAI 兼容协议下 assistant 发出的一次工具调用请求。
type ToolCall struct {
	ID       string `json:"id"`
	Type     string `json:"type"` // 一律 "function"
	Function struct {
		Name      string `json:"name"`
		Arguments string `json:"arguments"` // JSON 字符串
	} `json:"function"`
}

// MessageWithTools 兼容 OpenAI 协议带 tool_calls / tool_call_id 的扩展消息。
type MessageWithTools struct {
	Role       string     `json:"role"`
	Content    string     `json:"content,omitempty"`
	ToolCalls  []ToolCall `json:"tool_calls,omitempty"`
	ToolCallID string     `json:"tool_call_id,omitempty"`
	Name       string     `json:"name,omitempty"` // role=tool 时的 tool 名
}

// StreamEvent 是从 LLM 流式产出 / 或工具循环回报的事件。
type StreamEvent struct {
	Type        string     // text_delta / tool_calls / done / error
	TextDelta   string     // type=text_delta 时
	ToolCalls   []ToolCall // type=tool_calls 时（一轮 assistant 末尾累积完）
	Usage       *Usage     // type=done 时
	FinalText   string     // type=done 时本轮 assistant 累计文本
	ErrorMsg    string     // type=error 时
}

// StreamRequest 是对 ChatStream 的入参（不含 tools，由 Registry 提供）。
type StreamRequest struct {
	Model       string             // 留空走 c.Chat
	Messages    []MessageWithTools // 历史 + 本轮
	Tools       []map[string]any   // tools 列表（来自 registry.ToolListJSON）
	Temperature float64            // 默认 0.5
}

// ChatStream 调 DeepSeek /v1/chat/completions 的流式接口。
//
// 协议：每一行是 `data: {...}` 或 `data: [DONE]`。我们把流式产出的
// content 增量拼接成 finalText，工具调用按 index 累计 arguments，最终
// 用一个 done 事件总结一轮（finish_reason=stop / tool_calls）。
//
// 调用方负责在 type=tool_calls 时调度工具、把 tool 结果作为新一条 message
// 送回，再次调用 ChatStream，形成 tool calling loop。
func (c *DeepSeek) ChatStream(
	ctx context.Context,
	req StreamRequest,
	emit func(StreamEvent) error,
) error {
	model := req.Model
	if model == "" {
		model = c.Chat
	}
	temp := req.Temperature
	if temp == 0 {
		temp = 0.5
	}
	body := map[string]any{
		"model":       model,
		"messages":    req.Messages,
		"temperature": temp,
		"stream":      true,
	}
	if len(req.Tools) > 0 {
		body["tools"] = req.Tools
		body["tool_choice"] = "auto"
	}
	raw, _ := json.Marshal(body)
	httpReq, _ := http.NewRequestWithContext(ctx, "POST",
		c.BaseURL+"/v1/chat/completions", bytes.NewReader(raw))
	httpReq.Header.Set("Authorization", "Bearer "+c.APIKey)
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Accept", "text/event-stream")

	resp, err := c.httpc.Do(httpReq)
	if err != nil {
		return fmt.Errorf("deepseek http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return fmt.Errorf("deepseek status %d: %s", resp.StatusCode, string(respBody))
	}

	type deltaT struct {
		Role      string `json:"role,omitempty"`
		Content   string `json:"content,omitempty"`
		ToolCalls []struct {
			Index    int    `json:"index"`
			ID       string `json:"id,omitempty"`
			Type     string `json:"type,omitempty"`
			Function struct {
				Name      string `json:"name,omitempty"`
				Arguments string `json:"arguments,omitempty"`
			} `json:"function"`
		} `json:"tool_calls,omitempty"`
	}
	type chunkT struct {
		Choices []struct {
			Delta        deltaT `json:"delta"`
			FinishReason string `json:"finish_reason,omitempty"`
		} `json:"choices"`
		Usage *Usage `json:"usage,omitempty"`
	}

	type toolCallAcc struct {
		id   string
		name string
		args strings.Builder
	}
	toolCalls := map[int]*toolCallAcc{}
	finalText := strings.Builder{}
	var lastUsage *Usage
	finishReason := ""

	scanner := bufio.NewScanner(resp.Body)
	scanner.Buffer(make([]byte, 0, 64*1024), 1<<20)

	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		payload := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
		if payload == "" {
			continue
		}
		if payload == "[DONE]" {
			break
		}
		var ck chunkT
		if err := json.Unmarshal([]byte(payload), &ck); err != nil {
			continue
		}
		if ck.Usage != nil {
			lastUsage = ck.Usage
		}
		for _, ch := range ck.Choices {
			if ch.Delta.Content != "" {
				finalText.WriteString(ch.Delta.Content)
				if err := emit(StreamEvent{Type: "text_delta", TextDelta: ch.Delta.Content}); err != nil {
					return err
				}
			}
			for _, tc := range ch.Delta.ToolCalls {
				acc, ok := toolCalls[tc.Index]
				if !ok {
					acc = &toolCallAcc{}
					toolCalls[tc.Index] = acc
				}
				if tc.ID != "" {
					acc.id = tc.ID
				}
				if tc.Function.Name != "" {
					acc.name = tc.Function.Name
				}
				if tc.Function.Arguments != "" {
					acc.args.WriteString(tc.Function.Arguments)
				}
			}
			if ch.FinishReason != "" {
				finishReason = ch.FinishReason
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return fmt.Errorf("deepseek stream read: %w", err)
	}

	if len(toolCalls) > 0 && finishReason != "stop" {
		calls := make([]ToolCall, 0, len(toolCalls))
		for i := 0; i < len(toolCalls); i++ {
			a, ok := toolCalls[i]
			if !ok {
				continue
			}
			tc := ToolCall{ID: a.id, Type: "function"}
			tc.Function.Name = a.name
			tc.Function.Arguments = a.args.String()
			calls = append(calls, tc)
		}
		if err := emit(StreamEvent{Type: "tool_calls", ToolCalls: calls, FinalText: finalText.String()}); err != nil {
			return err
		}
		return nil
	}

	return emit(StreamEvent{
		Type:      "done",
		Usage:     lastUsage,
		FinalText: finalText.String(),
	})
}

// CompactToolSpec 给上层一个稳定的 tool registry → OpenAI tools 数组的转换点。
func CompactToolSpec(reg *tool.Registry) []map[string]any {
	if reg == nil {
		return nil
	}
	return reg.ToolListJSON()
}
