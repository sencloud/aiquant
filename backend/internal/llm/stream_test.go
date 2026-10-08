package llm

import (
	"encoding/json"
	"strings"
	"testing"
)

// 多模态 content 的序列化语义必须精确：普通消息仍是字符串、空正文的
// assistant(tool_calls) 仍省略 content、带图消息才变成片段数组。
func TestMessageWithToolsMarshalJSON(t *testing.T) {
	cases := []struct {
		name string
		msg  MessageWithTools
		want string
	}{
		{
			name: "纯文本保持字符串",
			msg:  MessageWithTools{Role: "user", Content: "你好"},
			want: `"content":"你好"`,
		},
		{
			name: "空正文带 tool_calls 省略 content",
			msg: MessageWithTools{
				Role:      "assistant",
				ToolCalls: []ToolCall{{ID: "call_1", Type: "function"}},
			},
			want: `"tool_calls":[{"id":"call_1","type":"function","function":{"name":"","arguments":""}}]`,
		},
		{
			name: "带图消息 content 变成片段数组",
			msg: MessageWithTools{
				Role:    "user",
				Content: "看看这张图",
				Parts:   BuildMultimodalParts("看看这张图", []string{"data:image/png;base64,AAAA"}),
			},
			want: `"content":[{"type":"text","text":"看看这张图"},{"type":"image_url","image_url":{"url":"data:image/png;base64,AAAA"}}]`,
		},
		{
			name: "只发图不带文字",
			msg: MessageWithTools{
				Role:  "user",
				Parts: BuildMultimodalParts("  ", []string{"data:image/png;base64,AAAA"}),
			},
			want: `"content":[{"type":"image_url","image_url":{"url":"data:image/png;base64,AAAA"}}]`,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			raw, err := json.Marshal(tc.msg)
			if err != nil {
				t.Fatalf("marshal: %v", err)
			}
			if !strings.Contains(string(raw), tc.want) {
				t.Fatalf("marshal mismatch\n got: %s\nwant contains: %s", raw, tc.want)
			}
			if tc.name == "空正文带 tool_calls 省略 content" && strings.Contains(string(raw), "content") {
				t.Fatalf("空正文不应出现 content 字段: %s", raw)
			}
		})
	}
}

// 无 Parts 时 BuildMultimodalParts 不应该产生空的 text 片段。
func TestBuildMultimodalPartsSkipsBlankText(t *testing.T) {
	parts := BuildMultimodalParts("   ", nil)
	if len(parts) != 0 {
		t.Fatalf("空正文 + 无图应返回空片段, got %+v", parts)
	}
}
