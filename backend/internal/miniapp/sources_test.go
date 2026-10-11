package miniapp

import (
	"context"
	"strings"
	"testing"
	"time"
)

func TestFetcherRecoversAdapterPanic(t *testing.T) {
	r := NewRegistry()
	r.Register(&Source{ID: "boom.x", Title: "炸", Topics: []string{"money"}, TTL: time.Minute, Cost: 1,
		Fetch: func(context.Context, Call) (any, error) { panic("adapter bug") }})
	f := NewFetcher(r, FetcherOptions{})
	_, err := f.Fetch(context.Background(), r.Get("boom.x"), Call{}, "u:1")
	if err == nil || !strings.Contains(err.Error(), "暂时不可用") {
		t.Fatalf("err = %v", err)
	}
}

func TestPlaceFallbacks(t *testing.T) {
	cases := map[string][]string{
		"新安江水库":  {"新安江"},
		"丹江口水库":  {"丹江口"},
		"三峡水利枢纽": {"三峡"},
		"千岛湖":    nil,
		"大水库":    nil, // 去掉后缀只剩 1 个字，不试
		"杭州":     nil,
	}
	for in, want := range cases {
		got := placeFallbacks(in)
		if len(got) != len(want) || (len(want) > 0 && got[0] != want[0]) {
			t.Errorf("placeFallbacks(%q) = %v, want %v", in, got, want)
		}
	}
}
