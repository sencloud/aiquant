// Package tools 是把所有 AI 工具批量注册到统一 Registry 的入口。
//
// 每个具体工具都实现 tool.Runner，通过 BuildAll 集中装配。
//
// 数据源分工：
//   - Tushare：A 股 / 期货历史日线、分钟、财报、行业资金、北向、两融
//   - Realtime（腾讯 + 东财 push2delay）：A 股/期货实时快照、涨跌幅榜，
//     以及美股 / 全球指数 / 外汇实时（均走东财 push2delay stock/get）
//   - CNNews（财联社+东财快讯+新浪滚动）：国内中文财经/期货/政策电报
//   - News（GDELT+FIRMS）：海外议题、卫星火点
package tools

import (
	"github.com/sencloud/finme-backend/internal/ai/cnnews"
	"github.com/sencloud/finme-backend/internal/ai/news"
	"github.com/sencloud/finme-backend/internal/ai/realtime"
	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// Deps 把所有工具会用到的下游 client 打包，避免每个 New* 改签名。
type Deps struct {
	Tushare  *tushare.Client
	News     *news.Client
	CNNews   *cnnews.Client
	Realtime *realtime.Client
}

// BuildAll 注册全部工具到一个新的 Registry。
//
// 调用方负责把 Registry 注入 chat / ding 两条执行路径。
func BuildAll(d Deps) *tool.Registry {
	r := tool.New()

	registerBaseTushare(r, d.Tushare)
	registerQuant(r, d.Tushare)
	registerFundamental(r, d.Tushare)
	registerMacro(r, d.Tushare)
	registerEvent(r, d.News, d.CNNews)
	registerRealtime(r, d.Realtime)
	registerGlobal(r, d.Realtime)
	registerBacktest(r, d.Tushare)
	registerOptions(r, d.Tushare)
	registerDominant(r, d.Tushare)

	return r
}
