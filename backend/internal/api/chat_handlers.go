package api

import (
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

// mountAIChat 挂载 /v1/ai/* 路由（受 JWT 保护）。
func mountAIChat(r chi.Router, d *Deps) {
	r.Post("/ai/chat", handleAIChatStream(d))
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
	}
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		if d.Chat == nil || !d.Chat.Configured() {
			WriteError(w, r, platform.ErrUnavailable("AI.NOT_CONFIGURED", errors.New("ai chat not configured")))
			return
		}

		var body reqBody
		if err := DecodeJSON(r, &body); err != nil {
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
		if userText == "" {
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
		}, emit)
		close(stopHeartbeat)
	}
}
