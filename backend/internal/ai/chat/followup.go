package chat

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/llm"
)

// 推荐追问（元宝式「回答下方的 2–3 个推荐问题」）。
//
// 只有客户端在请求里声明 want_suggestions=true 时才生成，并以新增的可选
// SSE 事件 `suggestions` 下发（在 done 之后）。旧版 App 不发这个字段，
// 协议与行为完全不变；即便收到未知事件，旧客户端的解析也会直接忽略。
//
// 生成走默认 chat 模型的一次非流式调用，不额外扣喜点。
const (
	// followUpTimeout 是生成推荐追问的最长等待；超时直接放弃，不影响本轮回答。
	followUpTimeout = 8 * time.Second
	// maxFollowUps 最多下发几条推荐问题。
	maxFollowUps = 3
	// maxFollowUpRunes 单条推荐问题的最大字数（超长截断）。
	maxFollowUpRunes = 40
	// followUpAnswerRunes 喂给模型的回答正文最多取多少字（控制成本）。
	followUpAnswerRunes = 1500
)

const followUpSystemPrompt = "你是投研助理的追问推荐器。根据用户的问题和助理的回答，" +
	"站在用户角度，给出 3 个用户最可能接着问的简短问题。要求：每个问题不超过 30 个字；" +
	"具体、可直接发送、和回答内容紧密相关；不要重复用户原问题；不要编号；" +
	"只输出一个 JSON 字符串数组，例如 [\"问题1\",\"问题2\",\"问题3\"]，不要输出任何其他文字。"

// generateFollowUps 调一次 LLM 生成推荐追问。失败返回 nil（静默降级）。
func (s *Service) generateFollowUps(ctx context.Context, question, answer string) []string {
	if s.d.LLM == nil || strings.TrimSpace(answer) == "" {
		return nil
	}
	ctx, cancel := context.WithTimeout(ctx, followUpTimeout)
	defer cancel()
	q := strings.TrimSpace(question)
	if q == "" {
		q = "（用户发送了图片）"
	}
	user := "用户问题：\n" + truncateRunes(q, 300) +
		"\n\n助理回答：\n" + truncateRunes(answer, followUpAnswerRunes)
	res, err := s.d.LLM.ChatOnce(ctx, s.d.LLM.Chat, []llm.Message{
		{Role: "system", Content: followUpSystemPrompt},
		{Role: "user", Content: user},
	})
	if err != nil || res == nil {
		return nil
	}
	return parseFollowUps(res.Content, q)
}

// parseFollowUps 从模型输出里解析推荐问题：优先按 JSON 数组解析（允许外面
// 包着 ```json 代码块或多余文字）；失败时退化为按行切分。结果去重、去编号、
// 截断，最多 [maxFollowUps] 条，并剔除与原问题相同的条目。
func parseFollowUps(raw, question string) []string {
	text := strings.TrimSpace(raw)
	var items []string
	if i, j := strings.Index(text, "["), strings.LastIndex(text, "]"); i >= 0 && j > i {
		var arr []string
		if err := json.Unmarshal([]byte(text[i:j+1]), &arr); err == nil {
			items = arr
		}
	}
	if items == nil {
		for _, line := range strings.Split(text, "\n") {
			items = append(items, line)
		}
	}
	seen := map[string]bool{}
	q := strings.TrimSpace(question)
	out := make([]string, 0, maxFollowUps)
	for _, it := range items {
		s := cleanFollowUp(it)
		if s == "" || s == q || seen[s] {
			continue
		}
		seen[s] = true
		out = append(out, truncateRunes(s, maxFollowUpRunes))
		if len(out) >= maxFollowUps {
			break
		}
	}
	return out
}

// cleanFollowUp 去掉列表符号、编号、引号和代码块标记。
func cleanFollowUp(s string) string {
	s = strings.TrimSpace(s)
	if strings.HasPrefix(s, "```") {
		return ""
	}
	s = strings.TrimLeft(s, "-*•·0123456789.、)） ")
	s = strings.Trim(s, " \t\"'“”‘’,，")
	return strings.TrimSpace(s)
}

func truncateRunes(s string, n int) string {
	rs := []rune(s)
	if len(rs) <= n {
		return s
	}
	return string(rs[:n])
}
