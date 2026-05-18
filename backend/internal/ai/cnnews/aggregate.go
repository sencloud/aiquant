package cnnews

import (
	"context"
	"sort"
	"strings"
	"sync"
)

// GlobalSearchOptions 是 SearchGlobal 的可选参数。
type GlobalSearchOptions struct {
	// Keyword：title/snippet 子串过滤；空 = 不过滤。
	Keyword string
	// Channel：华尔街见闻 channel，默认 global-channel。可选 forex-channel / oil-channel 等。
	Channel string
	// Limit：合并后返回上限。
	Limit int
	// IncludeArticles：是否同时拉深度文章（默认 true）。
	IncludeArticles bool
}

// SearchGlobal 拉「国际事件 / 全球宏观 / 商品外汇 / 地缘」相关新闻。
//
// 数据源（全部国内可达）：
//   - 华尔街见闻 lives  实时电报，覆盖全球宏观/外汇/原油/商品
//   - 华尔街见闻 articles 深度文章
//   - 财联社电报 cls    与国际宏观相关的子集（按关键字过滤）
//
// GDELT 在阿里云出口稳定 8s 超时，已不再使用。
func (c *Client) SearchGlobal(ctx context.Context, opt GlobalSearchOptions) ([]Event, error) {
	if opt.Limit <= 0 || opt.Limit > 100 {
		opt.Limit = 30
	}
	if opt.Channel == "" {
		opt.Channel = "global-channel"
	}

	type result struct {
		events []Event
		err    error
		src    string
	}
	resCh := make(chan result, 3)
	var wg sync.WaitGroup

	wg.Add(1)
	go func() {
		defer wg.Done()
		ev, err := c.FetchWallstreetcnLives(ctx, opt.Channel, 80)
		resCh <- result{events: ev, err: err, src: "wscn_lives"}
	}()
	if opt.IncludeArticles {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ev, err := c.FetchWallstreetcnArticles(ctx, opt.Channel, 30)
			resCh <- result{events: ev, err: err, src: "wscn_articles"}
		}()
	}
	wg.Add(1)
	go func() {
		defer wg.Done()
		ev, err := c.FetchClsTelegraph(ctx, 50)
		resCh <- result{events: ev, err: err, src: "cls"}
	}()
	go func() { wg.Wait(); close(resCh) }()

	all := make([]Event, 0, 100)
	var lastErr error
	srcOK := 0
	for r := range resCh {
		if r.err != nil {
			lastErr = r.err
			continue
		}
		srcOK++
		all = append(all, r.events...)
	}
	if srcOK == 0 && lastErr != nil {
		return nil, lastErr
	}

	if kw := strings.TrimSpace(opt.Keyword); kw != "" {
		all = filterByKeyword(all, kw)
	}
	sort.Slice(all, func(i, j int) bool {
		return all[i].PublishedAt > all[j].PublishedAt
	})
	all = dedupByTitle(all)
	if len(all) > opt.Limit {
		all = all[:opt.Limit]
	}
	return all, nil
}

// SearchOptions 是 SearchAll 的可选参数。
type SearchOptions struct {
	// Keyword 用于在 title/snippet 中做大小写不敏感的子串过滤。
	// 空字符串表示不过滤，仅返回最新条目。
	Keyword string
	// Channels 限制使用的源（cls/eastmoney/sina）。空 = 全部三源。
	Channels []string
	// Limit 最终返回的条数上限。
	Limit int
}

// SearchAll 并发调三源 → 关键字过滤 → 按 PublishedAt 倒序合并去重。
//
// 任一源失败不阻断整体，但若全部失败，返回最后一个错误。
// 不做静默兜底：如果 keyword 命中数 = 0，会返回空数组 + nil 错误，由调用方
// 透传给 LLM（让模型自己判断是关键字太冷还是源故障）。
func (c *Client) SearchAll(ctx context.Context, opt SearchOptions) ([]Event, error) {
	if opt.Limit <= 0 || opt.Limit > 100 {
		opt.Limit = 30
	}
	chSet := map[string]bool{}
	if len(opt.Channels) == 0 {
		// 默认只用 cls + eastmoney 两个国内可达的主源；sina 在阿里云出口
		// 经常被 anti-bot 403，需要时由调用方显式传 channels=["sina"]。
		chSet = map[string]bool{"cls": true, "eastmoney": true}
	} else {
		for _, ch := range opt.Channels {
			chSet[strings.ToLower(strings.TrimSpace(ch))] = true
		}
	}

	type result struct {
		events []Event
		err    error
		src    string
	}
	resCh := make(chan result, 3)
	var wg sync.WaitGroup

	if chSet["cls"] {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ev, err := c.FetchClsTelegraph(ctx, 50)
			resCh <- result{events: ev, err: err, src: "cls"}
		}()
	}
	if chSet["eastmoney"] {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ev, err := c.FetchEastmoneyKuaixun(ctx, "102", 50)
			resCh <- result{events: ev, err: err, src: "eastmoney"}
		}()
	}
	if chSet["sina"] {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ev, err := c.FetchSinaRoll(ctx, "finance", 30)
			resCh <- result{events: ev, err: err, src: "sina"}
		}()
	}
	go func() { wg.Wait(); close(resCh) }()

	all := make([]Event, 0, 100)
	var lastErr error
	srcOK := 0
	for r := range resCh {
		if r.err != nil {
			lastErr = r.err
			continue
		}
		srcOK++
		all = append(all, r.events...)
	}
	if srcOK == 0 && lastErr != nil {
		return nil, lastErr
	}

	if kw := strings.TrimSpace(opt.Keyword); kw != "" {
		all = filterByKeyword(all, kw)
	}

	sort.Slice(all, func(i, j int) bool {
		return all[i].PublishedAt > all[j].PublishedAt
	})
	all = dedupByTitle(all)
	if len(all) > opt.Limit {
		all = all[:opt.Limit]
	}
	return all, nil
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
