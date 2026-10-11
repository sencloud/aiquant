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
