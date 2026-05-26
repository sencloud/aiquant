package realtime

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"golang.org/x/text/encoding/simplifiedchinese"
	"golang.org/x/text/transform"
)

// tencent_common.go 封装腾讯财经 qt.gtimg.cn 的通用请求 / 响应解析。
//
// 接口形态(与新浪几乎一致,只是分隔符是 ~ 而非 ,):
//
//	GET https://qt.gtimg.cn/q=<sym1>,<sym2>,...
//	  Header 不强制(实测裸请求都能 200,WAF 比 Sina 宽松得多)
//	  Body 为 GBK 编码的若干行 JS 字面量:
//	    v_<sym>="字段1~字段2~字段3~...";
//	  不存在的标的 / 全局错误 → v_pv_none_match="1";
//
// 切换原因:阿里云 ECS 出口段在新浪 hq.sinajs.cn 的 WAF 黑名单里(社区已知),
// 腾讯 qt.gtimg.cn 政策宽松,本地 + ECS 均可达。
const (
	tencentBaseURL       = "https://qt.gtimg.cn/q="
	tencentReferer       = "https://gu.qq.com/"
	tencentUserAgent     = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
	tencentMaxBodyBytes  = 4 << 20
	tencentRequestRetry  = 2
	tencentRetryBackoff  = 200 * time.Millisecond
)

// fetchTencentList 拉一组腾讯 symbol 的实时报价。
// 返回 map[symbol]fields(已按 `~` 切分,GBK 已解码)。
// symbol 形如:sh600519 / sz000001 / sh000300。不存在的不进 map。
func (c *Client) fetchTencentList(ctx context.Context, symbols []string) (map[string][]string, error) {
	if len(symbols) == 0 {
		return nil, fmt.Errorf("tencent list: empty symbols")
	}
	url := tencentBaseURL + strings.Join(symbols, ",")

	var lastErr error
	for attempt := 0; attempt <= tencentRequestRetry; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(tencentRetryBackoff * time.Duration(attempt)):
			}
		}
		out, err := c.fetchTencentOnce(ctx, url)
		if err == nil {
			return out, nil
		}
		lastErr = err
	}
	return nil, lastErr
}

func (c *Client) fetchTencentOnce(ctx context.Context, url string) (map[string][]string, error) {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	// Header 不强制,但写全更稳:浏览器看着像从 gu.qq.com 加载脚本
	req.Header.Set("Referer", tencentReferer)
	req.Header.Set("User-Agent", tencentUserAgent)
	req.Header.Set("Accept", "*/*")
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
	// 不主动设 Accept-Encoding — 让 net/http transport 自己处理 gzip

	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("tencent http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return nil, fmt.Errorf("tencent http %d: %s", resp.StatusCode, strings.TrimSpace(string(b)))
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, tencentMaxBodyBytes))
	if err != nil {
		return nil, fmt.Errorf("tencent read: %w", err)
	}
	text, err := gbkDecode(raw)
	if err != nil {
		return nil, fmt.Errorf("tencent gbk decode: %w", err)
	}
	return parseTencentLines(text), nil
}

// parseTencentLines 把
//
//	v_sh600519="1~贵州茅台~600519~1273.38~...";
//	v_sz000001="51~平安银行~000001~10.79~...";
//	v_pv_none_match="1";   ← 整体查询无匹配(全部 symbol 都不存在)
//
// 解析为 map[symbol] = []string{fields...}。
// v_pv_none_match 行会被忽略,不会污染结果。
func parseTencentLines(text string) map[string][]string {
	out := make(map[string][]string)
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		// 形态:v_<sym>="<payload>";
		const head = "v_"
		idx := strings.Index(line, head)
		if idx < 0 {
			continue
		}
		rest := line[idx+len(head):]
		eq := strings.Index(rest, "=")
		if eq < 0 {
			continue
		}
		sym := strings.TrimSpace(rest[:eq])
		// 排除 pv_none_match 这种"全局错误标志"行
		if sym == "pv_none_match" {
			continue
		}
		payload := strings.TrimSpace(rest[eq+1:])
		payload = strings.TrimSuffix(payload, ";")
		payload = strings.TrimSpace(payload)
		payload = strings.Trim(payload, `"`)
		if payload == "" {
			// 单个标的不存在 / 已退市
			continue
		}
		out[sym] = strings.Split(payload, "~")
	}
	return out
}

// gbkDecode 把 GBK bytes 解为 UTF-8 string(腾讯 / 新浪 / 东财部分接口都用 GBK)。
func gbkDecode(b []byte) (string, error) {
	if len(b) == 0 {
		return "", nil
	}
	r := transform.NewReader(strings.NewReader(string(b)), simplifiedchinese.GBK.NewDecoder())
	dec, err := io.ReadAll(r)
	if err != nil {
		return "", err
	}
	return string(dec), nil
}

// parseFloatSafe 把 "1273.380" / "" / "0.000" 安全转 float64,解析失败返回 0。
func parseFloatSafe(s string) float64 {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	neg := false
	if strings.HasPrefix(s, "-") {
		neg = true
		s = s[1:]
	} else if strings.HasPrefix(s, "+") {
		s = s[1:]
	}
	dot := -1
	for i, ch := range s {
		if ch == '.' {
			if dot >= 0 {
				return 0
			}
			dot = i
			continue
		}
		if ch < '0' || ch > '9' {
			return 0
		}
	}
	var intPart, fracPart float64
	if dot < 0 {
		intPart = parseDigitsT(s)
	} else {
		intPart = parseDigitsT(s[:dot])
		frac := s[dot+1:]
		fracPart = parseDigitsT(frac)
		div := 1.0
		for range frac {
			div *= 10
		}
		fracPart /= div
	}
	v := intPart + fracPart
	if neg {
		v = -v
	}
	return v
}

// parseIntSafe 把 "4593162" / "12345.000" 安全转 int64(小数部分被截掉)。
func parseIntSafe(s string) int64 {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	neg := false
	if strings.HasPrefix(s, "-") {
		neg = true
		s = s[1:]
	}
	if dot := strings.Index(s, "."); dot >= 0 {
		s = s[:dot]
	}
	var n int64
	for _, ch := range s {
		if ch < '0' || ch > '9' {
			return 0
		}
		n = n*10 + int64(ch-'0')
	}
	if neg {
		return -n
	}
	return n
}

// parseDigitsT 仅取数字的 float 累加(不处理符号 / 小数点)。
func parseDigitsT(s string) float64 {
	var n float64
	for _, ch := range s {
		if ch < '0' || ch > '9' {
			return 0
		}
		n = n*10 + float64(ch-'0')
	}
	return n
}

// fieldAtT 安全取第 i 个字段,越界返回 ""。
func fieldAtT(fields []string, i int) string {
	if i < 0 || i >= len(fields) {
		return ""
	}
	return fields[i]
}
