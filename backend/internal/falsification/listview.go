package falsification

import (
	"sort"
	"strings"
)

// 列表收窄：通讯录式的档案列表只放「值得一行一行看」的条目。
//
// alpha-radar 每次导出约 2000 条，其中绝大多数是同一批策略在不同品种 / 周期上
// 的自动淘汰（同一个结论重复几百遍）。把它们全部塞进通讯录既没法看，也让
// 3 MB 的 JSON 走 1 Mbps 出口要 20 多秒，旧客户端 3 秒超时后只能回落内置数据。
//
// 规则（ListView）：
//   - 精选（curated）、可交易、仍在验证、研究发现，以及任何未知结论：全部保留；
//   - 自动淘汰（reject）：按 strategy_key 分组，每个策略最多留 RejectsPerStrategy
//     条「代表」，全部策略合计不超过 MaxRejects 条；
//   - 样本不足（insufficient，仅 include=insufficient 时）：同样按策略取代表，
//     每个策略 1 条，计入同一个总上限。
//
// 「代表」怎么选（rankTail）：先保证不同的失败闸门各有一条（死在不同关的样本
// 比同一关的十个品种更有信息量），闸门之间按「走得越远越靠前」排；同一道闸门
// 内按「离通过最近」排：正年占比 → 收益回撤比 → PF → 笔数，最后按 id 保证稳定。
// 总上限按轮次在策略之间轮流分配，不会被某一个条目最多的策略吃光。
//
// 没进列表的条目没有丢：解锁 / 详情按 id 在完整快照里查，搜索接口
// （Search）搜的也是完整快照。

// ListOptions 控制列表收窄。零值取默认。
type ListOptions struct {
	// RejectsPerStrategy 每个策略最多保留几条自动淘汰。默认 3；<0 视为 0。
	RejectsPerStrategy int
	// MaxRejects 自动淘汰 + 样本不足代表的总上限。默认 200。
	MaxRejects int
}

const (
	defaultRejectsPerStrategy = 3
	defaultMaxRejects         = 200
	insufficientPerStrategy   = 1
)

func (o ListOptions) normalized() ListOptions {
	if o.RejectsPerStrategy == 0 {
		o.RejectsPerStrategy = defaultRejectsPerStrategy
	}
	if o.RejectsPerStrategy < 0 {
		o.RejectsPerStrategy = 0
	}
	if o.MaxRejects <= 0 {
		o.MaxRejects = defaultMaxRejects
	}
	return o
}

// ListMeta 描述这次列表收窄的结果（响应里的 list 字段）。
type ListMeta struct {
	Mode               string         `json:"mode"`     // representative
	Total              int            `json:"total"`    // 收窄前可展示的条数
	Returned           int            `json:"returned"` // 本次返回条数
	Omitted            map[string]int `json:"omitted"`  // 按结论统计没放进列表的条数
	RejectsPerStrategy int            `json:"rejects_per_strategy"`
	MaxRejects         int            `json:"max_rejects"`
	Searchable         bool           `json:"searchable"` // 没列出的可以用搜索接口查到
}

// 闸门顺序：越靠后说明策略走得越远，淘汰样本越有信息量。
var gateRank = map[string]int{"sample": 0, "scale": 1, "yearly": 2, "drawdown": 3, "robust": 4}

// isTail 是否属于「长尾」：非精选的自动淘汰 / 样本不足。
func isTail(e map[string]any) bool {
	if c, _ := e["curated"].(bool); c {
		return false
	}
	v := str(e["verdict"])
	return v == VerdictReject || v == VerdictInsufficient
}

func groupKey(e map[string]any) string {
	if k := StrategyKey(e); k != "" {
		return k
	}
	if s := str(e["strategy"]); s != "" {
		return "name:" + s
	}
	return "id:" + str(e["id"])
}

func num(v any) (float64, bool) {
	switch t := v.(type) {
	case float64:
		return t, true
	case int:
		return float64(t), true
	case int64:
		return float64(t), true
	}
	return 0, false
}

// closeness 返回「离通过有多近」的排序键（越大越近）。
func closeness(e map[string]any) [5]float64 {
	m, _ := e["metrics"].(map[string]any)
	rank := -1.0
	if r, ok := gateRank[str(e["failed_gate"])]; ok {
		rank = float64(r)
	}
	ratio := -1.0
	if y, ok := num(m["years"]); ok && y > 0 {
		py, _ := num(m["positive_years"])
		ratio = py / y
	}
	pnlDD, ok := num(m["pnl_dd"])
	if !ok {
		pnlDD = -1e9
	}
	pf, ok := num(m["pf"])
	if !ok || pf > 1e6 {
		pf = -1e9
	}
	trades, _ := num(m["trades"])
	return [5]float64{rank, ratio, pnlDD, pf, trades}
}

func lessCloser(a, b map[string]any) bool {
	ka, kb := closeness(a), closeness(b)
	for i := range ka {
		if ka[i] != kb[i] {
			return ka[i] > kb[i]
		}
	}
	return str(a["id"]) < str(b["id"])
}

// rankTail 给一个策略的长尾条目排出代表顺序：先每道失败闸门各取最近的一条
// （闸门走得远的在前），再按 closeness 补齐。
func rankTail(es []map[string]any) []map[string]any {
	sorted := append([]map[string]any(nil), es...)
	sort.SliceStable(sorted, func(i, j int) bool { return lessCloser(sorted[i], sorted[j]) })
	out := make([]map[string]any, 0, len(sorted))
	seenGate := map[string]bool{}
	used := make([]bool, len(sorted))
	for i, e := range sorted {
		g := str(e["failed_gate"])
		if !seenGate[g] {
			seenGate[g] = true
			out = append(out, e)
			used[i] = true
		}
	}
	for i, e := range sorted {
		if !used[i] {
			out = append(out, e)
		}
	}
	return out
}

// SelectList 从可展示的条目里挑出列表要放的那些，保持原有顺序。
func SelectList(arch []map[string]any, opt ListOptions) ([]map[string]any, ListMeta) {
	opt = opt.normalized()
	meta := ListMeta{
		Mode: "representative", Total: len(arch), Omitted: map[string]int{},
		RejectsPerStrategy: opt.RejectsPerStrategy, MaxRejects: opt.MaxRejects, Searchable: true,
	}
	type group struct {
		verdict string
		key     string
		items   []map[string]any
	}
	groups := map[string]*group{}
	var order []string
	for _, e := range arch {
		if !isTail(e) {
			continue
		}
		v := str(e["verdict"])
		gk := v + "\x00" + groupKey(e)
		g, ok := groups[gk]
		if !ok {
			g = &group{verdict: v, key: groupKey(e)}
			groups[gk] = g
			order = append(order, gk)
		}
		g.items = append(g.items, e)
	}
	sort.Strings(order)
	ranked := make([][]map[string]any, len(order))
	for i, gk := range order {
		g := groups[gk]
		limit := opt.RejectsPerStrategy
		if g.verdict == VerdictInsufficient {
			limit = insufficientPerStrategy
		}
		r := rankTail(g.items)
		if len(r) > limit {
			r = r[:limit]
		}
		ranked[i] = r
	}
	// 轮流取：第 1 轮每个策略的头号代表，第 2 轮第二号……直到总上限。
	picked := map[string]bool{} // by id
	count := 0
	for round := 0; count < opt.MaxRejects; round++ {
		progressed := false
		for _, r := range ranked {
			if round < len(r) && count < opt.MaxRejects {
				picked[str(r[round]["id"])] = true
				count++
				progressed = true
			}
		}
		if !progressed {
			break
		}
	}
	out := make([]map[string]any, 0, len(arch)-countTail(arch)+count)
	for _, e := range arch {
		if isTail(e) && !picked[str(e["id"])] {
			meta.Omitted[str(e["verdict"])]++
			continue
		}
		out = append(out, e)
	}
	meta.Returned = len(out)
	return out, meta
}

func countTail(arch []map[string]any) int {
	n := 0
	for _, e := range arch {
		if isTail(e) {
			n++
		}
	}
	return n
}

// listDropFields 是列表 / 搜索里不需要的字段：客户端界面不展示，详情接口仍然返回。
var listDropFields = []string{"window", "judged_at", "license", "license_status", "asset_class", "few"}

// SlimEntry 返回列表用的精简条目（新 map，不修改入参）：去掉 listDropFields 和
// 值为 null 的字段，闸门结果里的 null 也去掉。免费层要用的结论、关键数字、
// 闸门结果、失败闸门、来源等全部保留，旧客户端的详情页照常能画出来。
func SlimEntry(e map[string]any) map[string]any {
	c := make(map[string]any, len(e))
	for k, v := range e {
		if v == nil {
			continue
		}
		c[k] = v
	}
	for _, f := range listDropFields {
		delete(c, f)
	}
	if g, ok := c["gates"].(map[string]any); ok {
		c["gates"] = dropNilsDeep(g)
	}
	if m, ok := c["metrics"].(map[string]any); ok {
		c["metrics"] = dropNilsDeep(m)
	}
	return c
}

// dropNilsDeep 复制 map 并递归去掉 null 值（不修改入参）。
func dropNilsDeep(m map[string]any) map[string]any {
	out := make(map[string]any, len(m))
	for k, v := range m {
		switch t := v.(type) {
		case nil:
			continue
		case map[string]any:
			out[k] = dropNilsDeep(t)
		default:
			out[k] = v
		}
	}
	return out
}

// ListView 生成给 App 的通讯录列表：PublicView 的可见性规则 + SelectList 收窄 +
// SlimEntry 精简。顶层浅拷贝，附带 list 元信息。
func ListView(p Payload, includeInsufficient bool, unlocked map[string]bool, opt ListOptions) Payload {
	out := make(Payload, len(p)+2)
	for k, v := range p {
		out[k] = v
	}
	visible := visibleEntries(p, includeInsufficient)
	sel, meta := SelectList(visible, opt)
	list := make([]any, 0, len(sel))
	for _, e := range sel {
		list = append(list, SlimEntry(LockedCopy(e, unlocked[str(e["id"])])))
	}
	out["archive"] = list
	out["list"] = meta
	return out
}

func visibleEntries(p Payload, includeInsufficient bool) []map[string]any {
	arch := Archive(p)
	out := make([]map[string]any, 0, len(arch))
	for _, e := range arch {
		curated, _ := e["curated"].(bool)
		if !includeInsufficient && str(e["verdict"]) == VerdictInsufficient && !curated {
			continue
		}
		out = append(out, e)
	}
	return out
}

// 搜索 ──────────────────────────────────────────────────────────────────

const (
	defaultSearchLimit = 50
	maxSearchLimit     = 200
	maxQueryLen        = 64
)

var familyLabels = map[string]string{
	"trend": "趋势跟随", "breakout": "突破", "reversal": "反转", "oscillator": "震荡指标",
	"bands": "通道", "level": "关键价位", "volatility": "波动率", "volume": "量能",
	"pattern": "形态", "research": "研究发现", "unknown": "其他",
}

var verdictLabels = map[string]string{
	VerdictInsufficient: "样本不足", VerdictReject: "淘汰", VerdictPending: "仍在验证",
	VerdictTradable: "可交易", VerdictFinding: "研究发现",
}

var freqLabels = map[string]string{
	"1d": "日线", "1min": "1分钟", "5min": "5分钟", "15min": "15分钟", "30min": "30分钟", "60min": "60分钟",
}

func searchText(e map[string]any) string {
	parts := []string{
		str(e["strategy"]), str(e["symbol"]), str(e["name"]), str(e["family"]),
		familyLabels[str(e["family_key"])], str(e["family_key"]), StrategyKey(e),
		str(e["freq"]), freqLabels[str(e["freq"])], str(e["headline"]),
		verdictLabels[str(e["verdict"])], str(e["id"]), str(e["source"]),
	}
	return strings.ToLower(strings.Join(parts, "\n"))
}

// SearchMeta 是搜索结果的元信息。
type SearchMeta struct {
	Query    string `json:"q"`
	Matched  int    `json:"matched"`
	Returned int    `json:"returned"`
	Limit    int    `json:"limit"`
}

// Search 在完整档案里搜索（含样本不足、含没进列表的淘汰条目）。
// 空格分隔的多个词需要同时命中；不区分大小写。排序：精选 → 非淘汰 → 离通过近的。
// 返回精简、按解锁状态脱敏后的条目。
func Search(p Payload, q string, limit int, unlocked map[string]bool) ([]any, SearchMeta) {
	q = strings.TrimSpace(q)
	if r := []rune(q); len(r) > maxQueryLen {
		q = string(r[:maxQueryLen])
	}
	if limit <= 0 {
		limit = defaultSearchLimit
	}
	if limit > maxSearchLimit {
		limit = maxSearchLimit
	}
	meta := SearchMeta{Query: q, Limit: limit}
	terms := strings.Fields(strings.ToLower(q))
	if len(terms) == 0 {
		return []any{}, meta
	}
	var hits []map[string]any
	for _, e := range Archive(p) {
		txt := searchText(e)
		ok := true
		for _, t := range terms {
			if !strings.Contains(txt, t) {
				ok = false
				break
			}
		}
		if ok {
			hits = append(hits, e)
		}
	}
	meta.Matched = len(hits)
	sort.SliceStable(hits, func(i, j int) bool {
		a, b := hits[i], hits[j]
		ca, _ := a["curated"].(bool)
		cb, _ := b["curated"].(bool)
		if ca != cb {
			return ca
		}
		ta, tb := isTail(a), isTail(b)
		if ta != tb {
			return !ta
		}
		return lessCloser(a, b)
	})
	if len(hits) > limit {
		hits = hits[:limit]
	}
	out := make([]any, 0, len(hits))
	for _, e := range hits {
		out = append(out, SlimEntry(LockedCopy(e, unlocked[str(e["id"])])))
	}
	meta.Returned = len(out)
	return out, meta
}
