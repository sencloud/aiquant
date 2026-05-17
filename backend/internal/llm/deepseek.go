// Package llm 服务端 LLM 调用客户端。
//
// 当前只接 DeepSeek (OpenAI 兼容 chat/completions)。未来扩展其他 provider
// 可以加 interface 抽象，本期先单文件最简实现。
package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Message 是 chat 协议里的一条消息。
type Message struct {
	Role    string `json:"role"`    // system / user / assistant
	Content string `json:"content"`
}

// ChatRequest 是 DeepSeek/OpenAI 兼容的 chat 入参子集。
type ChatRequest struct {
	Model       string    `json:"model"`
	Messages    []Message `json:"messages"`
	Temperature float64   `json:"temperature,omitempty"`
	MaxTokens   int       `json:"max_tokens,omitempty"`
}

// Usage 是 token 计费回执。
type Usage struct {
	PromptTokens     int64 `json:"prompt_tokens"`
	CompletionTokens int64 `json:"completion_tokens"`
	TotalTokens      int64 `json:"total_tokens"`
}

// ChatResult 是一次同步 chat 的最终结果。
type ChatResult struct {
	Content string
	Usage   Usage
}

// DeepSeek 是 DeepSeek/OpenAI 兼容客户端。
type DeepSeek struct {
	APIKey  string
	BaseURL string
	Chat    string // 默认模型名（chat）
	Reason  string // 思考模型名（reasoner）

	httpc *http.Client
}

// NewDeepSeek 用 cfg 构造客户端。
func NewDeepSeek(apiKey, baseURL, chatModel, reasonModel string, timeout time.Duration) (*DeepSeek, error) {
	if apiKey == "" {
		return nil, errors.New("deepseek api_key empty")
	}
	if baseURL == "" {
		baseURL = "https://api.deepseek.com"
	}
	if chatModel == "" {
		chatModel = "deepseek-chat"
	}
	if reasonModel == "" {
		reasonModel = "deepseek-reasoner"
	}
	if timeout <= 0 {
		timeout = 180 * time.Second
	}
	return &DeepSeek{
		APIKey:  apiKey,
		BaseURL: strings.TrimRight(baseURL, "/"),
		Chat:    chatModel,
		Reason:  reasonModel,
		httpc:   &http.Client{Timeout: timeout},
	}, nil
}

// ChatOnce 同步发一次 chat（非流式），返回完整内容。
func (c *DeepSeek) ChatOnce(ctx context.Context, model string, msgs []Message) (*ChatResult, error) {
	if model == "" {
		model = c.Chat
	}
	body, _ := json.Marshal(ChatRequest{
		Model:       model,
		Messages:    msgs,
		Temperature: 0.5,
	})
	req, _ := http.NewRequestWithContext(ctx, "POST", c.BaseURL+"/v1/chat/completions",
		bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+c.APIKey)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("deepseek http: %w", err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("deepseek status %d: %s", resp.StatusCode, string(respBody))
	}
	var r struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
			FinishReason string `json:"finish_reason"`
		} `json:"choices"`
		Usage Usage `json:"usage"`
	}
	if err := json.Unmarshal(respBody, &r); err != nil {
		return nil, fmt.Errorf("deepseek parse: %w", err)
	}
	if len(r.Choices) == 0 {
		return nil, errors.New("deepseek empty choices")
	}
	return &ChatResult{Content: r.Choices[0].Message.Content, Usage: r.Usage}, nil
}
