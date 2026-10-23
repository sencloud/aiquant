package story

import (
	"context"
	"path/filepath"
	"strings"
	"testing"

	"github.com/sencloud/finme-backend/internal/llm"
	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

func testStore(t *testing.T) *store.Store {
	t.Helper()
	st, err := store.Open(platform.DBConfig{
		Path:          filepath.Join(t.TempDir(), "story.db"),
		BusyTimeoutMs: 5000,
		CacheKB:       2048,
		MaxOpenConns:  4,
		MaxIdleConns:  2,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = st.Close() })
	return st
}

type fakeStreamer struct {
	calls int
	last  llm.StreamRequest
	text  string
}

func (f *fakeStreamer) ChatStream(_ context.Context, req llm.StreamRequest, emit func(llm.StreamEvent) error) error {
	f.calls++
	f.last = req
	if f.text == "" {
		f.text = "我在。"
	}
	if err := emit(llm.StreamEvent{Type: "text_delta", TextDelta: f.text}); err != nil {
		return err
	}
	return emit(llm.StreamEvent{Type: "done", FinalText: f.text})
}

func saveInput(character string) SaveInput {
	return SaveInput{
		SeasonID:    SeasonID,
		CharacterID: character,
		Night:       1,
		Beat:        0,
		Hearts:      2,
		Flags:       []string{"answered_rain"},
	}
}

func TestConfigDefaultsAndUpdate(t *testing.T) {
	st := testStore(t)
	svc := New(st, nil, "fake")
	ctx := context.Background()

	cfg, err := svc.Config(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.Enabled || !cfg.ShareEnabled || cfg.MaxTurns != MaxTurns {
		t.Fatalf("defaults=%+v", cfg)
	}
	if len(cfg.Characters) != 3 {
		t.Fatalf("default characters=%v", cfg.Characters)
	}

	cfg, err = svc.SetConfig(ctx, ConfigInput{
		Enabled:      false,
		Characters:   []string{"suyu", "suyu", "nobody"},
		ShareEnabled: false,
		MaxTurns:     12,
		Notice:       "今晚不营业",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Enabled || cfg.ShareEnabled {
		t.Fatalf("flags not applied: %+v", cfg)
	}
	if len(cfg.Characters) != 1 || cfg.Characters[0] != "suyu" {
		t.Fatalf("characters=%v", cfg.Characters)
	}
	if cfg.MaxTurns != 12 || cfg.Notice != "今晚不营业" {
		t.Fatalf("cfg=%+v", cfg)
	}

	// 越界 max_turns 回落到默认，不会把聊天关死。
	cfg, err = svc.SetConfig(ctx, ConfigInput{
		Enabled: true, ShareEnabled: true, Characters: []string{"linxia"}, MaxTurns: 0,
	})
	if err != nil {
		t.Fatal(err)
	}
	if cfg.MaxTurns != MaxTurns {
		t.Fatalf("max_turns=%d, want %d", cfg.MaxTurns, MaxTurns)
	}

	// 总开关关闭后，伪造请求也不能再写进度。
	if _, err := svc.SetConfig(ctx, ConfigInput{Enabled: false, Characters: []string{"linxia"}}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Save(ctx, 1, "run-closed", SaveInput{
		SeasonID: "before_dawn_s1", CharacterID: "linxia", Night: 1, Beat: 0, Hearts: 2,
	}); err == nil {
		t.Fatal("disabled story accepted Save")
	}
}

func TestSaveStateAndEnding(t *testing.T) {
	st := testStore(t)
	svc := New(st, nil, "fake")
	ctx := context.Background()
	id := NewRunID()

	run, err := svc.Save(ctx, 7, id, saveInput("linxia"))
	if err != nil {
		t.Fatal(err)
	}
	if run.ID != id || run.Night != 1 || run.Hearts != 2 {
		t.Fatalf("unexpected run: %+v", run)
	}
	if len(run.Flags) != 1 || run.Flags[0] != "answered_rain" {
		t.Fatalf("flags=%v", run.Flags)
	}

	state, err := svc.State(ctx, 7, id)
	if err != nil {
		t.Fatal(err)
	}
	if state.Run == nil || state.Run.ID != id {
		t.Fatalf("state run=%+v", state.Run)
	}

	in := saveInput("linxia")
	in.Night = 7
	in.Hearts = 5
	in.Finished = true
	in.EndingID = "linxia_he"
	if _, err := svc.Save(ctx, 7, id, in); err != nil {
		t.Fatal(err)
	}
	endings, err := svc.Endings(ctx, 7)
	if err != nil {
		t.Fatal(err)
	}
	if len(endings) != 1 || endings[0] != "linxia_he" {
		t.Fatalf("endings=%v", endings)
	}
}

func TestSaveRejectsAnotherUser(t *testing.T) {
	st := testStore(t)
	svc := New(st, nil, "fake")
	ctx := context.Background()
	id := NewRunID()

	if _, err := svc.Save(ctx, 1, id, saveInput("linxia")); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Save(ctx, 2, id, saveInput("linxia")); err == nil {
		t.Fatal("expected error when another user overwrites the run")
	}
}

func TestValidateSave(t *testing.T) {
	cases := []struct {
		name string
		id   string
		in   SaveInput
	}{
		{"bad id", "../x", saveInput("linxia")},
		{"bad character", NewRunID(), saveInput("nobody")},
		{"bad night", NewRunID(), func() SaveInput { v := saveInput("linxia"); v.Night = 9; return v }()},
		{"bad hearts", NewRunID(), func() SaveInput { v := saveInput("linxia"); v.Hearts = 6; return v }()},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if err := validateSave(tc.id, tc.in); err == nil {
				t.Fatal("expected validation error")
			}
		})
	}
}

func TestChatStreamsAndPersists(t *testing.T) {
	st := testStore(t)
	fake := &fakeStreamer{text: "雨还没停。伞在我这儿。"}
	svc := New(st, fake, "fake-model")
	ctx := context.Background()
	id := NewRunID()
	if _, err := svc.Save(ctx, 7, id, saveInput("linxia")); err != nil {
		t.Fatal(err)
	}

	var events []string
	var done map[string]any
	err := svc.Chat(ctx, 7, id, ChatInput{
		Message: "你那边下雨了吗？",
		Scene: SceneContext{
			Night: 1, Beat: 0, BeatID: "n1b1",
			Place: "旧公寓 · 七楼", Scene: "雨",
			BeatNote: "窗外的雨正敲在空调外机上。",
			Opening:  []string{"你那边下雨了吗？"},
		},
	}, func(event string, data any) error {
		events = append(events, event)
		if event == "done" {
			done, _ = data.(map[string]any)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if fake.calls != 1 {
		t.Fatalf("llm calls=%d", fake.calls)
	}
	if done == nil || done["text"] != "雨还没停。伞在我这儿。" {
		t.Fatalf("done=%v", done)
	}
	if !strings.Contains(fake.last.Messages[0].Content, "林夏") ||
		!strings.Contains(fake.last.Messages[0].Content, "不推进剧情") {
		t.Fatalf("system prompt missing character/rules: %s", fake.last.Messages[0].Content)
	}
	state, err := svc.State(ctx, 7, id)
	if err != nil {
		t.Fatal(err)
	}
	if len(state.Messages) != 2 {
		t.Fatalf("messages=%d, want 2", len(state.Messages))
	}
	if state.Messages[0].Role != "user" || state.Messages[1].Role != "assistant" {
		t.Fatalf("roles=%s/%s", state.Messages[0].Role, state.Messages[1].Role)
	}
}

func TestChatSafetyStopsBeforeLLM(t *testing.T) {
	st := testStore(t)
	fake := &fakeStreamer{}
	svc := New(st, fake, "fake")
	ctx := context.Background()
	id := NewRunID()
	if _, err := svc.Save(ctx, 7, id, saveInput("linxia")); err != nil {
		t.Fatal(err)
	}

	var done map[string]any
	err := svc.Chat(ctx, 7, id, ChatInput{Message: "我不想活了"},
		func(event string, data any) error {
			if event == "done" {
				done, _ = data.(map[string]any)
			}
			return nil
		})
	if err != nil {
		t.Fatal(err)
	}
	if fake.calls != 0 {
		t.Fatalf("safety message should not call LLM, calls=%d", fake.calls)
	}
	if done == nil || done["safety"] != true {
		t.Fatalf("done=%v", done)
	}
	state, _ := svc.State(ctx, 7, id)
	if len(state.Messages) != 2 || !state.Messages[1].Safety {
		t.Fatalf("messages=%+v", state.Messages)
	}
}

func TestChatRequiresRun(t *testing.T) {
	st := testStore(t)
	svc := New(st, &fakeStreamer{}, "fake")
	err := svc.Chat(context.Background(), 7, NewRunID(), ChatInput{Message: "在吗"},
		func(event string, data any) error { return nil })
	if err != nil {
		t.Fatal(err)
	}
}

func TestDeleteRun(t *testing.T) {
	st := testStore(t)
	svc := New(st, nil, "fake")
	ctx := context.Background()
	id := NewRunID()
	if _, err := svc.Save(ctx, 7, id, saveInput("linxia")); err != nil {
		t.Fatal(err)
	}
	if err := svc.Delete(ctx, 7, id); err != nil {
		t.Fatal(err)
	}
	state, err := svc.State(ctx, 7, "")
	if err != nil {
		t.Fatal(err)
	}
	if state.Run != nil {
		t.Fatalf("run should be deleted: %+v", state.Run)
	}
}
