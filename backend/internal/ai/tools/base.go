// Package tools 是把 6+8+6+4+5 = 30 个工具批量注册到统一 Registry 的入口。
//
// 每个具体工具都实现 tool.Runner，通过 BuildAll 集中装配。
package tools

import (
	"github.com/sencloud/finme-backend/internal/ai/news"
	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// Deps 把所有工具会用到的下游 client 打包，避免每个 New* 改签名。
type Deps struct {
	Tushare *tushare.Client
	News    *news.Client
}

// BuildAll 注册 X2~X6 全部 30 个工具到一个新的 Registry。
//
// 调用方负责把 Registry 注入 chat / ding 两条执行路径。
func BuildAll(d Deps) *tool.Registry {
	r := tool.New()

	// X2 — Tushare 基础 6
	registerBaseTushare(r, d.Tushare)
	// X3 — 量化 8
	registerQuant(r, d.Tushare)
	// X4 — 基本面 6
	registerFundamental(r, d.Tushare)
	// X5 — 宏观资金 4
	registerMacro(r, d.Tushare)
	// X6 — 事件 5
	registerEvent(r, d.News)

	return r
}
