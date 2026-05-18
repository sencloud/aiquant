// Package cnnews 是面向中国大陆用户的财经新闻 / 事件聚合源。
//
// 因为 GDELT、Google News 在国内出口经常 TLS 握手失败 / context deadline，
// 这里收敛到 3 个国内可直连的公开 HTTP 接口：
//   - 财联社电报（最实时，覆盖 A 股 / 期货 / 农产品 / 政策）
//   - 东方财富 7×24 快讯
//   - 新浪滚动新闻（按 lid 分财经 / 国内 / 国际 / 综合）
//
// 全部无需 key，请求都使用 Mozilla User-Agent + 必要的 Referer。
package cnnews

import (
	"net/http"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/news"
)

// Event 直接复用 news.Event，避免上层 tools 还要做类型转换。
type Event = news.Event

// Client 是 3 个国内源的共享 HTTP client。
type Client struct {
	httpc *http.Client
}

// New 构造 Client。timeout 默认 12s（cls/eastmoney 偶尔 > 5s）。
func New(timeoutSec int) *Client {
	if timeoutSec <= 0 {
		timeoutSec = 12
	}
	return &Client{
		httpc: &http.Client{Timeout: time.Duration(timeoutSec) * time.Second},
	}
}
