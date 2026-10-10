// Package falsification 提供「证伪档案」的公开读取、详情解锁与「跑一次证伪」。
//
// 数据来源是 alpha-radar 的只读导出（GET {alpharadar.url}/api/falsification），
// scheduler 定时拉取落库；api 进程读库里最新一份，没有就回落到二进制内置的
// seed（与 App 内置的 assets/strategy/falsification.json 同一份）。
//
// schema 只做宽松解析（map[string]any）：上游加字段不需要改这里，缺字段也不报错。
// 对外输出前统一做三件事：
//   - 删除所有 report_url（HTML 报告只在内部保留，不对外开放）；
//   - 丢弃非商用许可（CC BY-NC 等）的条目；
//   - 默认不返回 verdict=insufficient（样本不足只在搜索里出现）。
package falsification

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
)

//go:embed seed.json
var seedJSON []byte

// Payload 是一份完整档案（顶层 + archive[]），宽松 schema。
type Payload = map[string]any

// 结论取值。
const (
	VerdictInsufficient = "insufficient"
	VerdictReject       = "reject"
	VerdictPending      = "pending"
	VerdictTradable     = "tradable"
	VerdictFinding      = "finding"
)

// PaidFields 是需要按条解锁的字段：分年盈亏、失效机制、复现命令。
// 结论、关键数字、闸门结果始终免费。
var PaidFields = []string{"yearly", "mechanism", "command"}

// Seed 返回内置档案的一份新拷贝（调用方可以随意修改）。
func Seed() (Payload, error) {
	var p Payload
	if err := json.Unmarshal(seedJSON, &p); err != nil {
		return nil, fmt.Errorf("decode seed: %w", err)
	}
	return Sanitize(p), nil
}

// Decode 解析上游 / 库里的 JSON。archive 必须是数组，否则视为坏数据。
func Decode(raw []byte) (Payload, error) {
	var p Payload
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, err
	}
	if _, ok := p["archive"].([]any); !ok {
		return nil, fmt.Errorf("falsification payload: archive missing or not a list")
	}
	return p, nil
}

// Sanitize 删除所有层级的 report_url，并丢弃非商用许可的条目。原地修改并返回。
func Sanitize(p Payload) Payload {
	stripKey(p, "report_url")
	arch := Archive(p)
	kept := make([]any, 0, len(arch))
	for _, e := range arch {
		if IsNonCommercial(str(e["license"])) {
			continue
		}
		kept = append(kept, e)
	}
	p["archive"] = kept
	return p
}

// stripKey 递归删除 map / slice 里所有名为 key 的字段。
func stripKey(v any, key string) {
	switch t := v.(type) {
	case map[string]any:
		delete(t, key)
		for _, c := range t {
			stripKey(c, key)
		}
	case []any:
		for _, c := range t {
			stripKey(c, key)
		}
	}
}

var ncRe = regexp.MustCompile(`(?i)(\bNC\b|-NC|NC-|non[- ]?commercial|非商用|禁止商用)`)

// IsNonCommercial 判断许可字符串是否禁止商用（CC BY-NC / BY-NC-SA / BY-NC-ND 等）。
func IsNonCommercial(license string) bool {
	if strings.TrimSpace(license) == "" {
		return false
	}
	return ncRe.MatchString(license)
}

// Archive 取出 archive 里所有对象条目。
func Archive(p Payload) []map[string]any {
	raw, _ := p["archive"].([]any)
	out := make([]map[string]any, 0, len(raw))
	for _, e := range raw {
		if m, ok := e.(map[string]any); ok {
			out = append(out, m)
		}
	}
	return out
}

// Merge 用 seed 补齐上游缺的部分：
//   - 顶层缺 source / cost_scales / gates 时取 seed 的（方法页要用）；
//   - 上游没有任何 curated 条目时，把 seed 的精选档案按 id 去重追加进去。
//
// 原地修改 upstream 并返回。
func Merge(upstream, seed Payload) Payload {
	for _, k := range []string{"source", "cost_scales", "gates", "threshold_version"} {
		if _, ok := upstream[k]; !ok {
			if v, ok := seed[k]; ok {
				upstream[k] = v
			}
		}
	}
	arch := Archive(upstream)
	hasCurated := false
	ids := map[string]bool{}
	for _, e := range arch {
		ids[str(e["id"])] = true
		if b, _ := e["curated"].(bool); b {
			hasCurated = true
		}
	}
	if !hasCurated {
		raw, _ := upstream["archive"].([]any)
		for _, e := range Archive(seed) {
			if b, _ := e["curated"].(bool); b && !ids[str(e["id"])] {
				raw = append(raw, e)
			}
		}
		upstream["archive"] = raw
	}
	return upstream
}

// PublicView 生成对外输出：浅拷贝顶层，archive 换成过滤 / 脱敏后的新数组。
//
//   - includeInsufficient=false 时去掉样本不足的条目（精选档案除外：手写结论
//     本身就是内容）；
//   - unlocked 里没有的条目，去掉 PaidFields 并标 locked=true。传 nil 表示
//     全部锁住（未登录）。
func PublicView(p Payload, includeInsufficient bool, unlocked map[string]bool) Payload {
	out := make(Payload, len(p)+1)
	for k, v := range p {
		out[k] = v
	}
	arch := Archive(p)
	list := make([]any, 0, len(arch))
	for _, e := range arch {
		curated, _ := e["curated"].(bool)
		if !includeInsufficient && str(e["verdict"]) == VerdictInsufficient && !curated {
			continue
		}
		list = append(list, LockedCopy(e, unlocked[str(e["id"])]))
	}
	out["archive"] = list
	return out
}

// LockedCopy 返回条目的浅拷贝；未解锁时去掉付费字段并标注。
func LockedCopy(e map[string]any, unlocked bool) map[string]any {
	c := make(map[string]any, len(e)+2)
	for k, v := range e {
		c[k] = v
	}
	if !HasPaidContent(e) {
		c["locked"] = false
		return c
	}
	if unlocked {
		c["locked"] = false
		return c
	}
	for _, f := range PaidFields {
		delete(c, f)
	}
	c["locked"] = true
	return c
}

// HasPaidContent 条目里是否真有需要付费才能看的内容。
func HasPaidContent(e map[string]any) bool {
	for _, f := range PaidFields {
		switch v := e[f].(type) {
		case string:
			if strings.TrimSpace(v) != "" {
				return true
			}
		case []any:
			if len(v) > 0 {
				return true
			}
		}
	}
	return false
}

// FindEntry 按 id 找条目。
func FindEntry(p Payload, id string) (map[string]any, bool) {
	for _, e := range Archive(p) {
		if str(e["id"]) == id {
			return e, true
		}
	}
	return nil, false
}

var strategyFlagRe = regexp.MustCompile(`--strategy\s+([A-Za-z0-9_\-]+)`)

// StrategyKey 取条目对应的 alpha-radar 策略 id：优先 strategy_id 字段，
// 其次从复现命令里解析 `--strategy xxx`。
func StrategyKey(e map[string]any) string {
	if v := str(e["strategy_id"]); v != "" {
		return v
	}
	if m := strategyFlagRe.FindStringSubmatch(str(e["command"])); len(m) == 2 {
		return m[1]
	}
	return ""
}

func str(v any) string {
	switch t := v.(type) {
	case nil:
		return ""
	case string:
		return t
	default:
		return fmt.Sprint(t)
	}
}
