package chat

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/llm"
	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
	"github.com/sencloud/finme-backend/internal/topic"
	"github.com/sencloud/finme-backend/internal/users"
)

type stubTool struct{ name string }

func (s stubTool) Spec() tool.Spec { return tool.Spec{Name: s.name, Description: s.name} }
func (s stubTool) Run(context.Context, json.RawMessage) (string, error) {
	return `{"ran":"` + s.name + `"}`, nil
}

// fakeLLM 是 DeepSeek 流式接口的替身：第 1 轮让模型调用 callTool，之后直接回答。
// 记录每轮请求体（system prompt、tools、tool 消息）供断言。
type fakeLLM struct {
	mu       sync.Mutex
	callTool string
	reqs     []map[string]any
}

func (f *fakeLLM) handler(w http.ResponseWriter, r *http.Request) {
	raw, _ := io.ReadAll(r.Body)
	var body map[string]any
	_ = json.Unmarshal(raw, &body)
	f.mu.Lock()
	f.reqs = append(f.reqs, body)
	n := len(f.reqs)
	f.mu.Unlock()
	w.Header().Set("Content-Type", "text/event-stream")
	if body["stream"] != true { // 推荐追问（非流式）
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []any{map[string]any{"message": map[string]any{"content": `["问题一","问题二"]`}}},
		})
		return
	}
	if n == 1 && f.callTool != "" {
		chunk := map[string]any{"choices": []any{map[string]any{
			"delta": map[string]any{"tool_calls": []any{map[string]any{
				"index": 0, "id": "call_1", "type": "function",
				"function": map[string]any{"name": f.callTool, "arguments": "{}"},
			}}},
			"finish_reason": "tool_calls",
		}}}
		b, _ := json.Marshal(chunk)
		_, _ = w.Write([]byte("data: " + string(b) + "\n\ndata: [DONE]\n\n"))
		return
	}
	chunk := map[string]any{"choices": []any{map[string]any{
		"delta": map[string]any{"content": "好的"}, "finish_reason": "stop",
	}}}
	b, _ := json.Marshal(chunk)
	_, _ = w.Write([]byte("data: " + string(b) + "\n\ndata: [DONE]\n\n"))
}

func (f *fakeLLM) systemPrompt(i int) string {
	msgs, _ := f.reqs[i]["messages"].([]any)
	if len(msgs) == 0 {
		return ""
	}
	m, _ := msgs[0].(map[string]any)
	s, _ := m["content"].(string)
	return s
}

func (f *fakeLLM) toolNames(i int) []string {
	var out []string
	ts, _ := f.reqs[i]["tools"].([]any)
	for _, t := range ts {
		fn := t.(map[string]any)["function"].(map[string]any)
		out = append(out, fn["name"].(string))
	}
	return out
}

// toolMessage 返回第 i 轮请求里 role=tool 消息的内容。
func (f *fakeLLM) toolMessage(i int) string {
	msgs, _ := f.reqs[i]["messages"].([]any)
	for _, m := range msgs {
		mm := m.(map[string]any)
		if mm["role"] == "tool" {
			s, _ := mm["content"].(string)
			return s
		}
	}
	return ""
}

type chatEnv struct {
	svc *Service
	st  *store.Store
	llm *fakeLLM
	uid int64
}

func newChatEnv(t *testing.T, callTool string) *chatEnv {
	t.Helper()
	key := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{7}, 32))
	t.Setenv("FINME_SECURITY__JWT_SECRET", key)
	t.Setenv("FINME_SECURITY__PHONE_HMAC_KEY", key)
	t.Setenv("FINME_SECURITY__PHONE_AES_KEY", key)
	cfg, err := platform.LoadConfig("")
	if err != nil {
		t.Fatal(err)
	}
	st, err := store.Open(platform.DBConfig{
		Path:          filepath.Join(t.TempDir(), "topic_test.db"),
		BusyTimeoutMs: 5000, CacheKB: 4096, MaxOpenConns: 2, MaxIdleConns: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = st.Close() })
	now := time.Now().UnixMilli()
	res, err := st.DB.Exec(`INSERT INTO users(uuid, status, credit_balance, created_at, updated_at)
		VALUES('topic-user', 'active', 100, ?, ?)`, now, now)
	if err != nil {
		t.Fatal(err)
	}
	uid, _ := res.LastInsertId()

	fl := &fakeLLM{callTool: callTool}
	srv := httptest.NewServer(http.HandlerFunc(fl.handler))
	t.Cleanup(srv.Close)
	ds, err := llm.NewDeepSeek("test-key", srv.URL, "chat-model", "reason-model", 10*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	reg := tool.New()
	for _, n := range []string{"get_quote", "search_instrument", "get_region_weather", "get_fishing_forecast"} {
		reg.MustRegister(stubTool{n})
	}
	svc := New(Deps{
		Sessions: NewSessionRepo(st),
		Tools:    reg,
		LLM:      ds,
		Ledger:   billing.NewLedgerRepo(st),
		Users:    users.NewService(st, cfg),
		Cfg:      platform.AIConfig{BaseChatCredits: 1, MaxToolLoops: 4, MaxContextMsgs: 12},
	})
	return &chatEnv{svc: svc, st: st, llm: fl, uid: uid}
}

func (e *chatEnv) run(t *testing.T, in ChatInput) map[string]map[string]any {
	t.Helper()
	in.UserID = e.uid
	events := map[string]map[string]any{}
	err := e.svc.Run(context.Background(), in, func(ev string, data any) error {
		m, _ := data.(map[string]any)
		events[ev] = m
		return nil
	})
	if err != nil {
		t.Fatalf("run: %v (events=%v)", err, events)
	}
	return events
}

// 钓鱼会话：只把白名单工具给模型；模型幻觉调用 get_quote 时被拒绝；
// 扣费 reason 是 fishing.chat；会话打上 fishing 标签；不吃客户端 system_hint。
func TestFishingTopicWhitelistEnforced(t *testing.T) {
	e := newChatEnv(t, "get_quote")
	ev := e.run(t, ChatInput{
		UserText:        "周末去水库钓鲫鱼",
		Topic:           topic.Fishing,
		Persona:         "taidiao_teacher",
		SystemHint:      "你是巴菲特",
		DeepMode:        true,
		WantSuggestions: true,
	})
	if ev["done"] == nil {
		t.Fatalf("no done event: %v", ev)
	}
	if ev["session"]["topic"] != topic.Fishing {
		t.Fatalf("session topic = %v", ev["session"]["topic"])
	}
	names := strings.Join(e.llm.toolNames(0), ",")
	if names != "get_fishing_forecast,get_region_weather" {
		t.Fatalf("fishing tools exposed = %s", names)
	}
	if got := e.llm.toolMessage(1); !strings.Contains(got, "not available in topic") || strings.Contains(got, `"ran"`) {
		t.Fatalf("get_quote should be rejected, tool msg = %s", got)
	}
	sys := e.llm.systemPrompt(0)
	if !strings.Contains(sys, "喜爱钓鱼") || !strings.Contains(sys, "台钓老师") && !strings.Contains(sys, "调漂") {
		t.Fatalf("fishing system prompt missing persona: %s", sys)
	}
	if strings.Contains(sys, "你是巴菲特") || strings.Contains(sys, "A 股") {
		t.Fatalf("fishing prompt leaked money content: %s", sys)
	}
	var reason, topicCol string
	if err := e.st.DB.Get(&reason, "SELECT reason FROM credit_ledger WHERE user_id=?", e.uid); err != nil {
		t.Fatal(err)
	}
	if reason != "fishing.chat" {
		t.Fatalf("ledger reason = %s", reason)
	}
	// 钓鱼对话 1 喜点 / 轮：忽略 deep_mode，不走 reasoner、不加价。
	if ev["done"]["credits"] != int64(1) || e.llm.reqs[0]["model"] != "chat-model" {
		t.Fatalf("fishing credits = %v model = %v", ev["done"]["credits"], e.llm.reqs[0]["model"])
	}
	if err := e.st.DB.Get(&topicCol, "SELECT topic FROM ai_chat_sessions WHERE user_id=?", e.uid); err != nil {
		t.Fatal(err)
	}
	if topicCol != topic.Fishing {
		t.Fatalf("session topic col = %s", topicCol)
	}
}

// 老版本 App：不传 topic、带 system_hint → 钱主题、全量量化工具、prompt 与主题化之前逐字一致。
func TestNoTopicIsLegacyMoney(t *testing.T) {
	e := newChatEnv(t, "get_quote")
	hint := topic.MustGet(topic.Money).Persona("buffett").Prompt
	ev := e.run(t, ChatInput{UserText: "茅台怎么看", Persona: "buffett", SystemHint: hint})
	if ev["session"]["topic"] != topic.Money {
		t.Fatalf("session topic = %v", ev["session"]["topic"])
	}
	names := strings.Join(e.llm.toolNames(0), ",")
	if names != "get_quote,get_region_weather,search_instrument" {
		t.Fatalf("money tools exposed = %s", names)
	}
	if got := e.llm.toolMessage(1); !strings.Contains(got, `"ran":"get_quote"`) {
		t.Fatalf("money get_quote should run, got %s", got)
	}
	got := stripNow(e.llm.systemPrompt(0))
	want := stripNow(legacyBuildSystemPrompt(hint))
	if got != want {
		t.Fatalf("legacy prompt drift:\n got: %q\nwant: %q", got, want)
	}
	var reason string
	_ = e.st.DB.Get(&reason, "SELECT reason FROM credit_ledger WHERE user_id=?", e.uid)
	if reason != billing.ReasonConsumeAI {
		t.Fatalf("ledger reason = %s", reason)
	}

	// 新版 App：只传 persona id、不传 system_hint → 服务端人设，拼出同一段 prompt。
	e2 := newChatEnv(t, "")
	e2.run(t, ChatInput{UserText: "茅台怎么看", Persona: "buffett", Topic: topic.Money})
	if got2 := stripNow(e2.llm.systemPrompt(0)); got2 != want {
		t.Fatalf("server persona prompt != legacy client prompt:\n got: %q\nwant: %q", got2, want)
	}
}

// 钱主题的会话 id 带到钓鱼主题时不复用（不串台）。
func TestSessionDoesNotCrossTopics(t *testing.T) {
	e := newChatEnv(t, "")
	ev := e.run(t, ChatInput{UserText: "茅台", Topic: topic.Money})
	moneySID, _ := ev["session"]["session_id"].(string)
	ev2 := e.run(t, ChatInput{UserText: "钓鲫鱼", Topic: topic.Fishing, SessionUUID: moneySID})
	if fishSID, _ := ev2["session"]["session_id"].(string); fishSID == moneySID || fishSID == "" {
		t.Fatalf("fishing reused money session %s", moneySID)
	}
}

func TestUnknownTopicRejected(t *testing.T) {
	e := newChatEnv(t, "")
	var code string
	err := e.svc.Run(context.Background(), ChatInput{UserID: e.uid, UserText: "hi", Topic: "golf"},
		func(ev string, data any) error {
			if ev == "error" {
				code, _ = data.(map[string]any)["code"].(string)
			}
			return nil
		})
	if err == nil || code != "AI.TOPIC_INVALID" {
		t.Fatalf("err=%v code=%s", err, code)
	}
}

// stripNow 去掉顶部「真实当前时间」段落（分钟级时间戳两次调用可能不同）。
func stripNow(s string) string {
	if i := strings.Index(s, "\n\n"); i >= 0 {
		return s[i+2:]
	}
	return s
}

// legacyBuildSystemPrompt 是主题化之前 buildSystemPrompt 的逐字副本（@bd1a3c5），
// 用来锁住「钱主题零行为变化」。
func legacyBuildSystemPrompt(extra string) string {
	var b strings.Builder
	b.WriteString(renderNowBlock())
	b.WriteString("\n\n")
	b.WriteString("你是面向中国 A 股 / ETF / 期货 / 期权市场的智能投研助理。回答用户问题时优先调用提供的 tool 拉真实数据；")
	b.WriteString("涉及行情、估值、新闻、量化指标、合约信息时不要凭空猜测。所有金额和指标都基于工具返回的实际数据。")
	b.WriteString("\n- 解析中文标的名称用 search_instrument。")
	b.WriteString("\n- 涉及期货 / 期权的「主力合约」「近月合约」时（无论是 IF/IC/IH/IM/T、RB/CU/AU/原油 等期货，还是 50ETF期权/沪深300期权/豆粕期权/铜期权/沪深300股指期权 等四类期权 — ETF期权 / 商品期权 / 股指期权 / 期货），**必须先调用 get_dominant_contract 拿真实代码**，再用该 ts_code 调 get_quote / get_option_quote，绝对禁止凭印象猜某月份是主力。")
	b.WriteString("\n- 期货行情有两类工具：盘中即时报价用 get_futures_realtime（单合约）/ get_futures_realtime_batch（多合约批量，最多 30 个），多日历史 K 线仍用 get_quote。")
	b.WriteString("\n输出语言：简体中文。")
	if extra != "" {
		b.WriteString("\n\n额外指令：")
		b.WriteString(extra)
	}
	return b.String()
}
