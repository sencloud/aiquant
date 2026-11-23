package websearch

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestSearchUsesDeepSeekContract(t *testing.T) {
	tests := []struct {
		name     string
		basePath string
	}{
		{name: "host only"},
		{name: "already versioned", basePath: "/v1"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var calls atomic.Int32
			server := httptest.NewServer(http.HandlerFunc(
				func(w http.ResponseWriter, r *http.Request) {
					calls.Add(1)
					if r.Method != http.MethodPost {
						t.Errorf("method = %s", r.Method)
					}
					if r.URL.Path != "/v1/tools/search" {
						t.Errorf("path = %s", r.URL.Path)
					}
					if got := r.Header.Get("Authorization"); got != "Bearer test-key" {
						t.Errorf("authorization = %q", got)
					}
					var body struct {
						Query        string `json:"query"`
						Count        int    `json:"count"`
						Original     string `json:"ori_question"`
						Localization string `json:"localization"`
					}
					if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
						t.Errorf("decode request: %v", err)
					}
					if body.Query != "周末政策" || body.Count != 7 ||
						body.Original != "周末有什么政策" || body.Localization != "zh-CN" {
						t.Errorf("request body = %+v", body)
					}
					w.Header().Set("Content-Type", "application/json")
					_, _ = w.Write([]byte(`{"results":[{"title":"政策发布",` +
						`"url":"https://example.com/policy","site_name":"证监会",` +
						`"date":"2026-11-22","snippet":"摘要"}]}`))
				}))
			defer server.Close()

			client := New("test-key", server.URL+tt.basePath, time.Second)
			results, err := client.Search(context.Background(), Query{
				Query:    "周末政策",
				Original: "周末有什么政策",
				Count:    7,
				Localize: "zh-CN",
			})
			if err != nil {
				t.Fatalf("Search: %v", err)
			}
			if calls.Load() != 1 {
				t.Fatalf("calls = %d", calls.Load())
			}
			if len(results) != 1 || results[0].SiteName != "证监会" ||
				results[0].URL != "https://example.com/policy" {
				t.Fatalf("results = %+v", results)
			}
		})
	}
}

func TestSearchReturnsEmptyResults(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, _ *http.Request) {
			_, _ = w.Write([]byte(`{"results":[]}`))
		}))
	defer server.Close()

	client := New("test-key", server.URL, time.Second)
	results, err := client.Search(context.Background(), Query{Query: "无结果"})
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(results) != 0 {
		t.Fatalf("results = %+v", results)
	}
}

func TestSearchDoesNotRetryClientErrors(t *testing.T) {
	for _, status := range []int{http.StatusUnauthorized, http.StatusPaymentRequired} {
		t.Run(http.StatusText(status), func(t *testing.T) {
			var calls atomic.Int32
			server := httptest.NewServer(http.HandlerFunc(
				func(w http.ResponseWriter, _ *http.Request) {
					calls.Add(1)
					w.WriteHeader(status)
					_, _ = w.Write([]byte(`{"message":"denied"}`))
				}))
			defer server.Close()

			client := New("test-key", server.URL, time.Second)
			client.retryBase = time.Millisecond
			_, err := client.Search(context.Background(), Query{Query: "测试"})
			if err == nil {
				t.Fatal("expected error")
			}
			if calls.Load() != 1 {
				t.Fatalf("calls = %d, want 1", calls.Load())
			}
			if status == http.StatusUnauthorized && !strings.Contains(err.Error(), "鉴权") {
				t.Fatalf("error = %v", err)
			}
			if status == http.StatusPaymentRequired && !strings.Contains(err.Error(), "额度") {
				t.Fatalf("error = %v", err)
			}
		})
	}
}

func TestSearchRetriesTransientErrors(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, _ *http.Request) {
			n := calls.Add(1)
			switch n {
			case 1:
				w.WriteHeader(http.StatusTooManyRequests)
			case 2:
				w.WriteHeader(http.StatusBadGateway)
			default:
				_, _ = w.Write([]byte(`{"results":[{"title":"ok",` +
					`"url":"https://example.com/ok"}]}`))
			}
		}))
	defer server.Close()

	client := New("test-key", server.URL, time.Second)
	client.retryBase = time.Millisecond
	results, err := client.Search(context.Background(), Query{Query: "测试"})
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if calls.Load() != 3 || len(results) != 1 || results[0].Title != "ok" {
		t.Fatalf("calls = %d, results = %+v", calls.Load(), results)
	}
}

func TestSearchRequiresAPIKey(t *testing.T) {
	client := New("", "", time.Second)
	if client.Configured() {
		t.Fatal("empty client should be unconfigured")
	}
	_, err := client.Search(context.Background(), Query{Query: "测试"})
	if err == nil || !strings.Contains(err.Error(), "未配置") {
		t.Fatalf("error = %v", err)
	}
}
