// Package tool 是服务端 AI 工具的统一抽象与注册表。
//
// 每个工具实现 Runner 接口；所有工具通过 Registry 集中调度。Spec 转换成
// OpenAI / DeepSeek 协议要求的 tools 数组形态供 LLM 调用。
//
// 与客户端 Dart 旧实现 (lib/services/ai_tools.dart) 协议保持兼容：
//   - name 必须是字母 / 数字 / 下划线
//   - parameters 是 JSON Schema 子集
//   - 返回值是 JSON 字符串（喂回 model 当 role=tool 的 message）
package tool

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
)

// ParameterProperty 描述一个入参字段。
type ParameterProperty struct {
	Type        string   `json:"type"`
	Description string   `json:"description,omitempty"`
	Enum        []string `json:"enum,omitempty"`
	// Items 仅当 Type=="array" 时有效，描述数组元素。
	Items *ParameterProperty `json:"items,omitempty"`
}

// ParameterSchema 与 Dart 端的 ToolParameterSchema 对齐。
type ParameterSchema struct {
	Properties map[string]ParameterProperty `json:"properties"`
	Required   []string                     `json:"required,omitempty"`
}

func (s ParameterSchema) toJSONSchema() map[string]any {
	out := map[string]any{
		"type":       "object",
		"properties": s.Properties,
	}
	if len(s.Required) > 0 {
		out["required"] = s.Required
	}
	return out
}

// Spec 描述工具的元数据。
type Spec struct {
	Name        string
	Description string
	Parameters  ParameterSchema
}

// Runner 是所有工具的统一接口。
//
// Run 入参是 LLM 反序列化的 JSON 字符串原文（不会预解析）；返回值是
// 序列化好的 JSON 字符串（直接喂回 model）。任何错误都被 Registry
// 包装为 `{"error":"..."}`，避免单工具失败让 LLM 卡死。
type Runner interface {
	Spec() Spec
	Run(ctx context.Context, args json.RawMessage) (string, error)
}

// Registry 集中注册 + 调度全部工具。
type Registry struct {
	tools map[string]Runner
	// scope 非空表示这是 [Registry.Subset] 产出的白名单视图（如 "fishing"），
	// 只用于拒绝信息里说明「该主题不可用」。
	scope string
	// parent 是白名单视图的来源注册表：白名单外但存在于全集的工具，拒绝信息
	// 会写明是「主题不允许」而不是「不存在」，便于排查。
	parent *Registry
}

// New 构造空 Registry。
func New() *Registry {
	return &Registry{tools: make(map[string]Runner)}
}

// MustRegister 注册工具；同名重复注册 panic（编程错误，启动期暴露）。
func (r *Registry) MustRegister(t Runner) {
	name := t.Spec().Name
	if name == "" {
		panic("tool: empty name")
	}
	if _, ok := r.tools[name]; ok {
		panic("tool: duplicate name " + name)
	}
	r.tools[name] = t
}

// Names 返回排序后的工具名列表（便于审计 / 测试）。
func (r *Registry) Names() []string {
	out := make([]string, 0, len(r.tools))
	for n := range r.tools {
		out = append(out, n)
	}
	sort.Strings(out)
	return out
}

// Subset 返回只包含 names 中工具的白名单视图（共享同一组 Runner）。
//
// 视图的 ToolListJSON 只输出白名单内的工具；Dispatch 只放行白名单，模型
// 幻觉调用白名单外的工具（比如钓鱼会话里调 get_quote）会被拒绝并以
// `{"error":...}` 回给模型。names 里不存在的工具名被静默忽略。
func (r *Registry) Subset(scope string, names []string) *Registry {
	out := &Registry{tools: make(map[string]Runner, len(names)), scope: scope, parent: r}
	for _, n := range names {
		if t, ok := r.tools[n]; ok {
			out.tools[n] = t
		}
	}
	return out
}

// Scope 返回白名单视图的作用域名；全集注册表返回空串。
func (r *Registry) Scope() string { return r.scope }

// Has 判断工具是否在本注册表（或白名单视图）内。
func (r *Registry) Has(name string) bool {
	_, ok := r.tools[name]
	return ok
}

// Find 查工具 / nil。
func (r *Registry) Find(name string) Runner { return r.tools[name] }

// ToolListJSON 输出 OpenAI / DeepSeek 协议要求的 tools 数组。
//
// 形态：
//
//	[{"type":"function","function":{
//	   "name":"...","description":"...","parameters":{...}
//	}},...]
func (r *Registry) ToolListJSON() []map[string]any {
	names := r.Names()
	out := make([]map[string]any, 0, len(names))
	for _, n := range names {
		t := r.tools[n]
		s := t.Spec()
		out = append(out, map[string]any{
			"type": "function",
			"function": map[string]any{
				"name":        s.Name,
				"description": s.Description,
				"parameters":  s.Parameters.toJSONSchema(),
			},
		})
	}
	return out
}

// Dispatch 是 LLM tool_call 的执行入口。
//
// 任何错误（找不到工具 / 参数 JSON 无效 / 工具内部异常）都被序列化为
// `{"error":"..."}` 字符串返回，让 LLM 在 tool 消息里看到错误并自适应。
func (r *Registry) Dispatch(ctx context.Context, name string, argsJSON string) string {
	t := r.tools[name]
	if t == nil {
		if r.parent != nil && r.parent.Has(name) {
			return errorJSON(fmt.Errorf("tool %q is not available in topic %q", name, r.scope))
		}
		return errorJSON(fmt.Errorf("unknown tool %q", name))
	}
	args := json.RawMessage(argsJSON)
	if len(args) == 0 {
		args = json.RawMessage(`{}`)
	}
	// 校验参数本身是合法 JSON object
	var dummy map[string]any
	if err := json.Unmarshal(args, &dummy); err != nil {
		return errorJSON(fmt.Errorf("invalid arguments: %w", err))
	}
	out, err := t.Run(ctx, args)
	if err != nil {
		return errorJSON(err)
	}
	return out
}

// errorJSON 把 error 序列化成 `{"error":"<message>"}` 字符串。
func errorJSON(err error) string {
	b, _ := json.Marshal(map[string]string{"error": err.Error()})
	return string(b)
}

// EncodeJSON 工具内部用：把任意值序列化成字符串；失败则返回错误 JSON。
func EncodeJSON(v any) string {
	b, err := json.Marshal(v)
	if err != nil {
		return errorJSON(err)
	}
	return string(b)
}

// ErrEmptyResult 工具想表达"接口返回空"且需要让 LLM 看到时使用。
var ErrEmptyResult = errors.New("empty result")
