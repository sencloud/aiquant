package miniapp

import (
	"container/list"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"sync"
	"time"
)

// ParamDef 是数据源参数定义。
type ParamDef struct {
	Name     string   `json:"name"`
	Type     string   `json:"type"` // string / number / integer / boolean / array
	Required bool     `json:"required,omitempty"`
	Doc      string   `json:"doc,omitempty"`
	Enum     []string `json:"enum,omitempty"`
	Min      *float64 `json:"min,omitempty"`
	Max      *float64 `json:"max,omitempty"`
	Default  any      `json:"default,omitempty"`
	MaxItems int      `json:"max_items,omitempty"`
}

// Call 是一次数据源调用。UserID=0 表示未登录（公开模板浏览）。
type Call struct {
	UserID int64
	Params map[string]any
}

// Source 是白名单数据源。
type Source struct {
	ID     string     `json:"id"`
	Title  string     `json:"title"`
	Doc    string     `json:"doc"`
	Topics []string   `json:"topics"`
	Params []ParamDef `json:"params"`
	// Output 是输出结构说明（给大模型和客户端开发看；字段由适配器固定）。
	Output string `json:"output"`
	// TTL 是跨用户共享缓存的时长；UserScoped 的源不缓存。
	TTL time.Duration `json:"-"`
	// Cost 是每次实际调用（未命中缓存）消耗的成本单位。
	Cost int `json:"cost"`
	// UserScoped 表示读取当前用户的私有数据（只用登录态 uid，不接受参数里的 uid）。
	UserScoped bool `json:"user_scoped,omitempty"`
	// Fetch 返回 JSON 形态的数据（map / slice / 基本类型）。
	Fetch func(ctx context.Context, c Call) (any, error) `json:"-"`
}

// AllowedIn 判断数据源是否对主题开放。
func (s *Source) AllowedIn(topic string) bool {
	for _, t := range s.Topics {
		if t == topic {
			return true
		}
	}
	return false
}

// Registry 是数据源注册表。
type Registry struct {
	byID map[string]*Source
}

// NewRegistry 构造空注册表。
func NewRegistry() *Registry { return &Registry{byID: map[string]*Source{}} }

// Register 注册；重复 id panic（启动期暴露）。
func (r *Registry) Register(s *Source) {
	if s.ID == "" || s.Fetch == nil {
		panic("miniapp: bad source")
	}
	if _, ok := r.byID[s.ID]; ok {
		panic("miniapp: duplicate source " + s.ID)
	}
	r.byID[s.ID] = s
}

// Get 查数据源。
func (r *Registry) Get(id string) *Source {
	if r == nil {
		return nil
	}
	return r.byID[id]
}

// ForTopic 返回主题可用的数据源（按 id 排序）。
func (r *Registry) ForTopic(topic string) []*Source {
	var out []*Source
	for _, s := range r.byID {
		if s.AllowedIn(topic) {
			out = append(out, s)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}

// CheckParams 校验并规整参数（类型、必填、范围、枚举、默认值）。
func (s *Source) CheckParams(in map[string]any) (map[string]any, error) {
	out := map[string]any{}
	known := map[string]bool{}
	for _, p := range s.Params {
		known[p.Name] = true
		v, ok := in[p.Name]
		if !ok || v == nil {
			if p.Required {
				return nil, fmt.Errorf("缺少参数 %s", p.Name)
			}
			if p.Default != nil {
				out[p.Name] = p.Default
			}
			continue
		}
		cv, err := coerceParam(p, v)
		if err != nil {
			return nil, fmt.Errorf("参数 %s：%v", p.Name, err)
		}
		out[p.Name] = cv
	}
	for k := range in {
		if !known[k] {
			return nil, fmt.Errorf("数据源 %s 没有参数 %s", s.ID, k)
		}
	}
	return out, nil
}

func coerceParam(p ParamDef, v any) (any, error) {
	switch p.Type {
	case "string":
		s, ok := v.(string)
		if !ok {
			if f, isNum := v.(float64); isNum {
				s = fmt.Sprint(f)
			} else {
				return nil, errors.New("应为字符串")
			}
		}
		s = strings.TrimSpace(s)
		if p.Required && s == "" {
			return nil, errors.New("不能为空")
		}
		if len([]rune(s)) > 64 {
			return nil, errors.New("太长")
		}
		if len(p.Enum) > 0 {
			found := false
			for _, e := range p.Enum {
				if e == s {
					found = true
				}
			}
			if !found {
				return nil, fmt.Errorf("只能是 %s", strings.Join(p.Enum, " / "))
			}
		}
		return s, nil
	case "number", "integer":
		f, ok := v.(float64)
		if !ok {
			return nil, errors.New("应为数字")
		}
		if math.IsNaN(f) || math.IsInf(f, 0) {
			return nil, errors.New("不是有效数字")
		}
		if p.Type == "integer" {
			f = math.Round(f)
		}
		if p.Min != nil && f < *p.Min {
			f = *p.Min
		}
		if p.Max != nil && f > *p.Max {
			f = *p.Max
		}
		return f, nil
	case "boolean":
		b, ok := v.(bool)
		if !ok {
			return nil, errors.New("应为 true / false")
		}
		return b, nil
	case "array":
		arr, ok := v.([]any)
		if !ok {
			if s, isStr := v.(string); isStr && s != "" {
				arr = []any{s}
			} else {
				return nil, errors.New("应为数组")
			}
		}
		max := p.MaxItems
		if max <= 0 {
			max = 8
		}
		if len(arr) > max {
			return nil, fmt.Errorf("最多 %d 项", max)
		}
		out := make([]any, 0, len(arr))
		for _, e := range arr {
			s, ok := e.(string)
			if !ok {
				return nil, errors.New("数组元素应为字符串")
			}
			out = append(out, strings.TrimSpace(s))
		}
		return out, nil
	}
	return v, nil
}

func f64(v float64) *float64 { return &v }

// ─── Fetcher：缓存 + 合并并发 + 成本预算 ────────────────────────────────

// ErrBudget 当日数据成本预算用尽。
var ErrBudget = errors.New("今天的数据刷新次数用完了，明天再来")

// FetcherOptions 配置。
type FetcherOptions struct {
	CacheEntries    int           // LRU 容量（条）
	MaxResultBytes  int           // 单个结果上限
	DailyUserBudget int           // 每用户每天成本单位
	DailyAnonBudget int           // 未登录（按 IP 归并）每天成本单位
	CallTimeout     time.Duration // 单次数据源调用超时
	Now             func() time.Time
}

// Fetcher 统一执行数据源调用。
type Fetcher struct {
	reg  *Registry
	opts FetcherOptions

	mu        sync.Mutex
	lru       *list.List
	cache     map[string]*list.Element
	inflight  map[string]*flight
	budget    map[string]int // key=day|who
	budgetDay string
}

type cacheEntry struct {
	key     string
	val     any
	expires time.Time
}

type flight struct {
	done chan struct{}
	val  any
	err  error
}

// NewFetcher 构造。
func NewFetcher(reg *Registry, o FetcherOptions) *Fetcher {
	if o.CacheEntries <= 0 {
		o.CacheEntries = 2000
	}
	if o.MaxResultBytes <= 0 {
		o.MaxResultBytes = 256 << 10
	}
	if o.DailyUserBudget <= 0 {
		o.DailyUserBudget = 2000
	}
	if o.DailyAnonBudget <= 0 {
		o.DailyAnonBudget = 300
	}
	if o.CallTimeout <= 0 {
		o.CallTimeout = 15 * time.Second
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	return &Fetcher{reg: reg, opts: o, lru: list.New(), cache: map[string]*list.Element{},
		inflight: map[string]*flight{}, budget: map[string]int{}}
}

// Registry 返回注册表。
func (f *Fetcher) Registry() *Registry { return f.reg }

// FetchResult 是一次调用的结果。
type FetchResult struct {
	Value  any
	Cached bool
	Cost   int
	Took   time.Duration
}

// Fetch 调用数据源。who 是预算归属（"u:<id>" 或 "ip:<addr>"）。
func (f *Fetcher) Fetch(ctx context.Context, src *Source, call Call, who string) (*FetchResult, error) {
	params, err := src.CheckParams(call.Params)
	if err != nil {
		return nil, err
	}
	call.Params = params
	start := f.opts.Now()
	if src.UserScoped {
		if call.UserID <= 0 {
			// 未登录浏览模板：私有数据源返回空结构，不报错。
			return &FetchResult{Value: emptyFor(src)}, nil
		}
		v, err := f.do(ctx, src, call)
		if err != nil {
			return nil, err
		}
		return &FetchResult{Value: v, Took: f.opts.Now().Sub(start)}, nil
	}
	pb, _ := json.Marshal(params) // map 键已排序：json.Marshal 对 map 按键排序
	key := src.ID + "|" + string(pb)

	f.mu.Lock()
	if el, ok := f.cache[key]; ok {
		ce := el.Value.(*cacheEntry)
		if f.opts.Now().Before(ce.expires) {
			f.lru.MoveToFront(el)
			f.mu.Unlock()
			return &FetchResult{Value: ce.val, Cached: true}, nil
		}
	}
	if fl, ok := f.inflight[key]; ok {
		f.mu.Unlock()
		select {
		case <-fl.done:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
		if fl.err != nil {
			return nil, fl.err
		}
		return &FetchResult{Value: fl.val, Cached: true}, nil
	}
	if !f.spendLocked(who, src.Cost) {
		f.mu.Unlock()
		return nil, ErrBudget
	}
	fl := &flight{done: make(chan struct{})}
	f.inflight[key] = fl
	f.mu.Unlock()

	v, err := f.do(ctx, src, call)

	f.mu.Lock()
	delete(f.inflight, key)
	fl.val, fl.err = v, err
	close(fl.done)
	if err == nil && src.TTL > 0 {
		f.putLocked(key, v, src.TTL)
	}
	f.mu.Unlock()
	if err != nil {
		return nil, err
	}
	return &FetchResult{Value: v, Cost: src.Cost, Took: f.opts.Now().Sub(start)}, nil
}

func (f *Fetcher) do(ctx context.Context, src *Source, call Call) (out any, err error) {
	cctx, cancel := context.WithTimeout(ctx, f.opts.CallTimeout)
	defer cancel()
	// 适配器 panic 不能带崩整个进程：转成该绑定的错误。
	defer func() {
		if p := recover(); p != nil {
			out, err = nil, fmt.Errorf("数据源 %s 暂时不可用", src.ID)
		}
	}()
	v, err := src.Fetch(cctx, call)
	if err != nil {
		return nil, err
	}
	b, err := json.Marshal(v)
	if err != nil {
		return nil, fmt.Errorf("数据源 %s 输出无法序列化", src.ID)
	}
	if len(b) > f.opts.MaxResultBytes {
		return nil, fmt.Errorf("数据源 %s 返回的数据太大", src.ID)
	}
	if err := json.Unmarshal(b, &out); err != nil {
		return nil, err
	}
	return out, nil
}

func (f *Fetcher) putLocked(key string, v any, ttl time.Duration) {
	if el, ok := f.cache[key]; ok {
		f.lru.Remove(el)
		delete(f.cache, key)
	}
	el := f.lru.PushFront(&cacheEntry{key: key, val: v, expires: f.opts.Now().Add(ttl)})
	f.cache[key] = el
	for f.lru.Len() > f.opts.CacheEntries {
		old := f.lru.Back()
		f.lru.Remove(old)
		delete(f.cache, old.Value.(*cacheEntry).key)
	}
}

func (f *Fetcher) spendLocked(who string, cost int) bool {
	day := f.opts.Now().In(shanghai).Format("2006-01-02")
	if day != f.budgetDay {
		f.budget = map[string]int{}
		f.budgetDay = day
	}
	limit := f.opts.DailyUserBudget
	if strings.HasPrefix(who, "ip:") {
		limit = f.opts.DailyAnonBudget
	}
	if f.budget[who]+cost > limit {
		return false
	}
	f.budget[who] += cost
	return true
}

// Spent 返回今天已用成本（测试 / 观测用）。
func (f *Fetcher) Spent(who string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.budget[who]
}

var shanghai = time.FixedZone("CST", 8*3600)

func emptyFor(src *Source) any {
	switch src.ID {
	case "fishing.catch_stats":
		return map[string]any{"trips": 0, "fish": 0, "species": 0, "released": 0}
	}
	return map[string]any{"items": []any{}}
}
