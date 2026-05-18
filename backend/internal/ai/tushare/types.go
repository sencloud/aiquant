// Package tushare 是 Tushare HTTP API 的服务端单点客户端。
//
// 客户端 (Dart) 不再直连，所有 token 收回服务端；新闻 / 卫星 / 宏观资金等
// 数据源也在 internal/ai/news 包内统一管理。
package tushare

// Instrument 是 search_instrument 返回的归一形态，
// 与客户端旧实现 (lib/models/instrument.dart) 字段对齐。
type Instrument struct {
	TsCode     string `json:"ts_code"`               // 600519.SH
	Symbol     string `json:"symbol"`                // 600519
	Name       string `json:"name"`                  // 贵州茅台
	Market     string `json:"market"`                // SH / SZ / BJ / NQ
	Type       string `json:"type"`                  // stock / fund / future / index
	Industry   string `json:"industry,omitempty"`    // 行业（仅 stock）
	Area       string `json:"area,omitempty"`
	ListDate   string `json:"list_date,omitempty"`
	DelistDate string `json:"delist_date,omitempty"`
	FullName   string `json:"full_name,omitempty"`
	Multiplier float64 `json:"multiplier,omitempty"` // 期货合约乘数
	Pinyin     string `json:"pinyin,omitempty"`
}

// Candle 是一根 K 线，所有数值字段统一 float64，避免 LLM 看到 string。
type Candle struct {
	TsCode    string  `json:"ts_code"`
	TradeDate string  `json:"trade_date"` // 20240115
	Open      float64 `json:"open"`
	High      float64 `json:"high"`
	Low       float64 `json:"low"`
	Close     float64 `json:"close"`
	PreClose  float64 `json:"pre_close,omitempty"`
	Change    float64 `json:"change,omitempty"`
	PctChg    float64 `json:"pct_chg,omitempty"`
	Vol       float64 `json:"vol,omitempty"`
	Amount    float64 `json:"amount,omitempty"`
}

// Quote 是 get_quote 工具的归一形态：最新一条 + 最近 5 日变化等。
type Quote struct {
	Instrument Instrument `json:"instrument"`
	Last       *Candle    `json:"last,omitempty"`
	Recent     []Candle   `json:"recent,omitempty"`
}

// IndexComponent 指数成分股一行。
type IndexComponent struct {
	IndexCode  string  `json:"index_code"`
	ConCode    string  `json:"con_code"`
	ConName    string  `json:"con_name,omitempty"`
	Weight     float64 `json:"weight,omitempty"`
	InDate     string  `json:"in_date,omitempty"`
	OutDate    string  `json:"out_date,omitempty"`
}

// Margin 融资融券行。
type Margin struct {
	TradeDate string  `json:"trade_date"`
	Exchange  string  `json:"exchange,omitempty"`
	Rzye      float64 `json:"rzye,omitempty"`     // 融资余额
	Rzmre     float64 `json:"rzmre,omitempty"`    // 融资买入额
	Rzche     float64 `json:"rzche,omitempty"`    // 融资偿还额
	Rqye      float64 `json:"rqye,omitempty"`     // 融券余额
	Rqyl      float64 `json:"rqyl,omitempty"`     // 融券余量
	Rqmcl     float64 `json:"rqmcl,omitempty"`
}

// MoneyFlow 北向资金 / 行业资金流。
type MoneyFlow struct {
	TradeDate string  `json:"trade_date"`
	Industry  string  `json:"industry,omitempty"`
	NetAmount float64 `json:"net_amount,omitempty"`
	HghMv     float64 `json:"hgh_mv,omitempty"`     // 沪股通净买额
	SghMv     float64 `json:"sgh_mv,omitempty"`     // 深股通净买额
	BuyAmount float64 `json:"buy_amount,omitempty"`
	SellAmount float64 `json:"sell_amount,omitempty"`
}

// FinancialRow 通用财报行。利润表 / 资产负债表 / 现金流表共用字段。
//
// LLM 只关心常用字段，全字段见 Tushare 文档。Extra 透传剩余字段方便扩展。
type FinancialRow struct {
	TsCode     string                 `json:"ts_code"`
	EndDate    string                 `json:"end_date"`
	AnnDate    string                 `json:"ann_date,omitempty"`
	ReportType string                 `json:"report_type,omitempty"`
	Extra      map[string]any         `json:"extra,omitempty"`
}

// Holder 大股东 / 十大流通股东。
type Holder struct {
	TsCode    string  `json:"ts_code"`
	EndDate   string  `json:"end_date"`
	HolderName string `json:"holder_name"`
	HoldAmount float64 `json:"hold_amount,omitempty"`
	HoldRatio float64 `json:"hold_ratio,omitempty"`
}

// Dividend 分红除权一行。
type Dividend struct {
	TsCode    string  `json:"ts_code"`
	EndDate   string  `json:"end_date,omitempty"`
	AnnDate   string  `json:"ann_date,omitempty"`
	DivProc   string  `json:"div_proc,omitempty"`
	StockDivRatio float64 `json:"stk_div,omitempty"`
	CashDiv   float64 `json:"cash_div_tax,omitempty"`
	RecordDate string `json:"record_date,omitempty"`
	ExDate    string  `json:"ex_date,omitempty"`
	PayDate   string  `json:"pay_date,omitempty"`
}
