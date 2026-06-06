package tools

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/calendar"
	"github.com/sencloud/finme-backend/internal/ai/tool"
)

// registerCalendar 注册经济日历工具（百度股市通，境内可达）。
func registerCalendar(r *tool.Registry, c *calendar.Client) {
	r.MustRegister(&getEconomicCalendarTool{c: c})
}

// ── get_economic_calendar ──────────────────────────────────────────────

type getEconomicCalendarTool struct{ c *calendar.Client }

func (t *getEconomicCalendarTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_economic_calendar",
		Description: "获取全球经济数据发布日历（非农 / CPI / PPI / 议息 / GDP / PMI 等的公布时间、" +
			"重要性、前值 / 预期 / 公布值，时间为北京时间）。数据源百度股市通。" +
			"用于「本周有哪些重要数据」「今晚非农几点公布」「下周美联储议息」等前瞻性问题。" +
			"未公布的事件 actual 为空。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"date":     {Type: "string", Description: "起始日期 YYYYMMDD 或 YYYY-MM-DD，默认今天（北京时间）"},
				"days":     {Type: "integer", Description: "从起始日起向后看的天数（默认 1，最大 14）"},
				"min_star": {Type: "integer", Description: "仅返回重要性 >= 该值的事件（1~3，默认 0 不过滤；查重要数据建议传 2）"},
				"region":   {Type: "string", Description: "可选地区过滤（子串匹配，如 美国 / 中国 / 欧元区 / 日本）"},
				"limit":    {Type: "integer", Description: "最多返回条数（默认 60，最大 200）"},
			},
		},
	}
}

func (t *getEconomicCalendarTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Date    string `json:"date,omitempty"`
		Days    int    `json:"days,omitempty"`
		MinStar int    `json:"min_star,omitempty"`
		Region  string `json:"region,omitempty"`
		Limit   int    `json:"limit,omitempty"`
	}
	if len(args) > 0 {
		if err := json.Unmarshal(args, &in); err != nil {
			return "", err
		}
	}
	loc := shanghaiLoc()
	start := parseCalDate(in.Date, loc)
	days := clampInt(in.Days, 1, 14, 1)
	end := start.AddDate(0, 0, days-1)
	limit := clampInt(in.Limit, 1, 200, 60)
	region := strings.TrimSpace(in.Region)

	events, err := t.c.FetchEconomicCalendar(ctx,
		start.Format("2006-01-02"), end.Format("2006-01-02"))
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}

	out := make([]map[string]any, 0, len(events))
	for _, e := range events {
		if e.Star < in.MinStar {
			continue
		}
		if region != "" && !strings.Contains(e.Region, region) {
			continue
		}
		m := map[string]any{
			"date":   e.Date,
			"time":   e.Time,
			"region": e.Region,
			"event":  e.Title,
			"star":   e.Star,
		}
		if e.Previous != "" {
			m["previous"] = e.Previous
		}
		if e.Forecast != "" {
			m["forecast"] = e.Forecast
		}
		if e.Actual != "" {
			m["actual"] = e.Actual
		}
		if e.Period != "" {
			m["period"] = e.Period
		}
		out = append(out, m)
		if len(out) >= limit {
			break
		}
	}
	return tool.EncodeJSON(map[string]any{
		"start_date": start.Format("2006-01-02"),
		"end_date":   end.Format("2006-01-02"),
		"timezone":   "Asia/Shanghai",
		"count":      len(out),
		"events":     out,
		"source":     "baidu_gushitong",
	}), nil
}

// parseCalDate 解析 YYYYMMDD / YYYY-MM-DD；为空或非法时回退到今天（指定时区）。
func parseCalDate(s string, loc *time.Location) time.Time {
	s = strings.TrimSpace(s)
	for _, layout := range []string{"20060102", "2006-01-02"} {
		if d, err := time.ParseInLocation(layout, s, loc); err == nil {
			return d
		}
	}
	now := time.Now().In(loc)
	return time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
}
