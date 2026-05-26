// Package realtime 直接对接东方财富 push2 公开实时行情接口，
// 等价于 akshare 的 stock_zh_a_spot_em / index_realtime_em / sector_zh_em。
//
// 端点：
//   - https://push2.eastmoney.com/api/qt/clist/get   板块/全市场榜单
//   - https://push2.eastmoney.com/api/qt/stock/get   单标的快照
//   - https://push2.eastmoney.com/api/qt/ulist.np/get 多标的批量快照
//
// 字段编码（节选）：
//
//	f1=delay flag, f2=最新价(分), f3=涨跌幅(‱), f4=涨跌额(分),
//	f5=成交量(手), f6=成交额(元), f7=振幅, f8=换手率(‱),
//	f9=市盈率TTM, f10=量比, f12=代码, f13=市场, f14=名称,
//	f15=最高价(分), f16=最低价(分), f17=今开(分), f18=昨收(分),
//	f43=最新价(分,股票视图), f57=代码, f58=名称, f60=昨收(分),
//	f170=涨跌幅(‱)
//
// 价格 / 涨跌额是「分」(× 100 = 元)，涨跌幅是「万分位」(× 10000 = %)。
// 这些缩放在 toRMB / toPercent 里统一处理。
package realtime

import (
	"context"
	"net/http"
	"time"
)

// Client 持有 *http.Client；所有方法 ctx 受外部控制。
//
// 数据源策略（2026-05 起调整）：
//
//   - A 股 / ETF / 指数 / 期货实时快照 → 默认走 **新浪 hq.sinajs.cn**（更稳定）
//   - 涨跌幅榜 FetchTopMovers          → 走东方财富 push2 clist（新浪无对应接口）
//
// 东方财富 push2 的 stock/get 单点接口因风控收紧、缺失 ut/timestamp 参数等原因，
// 在生产环境频繁返回 data:null / 429，已经把核心快照路径切到新浪。
// 东财同名实现保留为 fetchSnapshotEM / fetchIndexesEM / fetchFuturesSnapshotEM /
// fetchFuturesBatchEM，可在新浪侧出问题时单测切回，不属于自动多源兜底。
type Client struct {
	httpc *http.Client
}

// New 默认 timeout 8s（新浪 / push2 国内 < 200ms，留余量）。
func New(timeoutSec int) *Client {
	if timeoutSec <= 0 {
		timeoutSec = 8
	}
	return &Client{
		httpc: &http.Client{Timeout: time.Duration(timeoutSec) * time.Second},
	}
}

// FetchSnapshot 拉单标的（A 股 / ETF / 主流指数）实时快照。
// 走新浪 hq.sinajs.cn，详见 sina_stock.go 的字段说明。
func (c *Client) FetchSnapshot(ctx context.Context, symbol string) (*Quote, error) {
	return c.fetchSinaStockSnapshot(ctx, symbol)
}

// FetchIndexes 批量拉指数实时快照（沪深 300 / 上证 50 / 中证 500 等）。
// 走新浪 hq.sinajs.cn。
func (c *Client) FetchIndexes(ctx context.Context, tsCodes []string) ([]Quote, error) {
	return c.fetchSinaIndexes(ctx, tsCodes)
}

// FetchFuturesSnapshot 拉单期货合约实时快照。
// 走新浪 hq.sinajs.cn，覆盖 CFFEX / SHFE / INE / DCE / CZCE / GFEX。
func (c *Client) FetchFuturesSnapshot(ctx context.Context, tsCode string) (*FuturesQuote, error) {
	return c.fetchSinaFuturesSnapshot(ctx, tsCode)
}

// FetchFuturesBatch 批量拉多个期货合约实时快照。
// 走新浪 hq.sinajs.cn，原生支持 list= 多 symbol，单次 HTTP 调用拿全部数据，
// 不再像东财那样需要并发调 N 次。
func (c *Client) FetchFuturesBatch(ctx context.Context, tsCodes []string) ([]FuturesQuote, error) {
	return c.fetchSinaFuturesBatch(ctx, tsCodes)
}

// toRMB 把「分」转「元」并保留 2 位。fl/分 → 0.01 元。
func toRMB(fen int64) float64 {
	if fen == 0 {
		return 0
	}
	return float64(fen) / 100.0
}

// toPercent 把「万分位」转「百分比」。f3=‱ → /100 = %。
func toPercent(wp int64) float64 {
	if wp == 0 {
		return 0
	}
	return float64(wp) / 100.0
}
