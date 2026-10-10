package api

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/ai/chat"
	"github.com/sencloud/finme-backend/internal/platform"
)

// sseHeartbeatInterval 是 SSE 流上的心跳间隔。DeepSeek 思考阶段 / 慢工具
// Dispatch 期间后端会"沉默"不发字节,移动端 NAT / 中间网络会把看似空闲的
// 长连接回收,导致前端 `Connection closed while receiving data`。每隔这个
// 间隔写一行 SSE 注释 `: ping`(前端 LineSplitter 见 ':' 开头即忽略,不破坏
// 协议),让连接始终有字节流动。
const sseHeartbeatInterval = 12 * time.Second

// maxChatBodyBytes 是 AI chat 请求体上限。普通文本远小于此，但多模态图片
// 走 base64 内联，4 张压缩图就可能到几 MB，因此单独放宽（默认 DecodeJSON
// 只有 256KB）。
const maxChatBodyBytes = 24 << 20 // 24 MB

// normalizeChatImages 校验客户端上传的图片 data URL。
//
// 约定：元素形如 `data:image/jpeg;base64,<payload>`。返回归一化后的列表
// （去掉空项），坏数据直接以 400 拒绝，避免带着无效图片去调 LLM 白扣费用。
func normalizeChatImages(in []string) ([]string, error) {
	if len(in) > chat.MaxImagesPerMessage {
		return nil, platform.ErrBadRequest("AI.TOO_MANY_IMAGES",
			fmt.Sprintf("一次最多上传 %d 张图片", chat.MaxImagesPerMessage), nil)
	}
	out := make([]string, 0, len(in))
	for _, raw := range in {
		s := strings.TrimSpace(raw)
		if s == "" {
			continue
		}
		if len(s) > chat.MaxImageDataURLLen {
			return nil, platform.ErrBadRequest("AI.IMAGE_TOO_LARGE",
				"单张图片过大，请压缩后重试", nil)
		}
		if !strings.HasPrefix(s, "data:image/") {
			return nil, platform.ErrBadRequest("AI.IMAGE_INVALID",
				"图片必须是 data:image/...;base64 形式", nil)
		}
		comma := strings.IndexByte(s, ',')
		if comma < 0 || !strings.Contains(s[:comma], ";base64") {
			return nil, platform.ErrBadRequest("AI.IMAGE_INVALID",
				"图片必须是 base64 编码", nil)
		}
		if _, err := base64.StdEncoding.DecodeString(s[comma+1:]); err != nil {
			return nil, platform.ErrBadRequest("AI.IMAGE_INVALID",
				"图片 base64 解码失败", err)
		}
		out = append(out, s)
	}
	return out, nil
}

// mountAIChat 挂载 /v1/ai/* 路由（受 JWT 保护）。
func mountAIChat(r chi.Router, d *Deps) {
	r.Post("/ai/chat", handleAIChatStream(d))
	r.Post("/ai/feedback", handleAIChatFeedback(d))
}

// handleAIChatFeedback 记录用户对一条回答的点赞 / 点踩（rating: 1 / -1 / 0=取消）。
//
// 请求体：{ session_id?, message_id, rating, question?, answer? }
// 响应：{ ok: true }
func handleAIChatFeedback(d *Deps) http.HandlerFunc {
	type reqBody struct {
		SessionID string `json:"session_id"`
		MessageID string `json:"message_id"`
		Rating    int    `json:"rating"`
		Question  string `json:"question"`
		Answer    string `json:"answer"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		if d.Chat == nil {
			WriteError(w, r, platform.ErrUnavailable("AI.NOT_CONFIGURED", errors.New("ai chat not configured")))
			return
		}
		var body reqBody
		if err := DecodeJSON(r, &body); err != nil {
			WriteError(w, r, err)
			return
		}
		err := d.Chat.SaveFeedback(r.Context(), chat.Feedback{
			UserID:      uc.UserID,
			SessionUUID: body.SessionID,
			MessageID:   body.MessageID,
			Rating:      body.Rating,
			Question:    body.Question,
			Answer:      body.Answer,
		})
		if errors.Is(err, chat.ErrBadFeedback) {
			WriteError(w, r, platform.ErrBadRequest("AI.FEEDBACK_INVALID", "反馈参数不合法", err))
			return
		}
		if err != nil {
			WriteError(w, r, platform.ErrInternal("AI.FEEDBACK", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

// handleAIChatStream 是 AI 助理的 SSE 入口。
//
// 协议：
//   - 请求体 JSON： { session_id?, persona?, deep_mode?, system_hint?, messages:[{role:user,content:...}] }
//     兼容前端简化形态：可以传 message:"..." 字段（单条 user 消息）。
//   - 响应 Content-Type: text/event-stream
//   - 服务端按 chat.Service.Run 派发的事件名输出：session / text_delta /
//     tool_call / tool_result / done / error
//
// 注意：SSE 必须立刻 flush，HTTP/1.1 + chunked 即可；不需要禁用 chi Timeout
// 中间件，因为 chat.Run 内部循环已经按 LLM 流式拉取，没空闲超时风险。
func handleAIChatStream(d *Deps) http.HandlerFunc {
	type chatMsg struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	}
	type reqBody struct {
		SessionID        string                 `json:"session_id,omitempty"`
		Persona          string                 `json:"persona,omitempty"`
		DeepMode         bool                   `json:"deep_mode,omitempty"`
		SystemHint       string                 `json:"system_hint,omitempty"`
		Message          string                 `json:"message,omitempty"`
		Messages         []chatMsg              `json:"messages,omitempty"`
		PortfolioContext *chat.PortfolioContext `json:"portfolio_context,omitempty"`
		// Images 是本轮用户消息附带的图片（data:image/...;base64,...）。
		Images []string `json:"images,omitempty"`
		// WantSuggestions 为 true 时 done 之后追加一条 `suggestions` 事件
		// （推荐追问）。新版 App 才会传；旧版不传则协议完全不变。
		WantSuggestions bool `json:"want_suggestions,omitempty"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		if d.Chat == nil || !d.Chat.Configured() {
			WriteError(w, r, platform.ErrUnavailable("AI.NOT_CONFIGURED", errors.New("ai chat not configured")))
			return
		}

		var body reqBody
		if err := decodeJSONLarge(r, &body, maxChatBodyBytes); err != nil {
			WriteError(w, r, err)
			return
		}
		images, err := normalizeChatImages(body.Images)
		if err != nil {
			WriteError(w, r, err)
			return
		}
		userText := strings.TrimSpace(body.Message)
		if userText == "" {
			for i := len(body.Messages) - 1; i >= 0; i-- {
				if body.Messages[i].Role == "user" {
					userText = strings.TrimSpace(body.Messages[i].Content)
					break
				}
			}
		}
		// 允许「只发图不发文」。
		if userText == "" && len(images) == 0 {
			WriteError(w, r, platform.ErrBadRequest("AI.EMPTY_INPUT", "消息内容为空", nil))
			return
		}

		flusher, ok := w.(http.Flusher)
		if !ok {
			WriteError(w, r, platform.ErrInternal("SSE.NO_FLUSHER", errors.New("response writer is not a flusher")))
			return
		}
		// 关闭 http.Server 层 WriteTimeout，避免 60s 强制断流；
		// SSE 的退出由客户端断连或 chat.Run 内部 LLM/工具超时决定。
		rc := http.NewResponseController(w)
		_ = rc.SetWriteDeadline(time.Time{})
		_ = rc.SetReadDeadline(time.Time{})

		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache, no-transform")
		w.Header().Set("Connection", "keep-alive")
		w.Header().Set("X-Accel-Buffering", "no")
		w.WriteHeader(http.StatusOK)
		flusher.Flush()

		// writeMu 串行化对 ResponseWriter 的写:emit(业务事件)与心跳
		// goroutine 并发写同一个 w 不安全,必须加锁。
		var writeMu sync.Mutex

		emit := func(event string, data any) error {
			raw, err := json.Marshal(data)
			if err != nil {
				return err
			}
			line := fmt.Sprintf("event: %s\ndata: %s\n\n", event, string(raw))
			writeMu.Lock()
			defer writeMu.Unlock()
			if _, err := w.Write([]byte(line)); err != nil {
				return err
			}
			flusher.Flush()
			return nil
		}

		// 心跳 goroutine:在 chat.Run 期间周期性写 `: ping`,run 结束或客户端
		// 断连(r.Context() 取消)时退出。
		stopHeartbeat := make(chan struct{})
		go func() {
			ticker := time.NewTicker(sseHeartbeatInterval)
			defer ticker.Stop()
			for {
				select {
				case <-stopHeartbeat:
					return
				case <-r.Context().Done():
					return
				case <-ticker.C:
					writeMu.Lock()
					_, err := w.Write([]byte(": ping\n\n"))
					if err == nil {
						flusher.Flush()
					}
					writeMu.Unlock()
					if err != nil {
						return
					}
				}
			}
		}()

		_ = d.Chat.Run(r.Context(), chat.ChatInput{
			UserID:           uc.UserID,
			SessionUUID:      body.SessionID,
			Persona:          body.Persona,
			UserText:         userText,
			DeepMode:         body.DeepMode,
			SystemHint:       body.SystemHint,
			PortfolioContext: body.PortfolioContext,
			Images:           images,
			WantSuggestions:  body.WantSuggestions,
		}, emit)
		close(stopHeartbeat)
	}
}
