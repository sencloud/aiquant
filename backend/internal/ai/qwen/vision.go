// Package qwen 阿里百炼 DashScope 客户端（OpenAI 兼容模式）。
//
// 当前仅暴露多模态 vision：把券商持仓截图解析成结构化 JSON，让客户端
// 一键导入到组合。后续若需要文本对话能力（替换 / 备份 deepseek）可在此
// 包内追加 chat.go，沿用同一份 base url + api key。
package qwen

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

	"github.com/sencloud/finme-backend/internal/platform"
)

// VisionClient 持有 DashScope 的 base url / api key / model 名。
//
// 线程安全；构造一次注入到 HTTP handler 即可。
type VisionClient struct {
	apiKey  string
	baseURL string
	model   string
	hc      *http.Client
}

// NewVisionClient 不会校验 key；调用方先用 Configured() 判可用性。
func NewVisionClient(cfg platform.QwenConfig) *VisionClient {
	timeout := time.Duration(cfg.TimeoutSec) * time.Second
	if timeout <= 0 {
		timeout = 60 * time.Second
	}
	return &VisionClient{
		apiKey:  cfg.APIKey,
		baseURL: strings.TrimRight(cfg.BaseURL, "/"),
		model:   cfg.VisionModel,
		hc:      &http.Client{Timeout: timeout},
	}
}

// Configured DashScope key 是否已注入。
func (c *VisionClient) Configured() bool { return c != nil && c.apiKey != "" }

// ParsedHolding 是 vision 模型返回的"一行持仓"结构。
//
// 字段含义都按券商 App 截图常见列归一化；模型遗漏的字段用零值，调用方按需校验。
type ParsedHolding struct {
	Name         string  `json:"name"`
	Code         string  `json:"code"`
	Market       string  `json:"market"` // SH/SZ/HK/US（可空，由后续标的解析补齐）
	Quantity     float64 `json:"quantity"`
	AvailableQty float64 `json:"available_qty"`
	AvgCost      float64 `json:"avg_cost"`
	CurrentPrice float64 `json:"current_price"`
	MarketValue  float64 `json:"market_value"`
	PnL          float64 `json:"pnl"`
	PnLPct       float64 `json:"pnl_pct"`
}

// ParseHoldingsResult 整张截图的解析结果。
type ParseHoldingsResult struct {
	BrokerHint string          `json:"broker_hint"`
	Currency   string          `json:"currency"`
	Holdings   []ParsedHolding `json:"holdings"`
}

// ParseHoldingsFromImage 调 qwen-vl-max 多模态接口，让它把图片里的持仓表
// 抽成结构化 JSON。imageDataURL 必须是 `data:image/png;base64,...` 形态，
// 客户端上传时已经按 image_picker 给出的字节做 base64。
func (c *VisionClient) ParseHoldingsFromImage(
	ctx context.Context, imageDataURL string,
) (*ParseHoldingsResult, error) {
	if !c.Configured() {
		return nil, errors.New("qwen vision: api key not configured")
	}
	if imageDataURL == "" {
		return nil, errors.New("qwen vision: empty image")
	}

	// system prompt 强调"只允许输出 JSON"；DashScope 的 OpenAI 兼容模式
	// 也接受 response_format=json_object，组合双保险。
	system := `你是金融券商持仓截图解析助手。任务：从用户上传的"券商 App 持仓截图"
里抽取所有标的的持仓信息，输出严格 JSON：
{
  "broker_hint": "可识别的券商名（如华泰/中金/老虎/富途，识别不到则填空字符串）",
  "currency": "CNY|HKD|USD（默认 CNY）",
  "holdings": [
    {
      "name": "标的中文名（必填）",
      "code": "代码（如 600519、00700.HK、AAPL；识别不到留空）",
      "market": "SH|SZ|HK|US（识别不到留空）",
      "quantity": 持仓数量（数字，单位股/份）,
      "available_qty": 可用数量（数字，识别不到设为 0）,
      "avg_cost": 平均成本（数字）,
      "current_price": 现价（数字）,
      "market_value": 市值（数字）,
      "pnl": 浮动盈亏（数字，亏损为负）,
      "pnl_pct": 盈亏百分比（数字，例如 -5.99 不是 -0.0599）
    }
  ]
}
只输出 JSON，不要任何额外说明。数字字段如果截图里看不到精确值就填 0；不要瞎编。`

	body := map[string]any{
		"model": c.model,
		"messages": []map[string]any{
			{"role": "system", "content": system},
			{
				"role": "user",
				"content": []map[string]any{
					{"type": "text", "text": "请解析这张持仓截图。"},
					{"type": "image_url", "image_url": map[string]any{
						"url": imageDataURL,
					}},
				},
			},
		},
		"response_format": map[string]string{"type": "json_object"},
	}
	raw, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("qwen vision: marshal: %w", err)
	}

	url := c.baseURL + "/chat/completions"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(raw))
	if err != nil {
		return nil, fmt.Errorf("qwen vision: build req: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.hc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("qwen vision: do: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("qwen vision: http %d: %s",
			resp.StatusCode, truncate(string(respBody), 400))
	}

	var parsed struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return nil, fmt.Errorf("qwen vision: parse envelope: %w", err)
	}
	if len(parsed.Choices) == 0 {
		return nil, errors.New("qwen vision: empty choices")
	}
	content := strings.TrimSpace(parsed.Choices[0].Message.Content)
	content = stripCodeFence(content)

	var out ParseHoldingsResult
	if err := json.Unmarshal([]byte(content), &out); err != nil {
		return nil, fmt.Errorf("qwen vision: parse content json: %w (raw=%s)",
			err, truncate(content, 400))
	}
	return &out, nil
}

// stripCodeFence 去掉模型在严格 json_object 之外有时仍会附加的 ```json ... ``` 包裹。
func stripCodeFence(s string) string {
	s = strings.TrimSpace(s)
	if !strings.HasPrefix(s, "```") {
		return s
	}
	if i := strings.Index(s, "\n"); i >= 0 {
		s = s[i+1:]
	}
	if j := strings.LastIndex(s, "```"); j >= 0 {
		s = s[:j]
	}
	return strings.TrimSpace(s)
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}
