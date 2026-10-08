package brief

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

func TestPhaseAtBoundaries(t *testing.T) {
	at := func(h, m int) time.Time {
		return time.Date(2026, 10, 8, h, m, 0, 0, ShanghaiLoc)
	}
	cases := []struct {
		t    time.Time
		want Phase
	}{
		{at(0, 5), PhasePreOpen},
		{at(9, 14), PhasePreOpen},
		{at(9, 15), PhaseMorning},
		{at(11, 29), PhaseMorning},
		{at(11, 30), PhaseNoon},
		{at(12, 59), PhaseNoon},
		{at(13, 0), PhaseAfternoon},
		{at(14, 59), PhaseAfternoon},
		{at(15, 0), PhaseClosed},
		{at(23, 59), PhaseClosed},
	}
	for _, c := range cases {
		if got := PhaseAt(c.t); got != c.want {
			t.Errorf("PhaseAt(%s) = %s, want %s", c.t.Format("15:04"), got, c.want)
		}
	}
	if !IsTradingDay(at(12, 0)) {
		t.Error("周四应为交易日")
	}
	if IsTradingDay(time.Date(2026, 10, 10, 12, 0, 0, 0, ShanghaiLoc)) {
		t.Error("周六不应为交易日")
	}
}

func TestParseQuestions(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want []string
	}{
		{"纯 JSON 数组", `["今天大盘怎么样？","哪些板块强？"]`,
			[]string{"今天大盘怎么样？", "哪些板块强？"}},
		{"带代码块包裹", "```json\n[\"复盘一下今天\",\"明天怎么看\"]\n```",
			[]string{"复盘一下今天", "明天怎么看"}},
		{"前后有废话", "好的，这里是结果：[\"只看这个\"]希望有帮助",
			[]string{"只看这个"}},
		{"退化成编号列表", "1. 今天上证收了多少？\n2. 明天怎么走？",
			[]string{"今天上证收了多少？", "明天怎么走？"}},
		{"空输出", "   ", nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := parseQuestions(c.in)
			if len(got) != len(c.want) {
				t.Fatalf("got %v, want %v", got, c.want)
			}
			for i := range got {
				if got[i] != c.want[i] {
					t.Fatalf("got %v, want %v", got, c.want)
				}
			}
		})
	}
}

func TestTemplateQuestionsAlwaysNonEmpty(t *testing.T) {
	snaps := []Snapshot{
		{Code: "000001.SH", Name: "上证指数", Open: 3838.98, Last: 3811.90, PctChg: -0.79},
		{Code: "000688.SH", Name: "科创50", Open: 1512.79, Last: 1456.32, PctChg: -4.82},
	}
	for _, p := range []Phase{PhasePreOpen, PhaseMorning, PhaseNoon, PhaseAfternoon, PhaseClosed} {
		for _, in := range [][]Snapshot{nil, snaps} {
			qs := templateQuestions(p, in)
			if len(qs) != 3 {
				t.Fatalf("phase %s 应生成 3 条提问, got %d", p, len(qs))
			}
			for _, q := range qs {
				if q == "" {
					t.Fatalf("phase %s 出现空提问", p)
				}
			}
		}
	}
}

// 同一时段重复执行只落一条；Latest 能读回并带上中文时段名。
func TestEnsureSlotIsIdempotent(t *testing.T) {
	st, err := store.Open(platform.DBConfig{
		Path:          filepath.Join(t.TempDir(), "brief_test.db"),
		BusyTimeoutMs: 5000,
		CacheKB:       4096,
		MaxOpenConns:  2,
		MaxIdleConns:  1,
	})
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	defer st.Close()

	l := zerolog.Nop()
	svc := NewService(st, &l, nil, nil, "") // llm / realtime 都缺失 → 走模板兜底
	ctx := context.Background()

	first := time.Date(2026, 10, 8, 15, 30, 0, 0, ShanghaiLoc)
	created, err := svc.EnsureSlot(ctx, first)
	if err != nil {
		t.Fatalf("first EnsureSlot: %v", err)
	}
	if !created {
		t.Fatal("首次应生成一条")
	}

	// 同属「收盘」时段的另一个时刻：不应重复生成。
	created, err = svc.EnsureSlot(ctx, time.Date(2026, 10, 8, 16, 30, 0, 0, ShanghaiLoc))
	if err != nil {
		t.Fatalf("second EnsureSlot: %v", err)
	}
	if created {
		t.Fatal("同一时段重复执行不应再生成")
	}

	var count int
	if err := st.DB.Get(&count, `SELECT COUNT(*) FROM ai_home_suggestions`); err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != 1 {
		t.Fatalf("应只有 1 条, got %d", count)
	}

	sug, err := svc.Latest(ctx)
	if err != nil {
		t.Fatalf("Latest: %v", err)
	}
	if sug == nil || len(sug.Questions) != 3 {
		t.Fatalf("Latest 应返回 3 条提问, got %+v", sug)
	}
	if sug.PhaseLabel != "收盘" || sug.Source != "template" {
		t.Fatalf("unexpected suggestion: %+v", sug)
	}
	if sug.TradeDate != "2026-10-08" || sug.Phase != string(PhaseClosed) {
		t.Fatalf("unexpected trade date/phase: %s %s", sug.TradeDate, sug.Phase)
	}
}
