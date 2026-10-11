package miniapp

import (
	"embed"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

//go:embed templates/*.json
var templateFS embed.FS

// Template 是官方小应用模板（未登录也能浏览；登录后可“用这个模板”复制成自己的）。
type Template struct {
	ID       string         `json:"id"`
	Topic    string         `json:"topic"`
	Order    int            `json:"order"`
	Title    string         `json:"title"`
	Summary  string         `json:"summary"`
	Icon     string         `json:"icon"`
	Spec     map[string]any `json:"spec"`
	Private  bool           `json:"private_data"` // 用到私人数据（未登录时显示为空）
	compiled *Compiled
}

// LoadTemplates 读取并校验内置模板。校验失败的模板返回在 errs 里（不会出现在结果中）。
func LoadTemplates(reg *Registry) ([]*Template, []error) {
	entries, err := templateFS.ReadDir("templates")
	if err != nil {
		return nil, []error{err}
	}
	var out []*Template
	var errs []error
	for _, e := range entries {
		b, err := templateFS.ReadFile("templates/" + e.Name())
		if err != nil {
			errs = append(errs, err)
			continue
		}
		var t Template
		if err := json.Unmarshal(b, &t); err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", e.Name(), err))
			continue
		}
		t.Topic, _ = t.Spec["topic"].(string)
		c, issues := Validate(t.Spec, t.Topic, reg)
		if len(issues) > 0 {
			msgs := make([]string, 0, len(issues))
			for _, i := range issues {
				msgs = append(msgs, i.String())
			}
			errs = append(errs, fmt.Errorf("%s: %s", e.Name(), strings.Join(msgs, "; ")))
			continue
		}
		t.compiled = c
		t.Title, t.Summary, t.Icon, t.Private = c.Title, c.Summary, c.Icon, c.UserScoped
		t.Spec = c.Raw
		out = append(out, &t)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Topic != out[j].Topic {
			return out[i].Topic < out[j].Topic
		}
		return out[i].Order < out[j].Order
	})
	return out, errs
}
