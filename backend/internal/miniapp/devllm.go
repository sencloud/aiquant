package miniapp

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/sencloud/finme-backend/internal/llm"
)

// DevLLM 是本地联调用的假模型（仅 env=dev 且显式开启时使用，不调用任何外部服务）：
// 新建时按关键词挑一个同主题的官方模板、用用户的话当标题；修改时原样返回当前 spec。
// 消息里带「问我」时返回一次澄清问题，带「下单」时拒绝，方便走完所有分支。
type DevLLM struct {
	Templates []*Template
}

// Complete 实现 LLM。
func (d *DevLLM) Complete(_ context.Context, _ string, msgs []llm.Message) (string, llm.Usage, error) {
	topic := "money"
	if len(msgs) > 0 && strings.Contains(msgs[0].Content, `"topic": "fishing"`) {
		topic = "fishing"
	}
	last := ""
	var current string
	for _, m := range msgs {
		if m.Role != "user" {
			continue
		}
		if strings.HasPrefix(m.Content, "当前小应用的 spec") {
			if i := strings.Index(m.Content, "\n"); i > 0 {
				current = m.Content[i+1:]
			}
			continue
		}
		last = m.Content
	}
	out := func(v any) (string, llm.Usage, error) {
		b, _ := json.Marshal(v)
		return string(b), llm.Usage{PromptTokens: 1, CompletionTokens: 1}, nil
	}
	switch {
	case strings.Contains(last, "下单"):
		return out(map[string]any{"action": "refuse", "message": "小应用不能自动下单。可以做一个价格到位提醒面板，打开时一眼看到是否到位。"})
	case strings.Contains(last, "问我"):
		return out(map[string]any{"action": "ask", "message": "先确认两件事：", "questions": []Question{
			{Q: "想看哪个品种？", Options: []string{"豆油", "棕榈油", "豆粕"}},
			{Q: "看多长时间？", Options: []string{"20 日", "60 日", "120 日"}}}})
	}
	if current != "" {
		var spec map[string]any
		if json.Unmarshal([]byte(current), &spec) == nil {
			return out(map[string]any{"action": "spec", "summary": "按你的要求调整了", "spec": spec})
		}
	}
	var pick *Template
	for _, t := range d.Templates {
		if t.Topic != topic {
			continue
		}
		if pick == nil {
			pick = t
		}
		for _, kw := range strings.Fields(strings.NewReplacer("、", " ", "，", " ", "的", " ").Replace(t.Summary + " " + t.Title)) {
			if len([]rune(kw)) >= 2 && strings.Contains(last, kw) {
				pick = t
			}
		}
	}
	if pick == nil {
		return out(map[string]any{"action": "refuse", "message": "这个主题还没有可用的模板"})
	}
	b, _ := json.Marshal(pick.Spec)
	var spec map[string]any
	_ = json.Unmarshal(b, &spec)
	if m, ok := spec["meta"].(map[string]any); ok {
		if t := []rune(strings.TrimSpace(last)); len(t) > 0 {
			if len(t) > 12 {
				t = t[:12]
			}
			m["title"] = string(t)
		}
	}
	return out(map[string]any{"action": "spec", "summary": "按「" + pick.Title + "」的思路做好了", "spec": spec})
}
