package chat

import (
	"context"
	"encoding/json"
	"path/filepath"
	"testing"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

// newTestRepo 建一个临时 SQLite（含全部 migration）+ 一个测试用户。
// ai_chat_sessions.user_id 有外键约束，必须先把用户插进去。
func newTestRepo(t *testing.T) *SessionRepo {
	t.Helper()
	st, err := store.Open(platform.DBConfig{
		Path:          filepath.Join(t.TempDir(), "chat_test.db"),
		BusyTimeoutMs: 5000,
		CacheKB:       4096,
		MaxOpenConns:  2,
		MaxIdleConns:  1,
	})
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { _ = st.Close() })
	if _, err := st.DB.Exec(
		`INSERT INTO users(id, uuid, nickname, created_at, updated_at)
		 VALUES(1, 'test-user', 'tester', 0, 0)`); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	return NewSessionRepo(st)
}

// 带图 user 消息要能落库、按历史取回，并重建成多模态片段；不带图回放时
// 退化成纯文本（避免历史图片无限重发进 prompt）。
func TestUserImagesPersistAndMapToMultimodal(t *testing.T) {
	ctx := context.Background()
	repo := newTestRepo(t)
	sess, err := repo.CreateOrLoad(ctx, 1, "", "default")
	if err != nil {
		t.Fatalf("create session: %v", err)
	}

	images := []string{"data:image/jpeg;base64,AAAA"}
	raw, _ := json.Marshal(images)
	if _, err := repo.AppendUser(ctx, sess.ID, "看看这张图", string(raw)); err != nil {
		t.Fatalf("append user: %v", err)
	}

	hist, err := repo.LoadHistory(ctx, sess.ID, 10)
	if err != nil {
		t.Fatalf("load history: %v", err)
	}
	if len(hist) != 1 {
		t.Fatalf("history len = %d, want 1", len(hist))
	}
	if !hist[0].ImagesJSON.Valid || hist[0].ImagesJSON.String != string(raw) {
		t.Fatalf("images_json 未正确落库: %+v", hist[0].ImagesJSON)
	}

	withImages := mapMessageToLLM(hist[0], true)
	if len(withImages.Parts) != 2 {
		t.Fatalf("multimodal parts = %d, want 2 (text + image)", len(withImages.Parts))
	}
	if withImages.Parts[0].Type != "text" || withImages.Parts[1].Type != "image_url" {
		t.Fatalf("unexpected parts: %+v", withImages.Parts)
	}
	if withImages.Parts[1].ImageURL == nil ||
		withImages.Parts[1].ImageURL.URL != images[0] {
		t.Fatalf("image url 丢失: %+v", withImages.Parts[1])
	}

	withoutImages := mapMessageToLLM(hist[0], false)
	if len(withoutImages.Parts) != 0 {
		t.Fatalf("不保留图片时应无 parts, got %+v", withoutImages.Parts)
	}
	if withoutImages.Content != "看看这张图" {
		t.Fatalf("正文丢失: %q", withoutImages.Content)
	}
}

// 只发图不发文：正文为空也要能落库并重建出纯图片片段。
func TestImageOnlyMessage(t *testing.T) {
	ctx := context.Background()
	repo := newTestRepo(t)
	sess, err := repo.CreateOrLoad(ctx, 1, "", "default")
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	raw, _ := json.Marshal([]string{"data:image/png;base64,BBBB"})
	if _, err := repo.AppendUser(ctx, sess.ID, "", string(raw)); err != nil {
		t.Fatalf("append user: %v", err)
	}
	hist, err := repo.LoadHistory(ctx, sess.ID, 10)
	if err != nil {
		t.Fatalf("load history: %v", err)
	}
	if len(hist) != 1 {
		t.Fatalf("history len = %d, want 1", len(hist))
	}
	msg := mapMessageToLLM(hist[0], true)
	if len(msg.Parts) != 1 || msg.Parts[0].Type != "image_url" {
		t.Fatalf("只发图应只产生 image_url 片段: %+v", msg.Parts)
	}
}
