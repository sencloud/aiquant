// Package topic 定义「喜爱」App 的主题（Topic）在服务端的差异：
// 基础 system prompt、人设表、工具白名单、推荐追问口吻、计费 reason。
//
// 客户端按主题切换整个 App（页签 / 助手 / 内容 / 配色），服务端只认 topic id：
//   - money   喜爱钱：给你量化（默认；老版本 App 不传 topic 时一律按 money）
//   - fishing 喜爱钓鱼：给你钓鱼相关的一切
//   - cat     喜爱养猫：给你养猫的一切
//   - coffee  喜爱咖啡：给你咖啡的一切
//   - camping 喜爱露营：给你露营的一切
//   - hanfu   喜爱汉服：给你汉服的一切
//   - social  广场：成年人交朋友 —— 六位标明的 AI 居民，不挂任何工具
//
// 喜点、内购、邀请全主题共享一个余额；钓鱼主题的流水用 reason 前缀 fishing.* 区分。
package topic

import (
	"errors"
	"sort"
	"strings"
)

// 主题 id。
const (
	Money   = "money"
	Fishing = "fishing"
	Cat     = "cat"
	Coffee  = "coffee"
	Camping = "camping"
	Hanfu   = "hanfu"
	// Default 是缺省主题：老客户端不传 topic 时使用。
	Default = Money
)

// ErrUnknownTopic 表示请求里带了未知的 topic。
var ErrUnknownTopic = errors.New("unknown topic")

// Persona 是一个人设：id + 展示名 + 服务端持有的 prompt。
type Persona struct {
	ID     string
	Name   string
	Prompt string
}

// Topic 是一个主题在服务端的全部差异点。
type Topic struct {
	ID   string
	Name string

	// Role 是 system prompt 里「你是谁、怎么用工具」的基础段落
	// （拼在真实当前时间段落之后）。
	Role string

	// Personas 是人设表；DefaultPersona 是找不到 id 时的回落。
	Personas       []Persona
	DefaultPersona string

	// AcceptSystemHint 为 true 时继续接受客户端上送的 system_hint（钱主题
	// 必须长期兼容老版本 App）；false 时忽略，人设只看 persona id。
	AcceptSystemHint bool

	// Tools 非空时是工具白名单（只暴露、只放行这些工具）。
	// 为空表示「全集减去 ExcludeTools」。
	Tools []string
	// NoTools 为 true 时这个主题不暴露任何工具（养猫 / 咖啡 / 汉服：
	// 它们靠模型本身与用户自己的记录回答，没有任何需要联网查的东西）。
	// 比「白名单里什么都不写」明确：空列表在 [AllowedTools] 里的含义是
	// 「全集减去 ExcludeTools」，会被误读成放开全部行情工具。
	NoTools bool
	// ExcludeTools 只在 Tools 为空时生效：全集里排除这些工具（钱主题用它
	// 挡掉其它主题专属的工具）。
	ExcludeTools []string

	// FollowUpPrompt 是推荐追问生成器的 system prompt。
	FollowUpPrompt string

	// AllowDeep 为 false 时忽略客户端的 deep_mode（不切 reasoner、不加价）：
	// 钓鱼对话定价 1 喜点 / 轮。
	AllowDeep bool

	// ChatReason 是对话扣费写进 credit_ledger.reason 的值。
	ChatReason string

	// HomeSuggestions 非空时作为首页「今天想聊点什么」的静态提问
	// （钱主题走市场简报，不用这个字段）。
	HomeSuggestions []string

	// Guard 在用户消息命中敏感词时返回追加到 system prompt 的提醒
	// （只提醒模型拒绝，不直接拦截：「电鱼违法吗」这类问题仍应正常回答）。
	Guard func(userText string) string
}

var registry = map[string]*Topic{}

func register(t *Topic) { registry[t.ID] = t }

// IDs 返回全部已注册主题 id（排序）。
func IDs() []string {
	out := make([]string, 0, len(registry))
	for id := range registry {
		out = append(out, id)
	}
	sort.Strings(out)
	return out
}

// Valid 判断 id 是否为已知主题（空串视为合法 = 默认主题）。
func Valid(id string) bool {
	id = strings.TrimSpace(id)
	if id == "" {
		return true
	}
	_, ok := registry[id]
	return ok
}

// Resolve 把请求里的 topic 解析成 *Topic：空串 → 默认主题（money），未知 → ErrUnknownTopic。
func Resolve(id string) (*Topic, error) {
	id = strings.TrimSpace(id)
	if id == "" {
		id = Default
	}
	t, ok := registry[id]
	if !ok {
		return nil, ErrUnknownTopic
	}
	return t, nil
}

// MustGet 取已知主题；未知 panic（只在代码里写死的 id 上用）。
func MustGet(id string) *Topic {
	t, ok := registry[id]
	if !ok {
		panic("topic: unknown " + id)
	}
	return t
}

// Persona 按 id 找人设；找不到回落到默认人设；主题没有人设表时返回零值。
func (t *Topic) Persona(id string) Persona {
	for _, p := range t.Personas {
		if p.ID == id {
			return p
		}
	}
	for _, p := range t.Personas {
		if p.ID == t.DefaultPersona {
			return p
		}
	}
	return Persona{}
}

// HasPersona 判断 id 是否是本主题的人设。
func (t *Topic) HasPersona(id string) bool {
	for _, p := range t.Personas {
		if p.ID == id {
			return true
		}
	}
	return false
}

// AllowedTools 从全集工具名里算出本主题可用的工具名（排序）。
func (t *Topic) AllowedTools(all []string) []string {
	if t.NoTools {
		return nil
	}
	var out []string
	if len(t.Tools) > 0 {
		have := make(map[string]bool, len(all))
		for _, n := range all {
			have[n] = true
		}
		for _, n := range t.Tools {
			if have[n] {
				out = append(out, n)
			}
		}
	} else {
		ex := make(map[string]bool, len(t.ExcludeTools))
		for _, n := range t.ExcludeTools {
			ex[n] = true
		}
		for _, n := range all {
			if !ex[n] {
				out = append(out, n)
			}
		}
	}
	sort.Strings(out)
	return out
}
