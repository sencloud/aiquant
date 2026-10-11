package llm

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestChatWithJSONMode(t *testing.T) {
	var got map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = nil
		_ = json.NewDecoder(r.Body).Decode(&got)
		finish := "stop"
		if got["max_tokens"] != nil {
			finish = "length"
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []any{map[string]any{"message": map[string]any{"content": `{"a":1}`}, "finish_reason": finish}},
			"usage":   map[string]any{"prompt_tokens": 3, "completion_tokens": 4},
		})
	}))
	defer srv.Close()
	c, _ := NewDeepSeek("k", srv.URL, "m", "r", time.Second)
	res, err := c.ChatWith(context.Background(), "", []Message{{Role: "user", Content: "hi"}}, ChatOptions{JSON: true, Temperature: 0.2})
	if err != nil || res.Content != `{"a":1}` || res.Usage.CompletionTokens != 4 {
		t.Fatalf("res=%+v err=%v", res, err)
	}
	rf, _ := got["response_format"].(map[string]any)
	if rf["type"] != "json_object" || got["model"] != "m" {
		t.Fatalf("request = %v", got)
	}
	_, err = c.ChatWith(context.Background(), "x", nil, ChatOptions{MaxTokens: 5})
	if !errors.Is(err, ErrTruncated) {
		t.Fatalf("want truncated, got %v", err)
	}
	if got["response_format"] != nil {
		t.Fatalf("json mode leaked: %v", got)
	}
}
