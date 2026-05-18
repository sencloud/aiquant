package news

import (
	"net/http"
	"time"

	"github.com/sencloud/finme-backend/internal/platform"
)

// Client 是 GDELT / Google News / FIRMS 三个数据源的合并 client。
//
// 共享同一个 *http.Client（连接复用），按数据源拆方法。
type Client struct {
	cfg   platform.NewsConfig
	httpc *http.Client
}

// New 构造 Client。所有 URL / key 走 cfg；零值 URL 在调用方法时会回退到默认 URL。
func New(cfg platform.NewsConfig) *Client {
	timeout := cfg.TimeoutSec
	if timeout <= 0 {
		timeout = 20
	}
	if cfg.GdeltBaseURL == "" {
		cfg.GdeltBaseURL = "https://api.gdeltproject.org/api/v2/doc/doc"
	}
	if cfg.GoogleRSSBase == "" {
		cfg.GoogleRSSBase = "https://news.google.com/rss/search"
	}
	if cfg.FirmsBaseURL == "" {
		cfg.FirmsBaseURL = "https://firms.modaps.eosdis.nasa.gov/api/area/csv"
	}
	return &Client{
		cfg:   cfg,
		httpc: &http.Client{Timeout: time.Duration(timeout) * time.Second},
	}
}

// FirmsConfigured 用于工具 Run 时的 fail-fast 检查。
func (c *Client) FirmsConfigured() bool { return c.cfg.FirmsMapKey != "" }
