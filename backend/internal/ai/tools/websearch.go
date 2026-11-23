package tools

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/ai/websearch"
)

func registerWebSearch(r *tool.Registry, c *websearch.Client) {
	if c == nil || !c.Configured() {
		return
	}
	r.MustRegister(&searchWebTool{c: c})
}

// searchWebTool 是面向模型的通用实时公开网页搜索入口。
//
// 结构化行情、财报和合约信息仍优先用 Tushare / Realtime；这个工具用于补足
// 最近政策、新闻事件、公司公告和“今天发生了什么”一类时效性信息。
type searchWebTool struct {
	c *websearch.Client
}

func (t *searchWebTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "search_web",
		Description: "搜索公开互联网网页，适合查询最新政策、新闻事件、公告、市场热点与" +
			"交易日期前后的国内国际背景。搜索词应具体；返回标题、站点、发布日期、" +
			"摘要和原始链接。结构化行情、财报、合约代码仍应优先使用专用金融工具。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"query": {
					Type:        "string",
					Description: "1~128 字的具体搜索词",
				},
				"ori_question": {
					Type:        "string",
					Description: "用户原始问题，可选，用于改善搜索排序",
				},
				"count": {
					Type:        "integer",
					Description: "返回结果数，默认 10，最大 20",
				},
				"need_content": {
					Type:        "boolean",
					Description: "是否需要网页正文；一般保持 false，摘要通常已足够",
				},
			},
			Required: []string{"query"},
		},
	}
}

func (t *searchWebTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Query       string `json:"query"`
		Original    string `json:"ori_question,omitempty"`
		Count       int    `json:"count,omitempty"`
		NeedContent bool   `json:"need_content,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	q := strings.TrimSpace(in.Query)
	if q == "" {
		return tool.EncodeJSON(map[string]any{"error": "query 必填"}), nil
	}
	results, err := t.c.Search(ctx, websearch.Query{
		Query:       q,
		Original:    in.Original,
		Count:       in.Count,
		NeedContent: in.NeedContent,
	})
	if err != nil {
		return "", err
	}
	out := map[string]any{
		"query":   q,
		"count":   len(results),
		"results": results,
	}
	if len(results) == 0 {
		out["notice"] = "没有找到匹配网页，可缩短搜索词或改用更常见的表述"
	}
	return tool.EncodeJSON(out), nil
}
