package fishing

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tool"
)

// RegisterTools 把钓鱼工具注册进全集注册表。钱主题的白名单通过
// topic.FishingOnlyTools 排除它们，钓鱼主题的白名单只放它们 + 天气。
func RegisterTools(reg *tool.Registry, f *Forecaster) {
	reg.MustRegister(&forecastTool{f: f})
	reg.MustRegister(&regulationsTool{now: time.Now})
}

// ── get_fishing_forecast ─────────────────────────────────────────────

type forecastTool struct{ f *Forecaster }

func (t *forecastTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_fishing_forecast",
		Description: "查询某地未来几天的「出钓指数」（0–100）：按气压趋势(30)、风(20)、气温(20)、降水(20)、月相(10) 打分，" +
			"返回每天的总分、档位、各因子原始值与解释、推荐时段（清晨 / 傍晚）、日出日落和安全提醒。" +
			"place 传中文地名（城市、区县、水库或湖名都可以，例如「武汉」「千岛湖」「密云水库」）；" +
			"已知坐标时传 lat/lon 更准。回答时要引用分项解释，不要编造数字。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"place": {Type: "string", Description: "地名，例如 杭州 / 千岛湖 / 北京密云"},
				"lat":   {Type: "number", Description: "纬度（可选，和 lon 一起传）"},
				"lon":   {Type: "number", Description: "经度（可选）"},
				"days":  {Type: "integer", Description: "天数，默认 3，最多 7"},
			},
		},
	}
}

func (t *forecastTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Place string   `json:"place"`
		Lat   *float64 `json:"lat"`
		Lon   *float64 `json:"lon"`
		Days  int      `json:"days"`
	}
	if len(args) > 0 {
		if err := json.Unmarshal(args, &in); err != nil {
			return "", err
		}
	}
	cctx, cancel := context.WithTimeout(ctx, 25*time.Second)
	defer cancel()
	var fc *Forecast
	var err error
	switch {
	case in.Lat != nil && in.Lon != nil:
		fc, err = t.f.ForCoord(cctx, in.Place, *in.Lat, *in.Lon, in.Days)
	case in.Place != "":
		fc, err = t.f.ForPlace(cctx, in.Place, in.Days)
	default:
		return tool.EncodeJSON(map[string]any{"error": "需要 place（地名）或 lat/lon"}), nil
	}
	if errors.Is(err, ErrPlaceNotFound) {
		return tool.EncodeJSON(map[string]any{"error": "没找到这个地名，请换成所在城市或区县名"}), nil
	}
	if err != nil {
		return "", err
	}
	return tool.EncodeJSON(fc), nil
}

// ── get_fishing_regulations ──────────────────────────────────────────

type regulationsTool struct{ now func() time.Time }

func (t *regulationsTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_fishing_regulations",
		Description: "查询农业农村部公布的全国性流域禁渔 / 休渔制度（长江十年禁渔、黄河、淮河、珠江、闽江、海南内陆、钱塘江、" +
			"海河、辽河、松花江），并标出指定日期哪些处于禁渔期。只包含全国性制度，不含各省市细则；" +
			"回答时必须提醒「以当地渔政部门公告为准」，不要编造地方规定。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"date": {Type: "string", Description: "日期 YYYY-MM-DD，默认今天（北京时间）"},
			},
		},
	}
}

func (t *regulationsTool) Run(_ context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Date string `json:"date"`
	}
	if len(args) > 0 {
		_ = json.Unmarshal(args, &in)
	}
	d, err := ParseDate(in.Date, t.now())
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": "date 格式应为 YYYY-MM-DD"}), nil
	}
	return tool.EncodeJSON(RegulationsResponse(d)), nil
}

// ParseDate 解析 YYYY-MM-DD（北京时间）；空串返回 now 的北京时间日期。
func ParseDate(s string, now time.Time) (time.Time, error) {
	if s == "" {
		return now.In(cst), nil
	}
	return time.ParseInLocation("2006-01-02", s, cst)
}

// RegulationsResponse 是 regulations 工具 / 接口的统一输出。
func RegulationsResponse(d time.Time) map[string]any {
	return map[string]any{
		"date":        d.Format("2006-01-02"),
		"regulations": RegulationsOn(d),
		"disclaimer":  RegulationDisclaimer,
	}
}
