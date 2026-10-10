package cnnews

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func newFakeClient(t *testing.T) (*Client, *httptest.Server) {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/wscn_search", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query().Get("query")
		if q != "厄尔尼诺" {
			_, _ = w.Write([]byte(`{"code":20000,"data":{"items":[]}}`))
			return
		}
		_, _ = w.Write([]byte(`{"code":20000,"data":{"items":[
			{"title":"<em>厄尔尼诺</em>推升橡胶价格","content":"联合国机构警告厄尔尼诺将加剧","display_time":1791628450,"uri":"https://wallstreetcn.com/articles/1?keyword=x"},
			{"title":"重复标题","content":"x","display_time":1791500000,"uri":"https://wallstreetcn.com/articles/2"}]}}`))
	})
	mux.HandleFunc("/ths", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"code":"200","data":{"list":[
			{"title":"棕榈油期货大涨","digest":"马来西亚产量下滑","url":"https://ths/1","ctime":"1791638330","tag":"期货"},
			{"title":"重复标题","digest":"y","url":"https://ths/2","ctime":"1791600000"},
			{"title":"无关新闻","digest":"z","url":"https://ths/3","ctime":"1791600000"}]}}`))
	})
	mux.HandleFunc("/rss", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`<?xml version="1.0" encoding="utf-8"?><rss version="2.0"><channel><title>t</title>
<item><title>厄尔尼诺影响东南亚降水</title><link>https://rss/1</link><description>描述</description><pubDate>Sat, 10 Oct 2026 21:30:34 +0800</pubDate></item>
<item><title>别的</title><link>https://rss/2</link><description>d</description><pubDate>Sat, 10 Oct 2026 20:00:00 +0800</pubDate></item>
</channel></rss>`))
	})
	mux.HandleFunc("/broken", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusForbidden)
	})
	mux.HandleFunc("/slow", func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-time.After(3 * time.Second):
		case <-r.Context().Done():
		}
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	c := New(10)
	c.SourceTimeout = 500 * time.Millisecond
	c.Overrides = map[string]string{
		"wallstreetcn_search": srv.URL + "/wscn_search",
		"ths_724":             srv.URL + "/ths",
		"chinanews_finance":   srv.URL + "/rss",
		"people_finance":      srv.URL + "/broken",
		"caixin_scroll":       srv.URL + "/slow",
	}
	return c, srv
}

func TestSearchAllParallelFilterDedupAndStatus(t *testing.T) {
	c, _ := newFakeClient(t)
	start := time.Now()
	res := c.SearchAllResult(context.Background(), SearchOptions{
		Keyword:  "厄尔尼诺 棕榈油",
		Channels: []string{"wallstreetcn_search", "ths_724", "chinanews_finance", "people_finance", "caixin"},
		Limit:    20,
	})
	if el := time.Since(start); el > 2*time.Second {
		t.Fatalf("sources not parallel / per-source timeout not applied: %v", el)
	}
	byName := map[string]SourceStatus{}
	for _, s := range res.Sources {
		byName[s.Name] = s
	}
	if !byName["wallstreetcn_search"].OK || !byName["ths_724"].OK || !byName["chinanews_finance"].OK {
		t.Fatalf("expected ok sources: %+v", res.Sources)
	}
	if byName["people_finance"].OK || !strings.Contains(byName["people_finance"].Error, "403") {
		t.Fatalf("people should fail with 403: %+v", byName["people_finance"])
	}
	if byName["caixin"].OK {
		t.Fatalf("slow caixin should time out: %+v", byName["caixin"])
	}
	titles := map[string]int{}
	for _, e := range res.Events {
		titles[e.Title]++
	}
	// 搜索型源的结果（去掉 <em>）直接采用；滚动源按关键词过滤；跨源同标题去重。
	for _, want := range []string{"厄尔尼诺推升橡胶价格", "棕榈油期货大涨", "厄尔尼诺影响东南亚降水"} {
		if titles[want] != 1 {
			t.Errorf("missing %q in %v", want, titles)
		}
	}
	if titles["无关新闻"] != 0 || titles["别的"] != 0 {
		t.Errorf("feed items should be keyword-filtered: %v", titles)
	}
	if titles["重复标题"] > 1 {
		t.Errorf("dedupe failed: %v", titles)
	}
	for i := 1; i < len(res.Events); i++ {
		if res.Events[i-1].PublishedAt < res.Events[i].PublishedAt {
			t.Fatalf("not sorted by time desc")
		}
	}
	if res.err() != nil {
		t.Fatalf("partial failure must not be an error: %v", res.err())
	}
}

func TestSearchAllAllFailedIsError(t *testing.T) {
	c, _ := newFakeClient(t)
	_, err := c.SearchAll(context.Background(), SearchOptions{
		Keyword: "x", Channels: []string{"people_finance", "caixin"},
	})
	if err == nil {
		t.Fatal("want error when every source fails")
	}
}

func TestSearchSourcesSkippedWithoutKeyword(t *testing.T) {
	c, _ := newFakeClient(t)
	res := c.SearchAllResult(context.Background(), SearchOptions{
		Channels: []string{"wallstreetcn_search", "ths_724"},
	})
	if len(res.Sources) != 1 || res.Sources[0].Name != "ths_724" || len(res.Events) != 3 {
		t.Fatalf("unexpected: %+v events=%d", res.Sources, len(res.Events))
	}
}
