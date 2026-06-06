// Package realtime 直接对接东方财富 push2 公开实时行情接口，
// 等价于 akshare 的 stock_zh_a_spot_em / index_realtime_em / sector_zh_em。
//
// 端点：
//   - https://push2delay.eastmoney.com/api/qt/clist/get   板块/全市场榜单
//   - https://push2delay.eastmoney.com/api/qt/stock/get   单标的快照
//   - https://push2delay.eastmoney.com/api/qt/ulist.np/get 多标的批量快照
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
// 数据源策略（2026-05 第二次调整）：
//
//   - A 股 / ETF / 指数实时快照 → **腾讯 qt.gtimg.cn**(本地 / 阿里云 ECS 均稳定,WAF 宽松)
//   - 期货实时快照 / 涨跌幅榜    → **东方财富 push2delay.eastmoney.com**(腾讯无公开期货接口)
//
// 第一版用东财 push2 stock/get 跑股票快照,在生产环境频繁 data:null / 429;
// 第二版切到新浪 hq.sinajs.cn 解决稳定性,但阿里云 ECS 出口 IP 段被新浪 WAF 拉黑导致 403;
// 第三版股票切腾讯彻底绕开新浪 IP 黑名单,期货回退东财(腾讯无公开期货 API);
// 第四版(本版)东财 host 从 push2 改 push2delay:push2.eastmoney.com CNAME 到 Azure
// trafficmanager 节点,在阿里云生产出口 TLS 握手被重置(unexpected eof),
// push2delay 解析到另一组可达 IP,同一套 API、字段一致(延迟行情,可接受)。
type Client struct {
	httpc *http.Client

	// quoteCache：全球行情快照短期缓存（TTL 12s），吸收同一标的的高频重复请求。
	// secidCache：美股 symbol→secid 解析缓存（TTL 6h），符号映射基本不变。
	quoteCache *ttlCache[*GlobalQuote]
	secidCache *ttlCache[secMeta]
}

// New 默认 timeout 8s(国内接口 < 200ms,留余量)。
func New(timeoutSec int) *Client {
	if timeoutSec <= 0 {
		timeoutSec = 8
	}
	return &Client{
		httpc:      &http.Client{Timeout: time.Duration(timeoutSec) * time.Second},
		quoteCache: newTTLCache[*GlobalQuote](12 * time.Second),
		secidCache: newTTLCache[secMeta](6 * time.Hour),
	}
}

// FetchSnapshot 拉单标的(A 股 / ETF / 主流指数)实时快照。走腾讯 qt.gtimg.cn。
func (c *Client) FetchSnapshot(ctx context.Context, symbol string) (*Quote, error) {
	return c.fetchTencentStockSnapshot(ctx, symbol)
}

// FetchIndexes 批量拉指数实时快照(沪深 300 / 上证 50 / 中证 500 等)。走腾讯 qt.gtimg.cn。
func (c *Client) FetchIndexes(ctx context.Context, tsCodes []string) ([]Quote, error) {
	return c.fetchTencentIndexes(ctx, tsCodes)
}

// FetchFuturesSnapshot 拉单期货合约实时快照。走东财 push2 stock/get
// (腾讯没有公开的期货实时接口;东财此路径在生产偶尔 data:null,但已是次优选)。
func (c *Client) FetchFuturesSnapshot(ctx context.Context, tsCode string) (*FuturesQuote, error) {
	return c.fetchFuturesSnapshotEM(ctx, tsCode)
}

// FetchFuturesBatch 批量拉多个期货合约实时快照。走东财 push2。
func (c *Client) FetchFuturesBatch(ctx context.Context, tsCodes []string) ([]FuturesQuote, error) {
	return c.fetchFuturesBatchEM(ctx, tsCodes)
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
