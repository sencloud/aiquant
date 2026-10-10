package cnnews

import (
	"context"
	"errors"
	"sort"
	"strings"
	"sync"
	"time"
)

// GlobalSearchOptions 是 SearchGlobal 的可选参数。
type GlobalSearchOptions struct {
	// Keyword：关键词（空格/逗号分隔做 OR）；空 = 不过滤。
	Keyword string
	// Channel：华尔街见闻 channel，默认 global-channel。可选 forex-channel / oil-channel 等。
	Channel string
	// Limit：合并后返回上限。
	Limit int
	// IncludeArticles：是否同时拉华尔街见闻深度文章（默认 true）。
	IncludeArticles bool
}

// SearchOptions 是 SearchAll 的可选参数。
type SearchOptions struct {
	// Keyword 用于在 title/snippet 中做大小写不敏感的子串过滤（OR），
	// 同时作为搜索型源的查询词。空字符串表示只取最新条目。
	Keyword string
	// Channels 限制使用的源（源名见 SourceNames）。空 = 默认组合。
	Channels []string
	// Limit 最终返回的条数上限。
	Limit int
}

// SourceStatus 是一次聚合里单个源的结果，透传给 LLM 和日志，
// 让「0 条」能区分成「源挂了」还是「真的没有」。
type SourceStatus struct {
	Name  string `json:"name"`
	OK    bool   `json:"ok"`
	Count int    `json:"count"`
	Error string `json:"error,omitempty"`
	Ms    int64  `json:"ms"`
}

// Result 是带源状态的聚合结果。
type Result struct {
	Events  []Event
	Sources []SourceStatus
}

// OKSources 返回成功的源名列表。
func (r *Result) OKSources() []string {
	out := []string{}
	for _, s := range r.Sources {
		if s.OK {
			out = append(out, s.Name)
		}
	}
	return out
}

// FailedSources 返回失败的源名列表。
func (r *Result) FailedSources() []string {
	out := []string{}
	for _, s := range r.Sources {
		if !s.OK {
			out = append(out, s.Name)
		}
	}
	return out
}

// source 是聚合器里的一个源。search=true 表示它按关键词在服务端搜索，
// 返回结果已经相关，不再做本地子串过滤。
type source struct {
	name   string
	search bool
	fetch  func(ctx context.Context, kw string) ([]Event, error)
}

// 默认组合（全部在阿里云出口实测可达）。
var (
	defaultCNSources     = []string{"wallstreetcn_search", "jin10", "eastmoney", "ths_724", "sina_7x24", "caixin", "chinanews_finance", "people_finance"}
	defaultGlobalSources = []string{"wallstreetcn_search", "wscn_lives", "wscn_articles", "jin10", "ths_724", "caixin", "un_news_zh", "cnbc", "marketwatch"}
)

// SourceNames 列出所有可用源名。
func SourceNames() []string {
	return []string{"wallstreetcn_search", "jin10", "eastmoney", "ths_724", "sina_7x24", "caixin",
		"chinanews_finance", "people_finance", "wscn_lives", "wscn_articles", "cnbc", "marketwatch", "un_news_zh", "cls", "sina"}
}

func (c *Client) sourceByName(name, channel string) (source, bool) {
	switch name {
	case "wallstreetcn_search":
		return source{name, true, func(ctx context.Context, kw string) ([]Event, error) {
			return c.searchTokens(ctx, kw, c.FetchWallstreetcnSearch)
		}}, true
	case "jin10":
		return source{name, false, func(ctx context.Context, _ string) ([]Event, error) { return c.FetchJin10Flash(ctx, 100) }}, true
	case "eastmoney":
		return source{name, false, func(ctx context.Context, _ string) ([]Event, error) { return c.FetchEastmoneyKuaixun(ctx, "102", 100) }}, true
	case "ths_724":
		return source{name, false, func(ctx context.Context, _ string) ([]Event, error) { return c.FetchTHS724(ctx, 100) }}, true
	case "sina_7x24":
		return source{name, false, func(ctx context.Context, _ string) ([]Event, error) { return c.FetchSina7x24(ctx, 100) }}, true
	case "caixin":
		return source{name, false, func(ctx context.Context, _ string) ([]Event, error) { return c.FetchCaixinScroll(ctx, 0) }}, true
	case "chinanews_finance", "people_finance", "cnbc", "marketwatch", "un_news_zh":
		return source{name, false, func(ctx context.Context, _ string) ([]Event, error) { return c.FetchRSS(ctx, name, 100) }}, true
	case "wscn_lives":
		return source{name, false, func(ctx context.Context, _ string) ([]Event, error) {
			return c.FetchWallstreetcnLives(ctx, channel, 80)
		}}, true
	case "wscn_articles":
		return source{name, false, func(ctx context.Context, _ string) ([]Event, error) {
			return c.FetchWallstreetcnArticles(ctx, channel, 30)
		}}, true
	case "cls":
		return source{name, false, func(ctx context.Context, _ string) ([]Event, error) { return c.FetchClsTelegraph(ctx, 50) }}, true
	case "sina":
		return source{name, false, func(ctx context.Context, _ string) ([]Event, error) { return c.FetchSinaRoll(ctx, "finance", 30) }}, true
	}
	return source{}, false
}

// searchTokens：搜索 API 对多词是 AND 语义，而工具约定是 OR，
// 所以按词拆开（最多 3 个）并发搜，再合并。
func (c *Client) searchTokens(ctx context.Context, kw string, fn func(context.Context, string, int) ([]Event, error)) ([]Event, error) {
	tokens := splitKeyword(kw)
	if len(tokens) == 0 {
		return nil, nil
	}
	if len(tokens) > 3 {
		tokens = tokens[:3]
	}
	type res struct {
		ev  []Event
		err error
	}
	ch := make(chan res, len(tokens))
	for _, t := range tokens {
		go func(t string) {
			ev, err := fn(ctx, t, 15)
			ch <- res{ev, err}
		}(t)
	}
	var all []Event
	var lastErr error
	ok := 0
	for range tokens {
		r := <-ch
		if r.err != nil {
			lastErr = r.err
			continue
		}
		ok++
		all = append(all, r.ev...)
	}
	if ok == 0 {
		return nil, lastErr
	}
	return all, nil
}

// run 并发跑一组源：每个源有自己的超时，失败只记状态不阻断；
// 滚动型源按关键词过滤，搜索型源直接采用；最后按时间倒序去重截断。
func (c *Client) run(ctx context.Context, srcs []source, kw string, limit int) *Result {
	timeout := c.SourceTimeout
	if timeout <= 0 {
		timeout = 8 * time.Second
	}
	kw = strings.TrimSpace(kw)
	type item struct {
		idx    int
		events []Event
		status SourceStatus
	}
	ch := make(chan item, len(srcs))
	var wg sync.WaitGroup
	for i, s := range srcs {
		if s.search && kw == "" {
			continue // 没有关键词时搜索型源没有意义
		}
		wg.Add(1)
		go func(i int, s source) {
			defer wg.Done()
			sctx, cancel := context.WithTimeout(ctx, timeout)
			defer cancel()
			start := time.Now()
			ev, err := s.fetch(sctx, kw)
			st := SourceStatus{Name: s.name, Ms: time.Since(start).Milliseconds()}
			if err != nil {
				st.Error = truncateRunes(err.Error(), 160)
			} else {
				st.OK = true
				if !s.search && kw != "" {
					ev = filterByKeyword(ev, kw)
				}
				st.Count = len(ev)
			}
			ch <- item{idx: i, events: ev, status: st}
		}(i, s)
	}
	go func() { wg.Wait(); close(ch) }()

	got := make([]item, 0, len(srcs))
	for it := range ch {
		got = append(got, it)
	}
	sort.Slice(got, func(a, b int) bool { return got[a].idx < got[b].idx })

	res := &Result{}
	var all []Event
	for _, it := range got {
		res.Sources = append(res.Sources, it.status)
		if it.status.OK {
			all = append(all, it.events...)
		} else if c.logger != nil {
			c.logger.Warn().Str("source", it.status.Name).Str("err", it.status.Error).
				Int64("ms", it.status.Ms).Msg("cnnews: source failed")
		}
	}
	sort.SliceStable(all, func(i, j int) bool { return all[i].PublishedAt > all[j].PublishedAt })
	all = dedupByTitle(all)
	if limit > 0 && len(all) > limit {
		all = all[:limit]
	}
	res.Events = all
	if c.logger != nil {
		c.logger.Debug().Str("kw", kw).Int("events", len(all)).
			Strs("ok", res.OKSources()).Strs("failed", res.FailedSources()).Msg("cnnews: aggregate")
	}
	return res
}

func (c *Client) buildSources(names []string, channel string) []source {
	seen := map[string]bool{}
	out := make([]source, 0, len(names))
	for _, n := range names {
		n = strings.ToLower(strings.TrimSpace(n))
		if seen[n] {
			continue
		}
		seen[n] = true
		if s, ok := c.sourceByName(n, channel); ok {
			out = append(out, s)
		}
	}
	return out
}

// SearchGlobalResult 拉「国际事件 / 全球宏观 / 商品外汇 / 地缘」相关新闻，带源状态。
//
// 搜索型（华尔街见闻文章搜索）负责召回，滚动型（华尔街见闻电报、金十、
// 同花顺、财新、联合国新闻中文、CNBC、MarketWatch）负责最新动态。
// GDELT / Google News 在阿里云出口不可达，不再使用。
func (c *Client) SearchGlobalResult(ctx context.Context, opt GlobalSearchOptions) *Result {
	if opt.Limit <= 0 || opt.Limit > 100 {
		opt.Limit = 30
	}
	if opt.Channel == "" {
		opt.Channel = "global-channel"
	}
	names := defaultGlobalSources
	if !opt.IncludeArticles {
		names = make([]string, 0, len(defaultGlobalSources))
		for _, n := range defaultGlobalSources {
			if n != "wscn_articles" {
				names = append(names, n)
			}
		}
	}
	return c.run(ctx, c.buildSources(names, opt.Channel), opt.Keyword, opt.Limit)
}

// SearchGlobal 是 SearchGlobalResult 的兼容封装：全部源失败时返回错误。
func (c *Client) SearchGlobal(ctx context.Context, opt GlobalSearchOptions) ([]Event, error) {
	r := c.SearchGlobalResult(ctx, opt)
	return r.Events, r.err()
}

// SearchAllResult 是国内中文新闻聚合，带源状态。
//
// 不做静默兜底：关键词命中 0 条时返回空 + 各源状态，由调用方透传给 LLM
// （让模型能区分是关键词太冷还是源故障）。
func (c *Client) SearchAllResult(ctx context.Context, opt SearchOptions) *Result {
	if opt.Limit <= 0 || opt.Limit > 100 {
		opt.Limit = 30
	}
	names := opt.Channels
	if len(names) == 0 {
		names = defaultCNSources
	}
	return c.run(ctx, c.buildSources(names, "global-channel"), opt.Keyword, opt.Limit)
}

// SearchAll 是 SearchAllResult 的兼容封装：全部源失败时返回错误。
func (c *Client) SearchAll(ctx context.Context, opt SearchOptions) ([]Event, error) {
	r := c.SearchAllResult(ctx, opt)
	return r.Events, r.err()
}

func (r *Result) err() error {
	if len(r.Sources) == 0 {
		return nil
	}
	var last string
	for _, s := range r.Sources {
		if s.OK {
			return nil
		}
		last = s.Name + ": " + s.Error
	}
	return errors.New("all news sources failed; last: " + last)
}

// filterByKeyword 按空格 / 中文逗号 / 顿号拆词，任一词命中即保留（OR）。
//
// 这样 "有色金属 锂电" 这种"或"语义就能直接 work，避免 LLM 还要拆词。
func filterByKeyword(events []Event, kw string) []Event {
	tokens := splitKeyword(kw)
	if len(tokens) == 0 {
		return events
	}
	out := make([]Event, 0, len(events))
	for _, ev := range events {
		hay := strings.ToLower(ev.Title + " " + ev.Snippet)
		for _, t := range tokens {
			if t != "" && strings.Contains(hay, t) {
				out = append(out, ev)
				break
			}
		}
	}
	return out
}

func splitKeyword(s string) []string {
	repl := strings.NewReplacer("，", " ", "、", " ", ",", " ", "/", " ", "|", " ")
	s = repl.Replace(s)
	parts := strings.Fields(s)
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.ToLower(strings.TrimSpace(p))
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func dedupByTitle(events []Event) []Event {
	seen := map[string]bool{}
	out := make([]Event, 0, len(events))
	for _, ev := range events {
		k := normalizeTitle(ev.Title)
		if k == "" || seen[k] {
			continue
		}
		seen[k] = true
		out = append(out, ev)
	}
	return out
}

func normalizeTitle(s string) string {
	s = strings.TrimSpace(s)
	s = strings.ReplaceAll(s, " ", "")
	return strings.ToLower(s)
}

// stripHTML 去掉简易 HTML 标签（够用于电报里的 <p>/<a>）。
func stripHTML(s string) string {
	var b strings.Builder
	in := false
	for _, r := range s {
		switch r {
		case '<':
			in = true
		case '>':
			in = false
		default:
			if !in {
				b.WriteRune(r)
			}
		}
	}
	return b.String()
}
