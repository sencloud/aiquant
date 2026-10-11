package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
)

// ChatOptions 是 ChatJSON 的可选参数。
type ChatOptions struct {
	Temperature float64
	MaxTokens   int
	// JSON 为 true 时要求模型只输出一个 JSON 对象（response_format=json_object）。
	JSON bool
}

type chatRequestEx struct {
	Model          string          `json:"model"`
	Messages       []Message       `json:"messages"`
	Temperature    float64         `json:"temperature"`
	MaxTokens      int             `json:"max_tokens,omitempty"`
	ResponseFormat *responseFormat `json:"response_format,omitempty"`
}

type responseFormat struct {
	Type string `json:"type"`
}

// ChatWith 同步发一次 chat，支持 JSON 模式与温度 / 长度控制。
// finish_reason=length 时返回 ErrTruncated（内容仍然一并返回）。
func (c *DeepSeek) ChatWith(ctx context.Context, model string, msgs []Message, o ChatOptions) (*ChatResult, error) {
	if model == "" {
		model = c.Chat
	}
	r := chatRequestEx{Model: model, Messages: msgs, Temperature: o.Temperature, MaxTokens: o.MaxTokens}
	if o.JSON {
		r.ResponseFormat = &responseFormat{Type: "json_object"}
	}
	body, _ := json.Marshal(r)
	req, _ := http.NewRequestWithContext(ctx, "POST", c.BaseURL+"/v1/chat/completions", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+c.APIKey)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("deepseek http: %w", err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if resp.StatusCode != http.StatusOK {
		if len(respBody) > 300 {
			respBody = respBody[:300]
		}
		return nil, fmt.Errorf("deepseek status %d: %s", resp.StatusCode, string(respBody))
	}
	var out struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
			FinishReason string `json:"finish_reason"`
		} `json:"choices"`
		Usage Usage `json:"usage"`
	}
	if err := json.Unmarshal(respBody, &out); err != nil {
		return nil, fmt.Errorf("deepseek parse: %w", err)
	}
	if len(out.Choices) == 0 {
		return nil, errors.New("deepseek empty choices")
	}
	res := &ChatResult{Content: out.Choices[0].Message.Content, Usage: out.Usage}
	if out.Choices[0].FinishReason == "length" {
		return res, ErrTruncated
	}
	return res, nil
}

// ErrTruncated 表示输出被 max_tokens 截断。
var ErrTruncated = errors.New("deepseek output truncated")
