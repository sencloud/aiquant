package tools

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/sencloud/finme-backend/internal/ai/realtime"
	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// registerGlobal 注册「全球行情」工具（东方财富 push2delay，已在阿里云生产实测可达）：
//
//   - get_us_stock_realtime        单支美股实时快照
//   - get_us_stock_realtime_batch  批量美股实时快照（并发）
//   - get_global_index             全球主要股指实时（道指/标普/纳指/恒生/日经/德指/富时/美元指数）
//   - get_forex_rate               主流货币对 / 美元指数实时
//
// 底层共用 realtime.Client 的 emStockGet + 短期缓存，新增市场只需加薄工具。
//
// 取数源已变更：东财 push2 系在阿里云出口整体不可达，美股与全球指数改为
// 腾讯优先 / 东财兜底；外汇东财拿不到时退 Tushare fx_daily（日线口径）。
func registerGlobal(r *tool.Registry, c *realtime.Client, tu *tushare.Client) {
	r.MustRegister(&getUSStockRealtimeTool{c: c})
	r.MustRegister(&getUSStockRealtimeBatchTool{c: c})
	r.MustRegister(&getGlobalIndexTool{c: c})
	r.MustRegister(&getForexRateTool{c: c, tu: tu})
}

// globalQuoteToJSON 把 GlobalQuote 转成对外 map（统一字段命名）。
func globalQuoteToJSON(q realtime.GlobalQuote) map[string]any {
	m := map[string]any{
		"symbol":    q.Symbol,
		"secid":     q.SecID,
		"name":      q.Name,
		"last":      q.Last,
		"pct_chg":   q.PctChg,
		"change":    q.Change,
		"open":      q.Open,
		"high":      q.High,
		"low":       q.Low,
		"pre_close": q.PreClose,
		"delayed":   q.Delayed,
	}
	if q.Volume != 0 {
		m["volume"] = q.Volume
	}
	if q.Amount != 0 {
		m["amount"] = q.Amount
	}
	return m
}

// ── get_us_stock_realtime ──────────────────────────────────────────────

type getUSStockRealtimeTool struct{ c *realtime.Client }

func (t *getUSStockRealtimeTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_us_stock_realtime",
		Description: "获取单支美股的实时报价（东方财富，含盘前盘后，行情有少量延迟）。" +
			"自动识别纳斯达克 / 纽交所 / 美交所，无需区分市场后缀。" +
			"返回最新价(美元)、涨跌幅、涨跌额、今开/最高/最低/昨收、成交量。" +
			"用于「苹果现在多少钱」「英伟达今天涨跌」等美股即时问题。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol": {Type: "string", Description: "美股代码：AAPL / MSFT / NVDA / TSLA / BABA / BRK.A 等"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *getUSStockRealtimeTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol string `json:"symbol"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	s := strings.TrimSpace(in.Symbol)
	if s == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填，例如 AAPL / NVDA"}), nil
	}
	q, err := t.c.FetchUSStock(ctx, s)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	out := globalQuoteToJSON(*q)
	out["currency"] = "USD"
	out["source"] = "eastmoney_push2"
	return tool.EncodeJSON(out), nil
}

// ── get_us_stock_realtime_batch ────────────────────────────────────────

type getUSStockRealtimeBatchTool struct{ c *realtime.Client }

func (t *getUSStockRealtimeBatchTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_us_stock_realtime_batch",
		Description: "批量获取多支美股实时报价（最多 30 支，内部并发，整体耗时接近单支）。" +
			"适合一次性比较「美股七姐妹」「半导体龙头」等。失败项静默丢弃。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbols": {
					Type:        "array",
					Description: "美股代码数组，例如 [\"AAPL\",\"MSFT\",\"NVDA\",\"GOOGL\"]",
					Items:       &tool.ParameterProperty{Type: "string"},
				},
			},
			Required: []string{"symbols"},
		},
	}
}

func (t *getUSStockRealtimeBatchTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbols []string `json:"symbols"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	codes := []string{}
	for _, s := range in.Symbols {
		if s = strings.TrimSpace(s); s != "" {
			codes = append(codes, s)
		}
	}
	if len(codes) == 0 {
		return tool.EncodeJSON(map[string]any{"error": "symbols 至少传一个美股代码"}), nil
	}
	if len(codes) > 30 {
		codes = codes[:30]
	}
	quotes, err := t.c.FetchUSBatch(ctx, codes)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	out := make([]map[string]any, 0, len(quotes))
	for _, q := range quotes {
		out = append(out, globalQuoteToJSON(q))
	}
	return tool.EncodeJSON(map[string]any{
		"count":    len(out),
		"currency": "USD",
		"quotes":   out,
		"source":   "eastmoney_push2",
	}), nil
}

// ── get_global_index ───────────────────────────────────────────────────

type getGlobalIndexTool struct{ c *realtime.Client }

func (t *getGlobalIndexTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_global_index",
		Description: "获取全球主要股指实时快照（东方财富，少量延迟）。" +
			"不传参数时返回默认集合：道指、标普500、纳斯达克、恒生、日经225、德国DAX、英国富时100、美元指数。" +
			"可用 symbols 指定子集。用于「美股三大指数表现」「今晚外盘怎么样」等问题。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbols": {
					Type: "array",
					Description: "可选，指数别名数组。支持：DJIA(道指)/SPX(标普)/NDX(纳指)/HSI(恒生)/" +
						"N225(日经)/GDAXI(德指)/FTSE(富时)/UDI(美元指数)",
					Items: &tool.ParameterProperty{Type: "string"},
				},
			},
		},
	}
}

func (t *getGlobalIndexTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbols []string `json:"symbols,omitempty"`
	}
	if len(args) > 0 {
		if err := json.Unmarshal(args, &in); err != nil {
			return "", err
		}
	}
	quotes, err := t.c.FetchGlobalIndexes(ctx, in.Symbols)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	out := make([]map[string]any, 0, len(quotes))
	for _, q := range quotes {
		out = append(out, globalQuoteToJSON(q))
	}
	return tool.EncodeJSON(map[string]any{
		"count":   len(out),
		"indexes": out,
		"source":  "eastmoney_push2",
	}), nil
}

// ── get_forex_rate ─────────────────────────────────────────────────────

type getForexRateTool struct {
	c  *realtime.Client
	tu *tushare.Client
}

func (t *getForexRateTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_forex_rate",
		Description: "获取主流外汇货币对 / 美元指数实时报价（东方财富，少量延迟）。" +
			"不传参数时返回默认集合：美元指数、离岸人民币、人民币中间价、欧元美元、美元日元、英镑美元。" +
			"用于「人民币汇率」「美元指数」「欧元走势」等问题。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"pairs": {
					Type: "array",
					Description: "可选，货币对别名数组。支持：UDI(美元指数)/USDCNH(离岸人民币)/USDCNYC(中间价)/" +
						"EURUSD/USDJPY/GBPUSD/AUDUSD/USDCAD/USDCHF",
					Items: &tool.ParameterProperty{Type: "string"},
				},
			},
		},
	}
}

func (t *getForexRateTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Pairs []string `json:"pairs,omitempty"`
	}
	if len(args) > 0 {
		if err := json.Unmarshal(args, &in); err != nil {
			return "", err
		}
	}
	quotes, err := t.c.FetchForexBatch(ctx, in.Pairs)
	if err != nil || len(quotes) == 0 {
		// 东财不可达 → 逐对退 Tushare fx_daily（日线收盘口径）。
		// 注意 len==0 也要兜底：东财不可达时批量方法会吞掉错误返回空列表，
		// 表现为"成功但没数据"，比报错更难排查。
		pairs := in.Pairs
		if len(pairs) == 0 {
			pairs = []string{"UDI", "USDCNH", "EURUSD", "USDJPY", "GBPUSD"}
		}
		rates := make([]map[string]any, 0, len(pairs))
		for _, p := range pairs {
			if fb, ferr := forexDailyFallback(ctx, t.tu, p); ferr == nil {
				rates = append(rates, fb)
			}
		}
		if len(rates) > 0 {
			return tool.EncodeJSON(map[string]any{
				"count":    len(rates),
				"rates":    rates,
				"source":   "tushare_fx_daily",
				"realtime": false,
				"notice":   "实时外汇源在服务器出口不可达，以上为最近交易日收盘口径（非盘中价）。",
			}), nil
		}
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	out := make([]map[string]any, 0, len(quotes))
	for _, q := range quotes {
		out = append(out, globalQuoteToJSON(q))
	}
	return tool.EncodeJSON(map[string]any{
		"count":  len(out),
		"rates":  out,
		"source": "eastmoney_push2",
	}), nil
}
