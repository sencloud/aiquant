package tools

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/sencloud/finme-backend/internal/ai/realtime"
	"github.com/sencloud/finme-backend/internal/ai/tool"
)

// registerRealtime 注册实时行情工具：
//
//   - get_realtime_quote          单标的实时快照（A 股 / ETF / 指数，新浪 hq.sinajs.cn）
//   - get_top_movers              涨幅 / 跌幅榜（东方财富 push2 clist；新浪无等价接口）
//   - get_market_snapshot         主流指数实时快照（新浪 hq.sinajs.cn）
//   - get_futures_realtime        单期货合约实时（CFFEX/SHFE/INE/DCE/CZCE/GFEX，新浪）
//   - get_futures_realtime_batch  批量期货合约实时（新浪 list= 单次批量拉取，最多 30 个）
func registerRealtime(r *tool.Registry, c *realtime.Client) {
	r.MustRegister(&getRealtimeQuoteTool{c: c})
	r.MustRegister(&getTopMoversTool{c: c})
	r.MustRegister(&getMarketSnapshotTool{c: c})
	r.MustRegister(&getFuturesRealtimeTool{c: c})
	r.MustRegister(&getFuturesRealtimeBatchTool{c: c})
}

// ── get_realtime_quote ─────────────────────────────────────────────────

type getRealtimeQuoteTool struct{ c *realtime.Client }

func (t *getRealtimeQuoteTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_realtime_quote",
		Description: "获取 A 股 / ETF / 主流指数当下实时报价（东方财富 push2，交易日盘中即时）。" +
			"返回最新价、涨跌幅、涨跌额、今开/最高/最低/昨收、成交量、成交额、换手率、市盈率。" +
			"想看多日历史走势请用 get_quote；这里专门覆盖「今天/此刻」语义。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol": {Type: "string", Description: "标的代码：6 位数字或 ts_code（600519 / 600519.SH / 000300.SH）"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *getRealtimeQuoteTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol string `json:"symbol"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	s := strings.TrimSpace(in.Symbol)
	if s == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	q, err := t.c.FetchSnapshot(ctx, s)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	out := map[string]any{
		"code":          q.Code,
		"ts_code":       q.TsCode,
		"name":          q.Name,
		"last":          q.Last,
		"pct_chg":       q.PctChg,
		"change":        q.Change,
		"open":          q.Open,
		"high":          q.High,
		"low":           q.Low,
		"pre_close":     q.PreClose,
		"volume":        q.Volume,
		"amount":        q.Amount,
		"turnover_rate": q.TurnoverRate,
		"pe_ttm":        q.PE,
		"delayed":       q.Delayed,
		"source":        "sina_hq",
	}
	return tool.EncodeJSON(out), nil
}

// ── get_top_movers ─────────────────────────────────────────────────────

type getTopMoversTool struct{ c *realtime.Client }

func (t *getTopMoversTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_top_movers",
		Description: "实时涨幅 / 跌幅榜（东方财富 push2）。可按全 A / 创业板 / 科创板 / 沪市 / 深市 / 行业板块筛选。" +
			"用于「今天涨幅最大的有色个股」「跌幅榜前 10」等问题。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"direction":  {Type: "string", Enum: []string{"up", "down"}, Description: "up=涨幅榜（默认）, down=跌幅榜"},
				"scope":      {Type: "string", Enum: []string{"a", "sh", "sz", "cy", "kc", "board"}, Description: "a=全 A 股(默认), sh=沪市, sz=深市, cy=创业板, kc=科创板, board=指定行业板块"},
				"board_code": {Type: "string", Description: "scope=board 时必填，行业板块东财代码 BKxxxx（如有色 BK0478、半导体 BK0475、新能源 BK0900）"},
				"limit":      {Type: "integer", Description: "前 N 条（默认 20，最大 100）"},
			},
		},
	}
}

func (t *getTopMoversTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Direction string `json:"direction,omitempty"`
		Scope     string `json:"scope,omitempty"`
		BoardCode string `json:"board_code,omitempty"`
		Limit     int    `json:"limit,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	limit := clampInt(in.Limit, 1, 100, 20)
	rows, err := t.c.FetchTopMovers(ctx, realtime.MoversOptions{
		Direction: in.Direction,
		Scope:     in.Scope,
		BoardCode: in.BoardCode,
		Limit:     limit,
	})
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	movers := make([]map[string]any, 0, len(rows))
	for _, m := range rows {
		movers = append(movers, map[string]any{
			"code":          m.Code,
			"ts_code":       m.TsCode,
			"name":          m.Name,
			"last":          m.Last,
			"pct_chg":       m.PctChg,
			"change":        m.Change,
			"volume":        m.Volume,
			"amount":        m.Amount,
			"turnover_rate": m.TurnoverRate,
		})
	}
	out := map[string]any{
		"direction": firstNonEmptyStr(in.Direction, "up"),
		"scope":     firstNonEmptyStr(in.Scope, "a"),
		"count":     len(movers),
		"movers":    movers,
		"source":    "eastmoney_push2",
	}
	if in.BoardCode != "" {
		out["board_code"] = strings.ToUpper(in.BoardCode)
	}
	return tool.EncodeJSON(out), nil
}

func firstNonEmptyStr(ss ...string) string {
	for _, s := range ss {
		if strings.TrimSpace(s) != "" {
			return s
		}
	}
	return ""
}

// ── get_market_snapshot（实时版本，替换原 Tushare 日线版本）─────────────

type getMarketSnapshotTool struct{ c *realtime.Client }

func (t *getMarketSnapshotTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_market_snapshot",
		Description: "获取 A 股主要指数（沪深 300 / 上证 50 / 中证 500 / 科创 50 / 创业板指 / 上证综指 / 深证成指）" +
			"的实时快照（东方财富 push2，交易日盘中即刻反映当日点位与涨跌幅）。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{},
		},
	}
}

var snapshotIndexCodes = []string{
	"000001.SH", // 上证综指
	"000300.SH", // 沪深 300
	"000016.SH", // 上证 50
	"000905.SH", // 中证 500
	"000688.SH", // 科创 50
	"399001.SZ", // 深证成指
	"399006.SZ", // 创业板指
}

func (t *getMarketSnapshotTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	quotes, err := t.c.FetchIndexes(ctx, snapshotIndexCodes)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	out := make([]map[string]any, 0, len(quotes))
	for _, q := range quotes {
		out = append(out, map[string]any{
			"code":      q.Code,
			"ts_code":   q.TsCode,
			"name":      q.Name,
			"last":      q.Last,
			"pct_chg":   q.PctChg,
			"change":    q.Change,
			"open":      q.Open,
			"high":      q.High,
			"low":       q.Low,
			"pre_close": q.PreClose,
			"delayed":   q.Delayed,
		})
	}
	return tool.EncodeJSON(map[string]any{
		"indexes": out,
		"source":  "sina_hq",
	}), nil
}

// ── get_futures_realtime ───────────────────────────────────────────────

type getFuturesRealtimeTool struct{ c *realtime.Client }

func (t *getFuturesRealtimeTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_futures_realtime",
		Description: "获取单个期货合约的实时行情（东方财富 push2，盘中即刻）。" +
			"覆盖中金所(CFFEX)、上期所(SHFE)、上海能源(INE)、大商所(DCE)、郑商所(CZCE)、广期所(GFEX)。" +
			"返回最新价、涨跌幅(相对昨结)、涨跌额、今开/最高/最低、昨收/昨结、成交量、成交额、持仓量、买一/卖一。" +
			"价格已按品种自动还原（自动处理 RB/AU/IF 等不同小数位）。" +
			"想知道某品种当前主力合约请先用 get_dominant_contract 取 ts_code，再传给本工具。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"ts_code": {
					Type: "string",
					Description: "完整期货合约 ts_code，必须带交易所后缀：" +
						"沪铜 CU2510.SHF、螺纹 RB2510.SHF、原油 SC2509.INE、" +
						"豆粕 M2509.DCE、白糖 SR509.CZC、IF2509.CFE、工业硅 SI2510.GFE",
				},
			},
			Required: []string{"ts_code"},
		},
	}
}

func (t *getFuturesRealtimeTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		TsCode string `json:"ts_code"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	ts := strings.TrimSpace(in.TsCode)
	if ts == "" {
		return tool.EncodeJSON(map[string]any{"error": "ts_code 必填，例如 RB2510.SHF / IF2509.CFE"}), nil
	}
	q, err := t.c.FetchFuturesSnapshot(ctx, ts)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	return tool.EncodeJSON(map[string]any{
		"code":       q.Code,
		"ts_code":    q.TsCode,
		"name":       q.Name,
		"exchange":   q.Exchange,
		"last":       q.Last,
		"pct_chg":    q.PctChg,
		"change":     q.Change,
		"open":       q.Open,
		"high":       q.High,
		"low":        q.Low,
		"pre_close":  q.PreClose,
		"pre_settle": q.PreSettle,
		"volume":     q.Volume,
		"amount":     q.Amount,
		"oi":         q.OI,
		"bid":        q.Bid,
		"ask":        q.Ask,
		"delayed":    q.Delayed,
		"source":     "sina_hq",
	}), nil
}

// ── get_futures_realtime_batch ─────────────────────────────────────────

type getFuturesRealtimeBatchTool struct{ c *realtime.Client }

func (t *getFuturesRealtimeBatchTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_futures_realtime_batch",
		Description: "批量获取多个期货合约的实时行情（最多 30 个，内部并发拉取，整体耗时与单合约接近）。" +
			"适合一次性比较『黑色系主力』『有色金属主力』『股指三大合约』等场景。" +
			"返回字段与 get_futures_realtime 一致。失败合约会被静默丢弃，不影响其他返回。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"ts_codes": {
					Type:        "array",
					Description: "期货合约 ts_code 数组，必须带交易所后缀，例如 [\"RB2510.SHF\",\"HC2510.SHF\",\"I2509.DCE\"]",
					Items: &tool.ParameterProperty{
						Type: "string",
					},
				},
			},
			Required: []string{"ts_codes"},
		},
	}
}

func (t *getFuturesRealtimeBatchTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		TsCodes []string `json:"ts_codes"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	codes := []string{}
	for _, s := range in.TsCodes {
		s = strings.TrimSpace(s)
		if s != "" {
			codes = append(codes, s)
		}
	}
	if len(codes) == 0 {
		return tool.EncodeJSON(map[string]any{"error": "ts_codes 至少传一个合约"}), nil
	}
	if len(codes) > 30 {
		codes = codes[:30]
	}
	quotes, err := t.c.FetchFuturesBatch(ctx, codes)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	out := make([]map[string]any, 0, len(quotes))
	for _, q := range quotes {
		out = append(out, map[string]any{
			"code":       q.Code,
			"ts_code":    q.TsCode,
			"name":       q.Name,
			"exchange":   q.Exchange,
			"last":       q.Last,
			"pct_chg":    q.PctChg,
			"change":     q.Change,
			"open":       q.Open,
			"high":       q.High,
			"low":        q.Low,
			"pre_settle": q.PreSettle,
			"volume":     q.Volume,
			"amount":     q.Amount,
			"oi":         q.OI,
			"delayed":    q.Delayed,
		})
	}
	return tool.EncodeJSON(map[string]any{
		"count":  len(out),
		"quotes": out,
		"source": "sina_hq",
	}), nil
}
