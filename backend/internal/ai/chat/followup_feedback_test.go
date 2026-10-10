package chat

import (
	"context"
	"errors"
	"reflect"
	"testing"
)

func TestParseFollowUps(t *testing.T) {
	cases := []struct {
		name string
		raw  string
		want []string
	}{
		{"纯 JSON", `["棕榈油库存怎么看？","豆油和棕榈油价差？","明天会涨吗？"]`,
			[]string{"棕榈油库存怎么看？", "豆油和棕榈油价差？", "明天会涨吗？"}},
		{"代码块包裹 + 超过三条", "```json\n[\"a\",\"b\",\"c\",\"d\"]\n```", []string{"a", "b", "c"}},
		{"按行退化 + 去编号", "1. 第一个问题\n2、第二个问题\n- 第三个问题", []string{"第一个问题", "第二个问题", "第三个问题"}},
		{"去重并剔除原问题", `["原问题","x","x"]`, []string{"x"}},
		{"空输出", "", []string{}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := parseFollowUps(c.raw, "原问题")
			if !reflect.DeepEqual(got, c.want) {
				t.Fatalf("got %#v want %#v", got, c.want)
			}
		})
	}
	long := parseFollowUps(`["`+string(make([]rune, 0))+"一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一二三四五"+`"]`, "")
	if len([]rune(long[0])) != maxFollowUpRunes {
		t.Fatalf("expected truncation to %d runes, got %d", maxFollowUpRunes, len([]rune(long[0])))
	}
}

func TestUpsertFeedback(t *testing.T) {
	ctx := context.Background()
	repo := newTestRepo(t)
	count := func() (n int, rating int) {
		_ = repo.st.DB.Get(&n, `SELECT COUNT(*) FROM ai_chat_feedback WHERE user_id=1`)
		_ = repo.st.DB.Get(&rating, `SELECT COALESCE(MAX(rating),0) FROM ai_chat_feedback WHERE user_id=1`)
		return
	}
	f := Feedback{UserID: 1, SessionUUID: "s1", MessageID: "m1", Rating: 1, Question: "q", Answer: "a"}
	if err := repo.UpsertFeedback(ctx, f); err != nil {
		t.Fatal(err)
	}
	f.Rating = -1
	if err := repo.UpsertFeedback(ctx, f); err != nil {
		t.Fatal(err)
	}
	if n, r := count(); n != 1 || r != -1 {
		t.Fatalf("after update: n=%d rating=%d", n, r)
	}
	f.Rating = 0
	if err := repo.UpsertFeedback(ctx, f); err != nil {
		t.Fatal(err)
	}
	if n, _ := count(); n != 0 {
		t.Fatalf("after cancel: n=%d", n)
	}
	if err := repo.UpsertFeedback(ctx, Feedback{UserID: 1, MessageID: "m2", Rating: 5}); !errors.Is(err, ErrBadFeedback) {
		t.Fatalf("expected ErrBadFeedback, got %v", err)
	}
	if err := repo.UpsertFeedback(ctx, Feedback{UserID: 1, MessageID: " ", Rating: 1}); !errors.Is(err, ErrBadFeedback) {
		t.Fatalf("expected ErrBadFeedback for empty id, got %v", err)
	}
}
