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

// sina_common.go 封装新浪 hq.sinajs.cn 的通用请求 / 响应解析逻辑。
//
// 接口形态：
//
//	GET https://hq.sinajs.cn/list=<sym1>,<sym2>,...
//	  Header 必须带 Referer: https://finance.sina.com.cn/
//	  Body 为 GBK 编码的若干行 JavaScript 字面量：
//	    var hq_str_<sym>="字段1,字段2,字段3,...";
//	  标的不存在 / 已退市时该行 = "";（空字符串）。
//
// 接口稳定度极高（akshare/Tushare/同花顺多年都直连），几乎没有限流。
// 加 2 次重试 + 200ms 退避，纯网络抖动容错，不属于"数据源兜底"。

const (
	sinaBaseURL       = "https://hq.sinajs.cn/list="
	sinaReferer       = "https://finance.sina.com.cn/"
	sinaUserAgent     = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
	sinaMaxBodyBytes  = 4 << 20 // 4MB，足够数百个标的
	sinaRequestRetry  = 2       // 总尝试次数 = 1 + retry
	sinaRetryBackoff  = 200 * time.Millisecond
)

// fetchSinaList 拉一组新浪 symbol 的实时报价。返回 map[symbol]fields（已切分）。
//
// symbol 形如：sh600519 / sz000001 / s_sh000300 / nf_RB2610。
// 不存在的 symbol 不会进 map。
func (c *Client) fetchSinaList(ctx context.Context, symbols []string) (map[string][]string, error) {
	if len(symbols) == 0 {
		return nil, fmt.Errorf("sina list: empty symbols")
	}
	url := sinaBaseURL + strings.Join(symbols, ",")

	var lastErr error
	for attempt := 0; attempt <= sinaRequestRetry; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(sinaRetryBackoff * time.Duration(attempt)):
			}
		}
		out, err := c.fetchSinaOnce(ctx, url)
		if err == nil {
			return out, nil
		}
		lastErr = err
	}
	return nil, lastErr
}

func (c *Client) fetchSinaOnce(ctx context.Context, url string) (map[string][]string, error) {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	req.Header.Set("Referer", sinaReferer)
	req.Header.Set("User-Agent", sinaUserAgent)
	req.Header.Set("Accept", "*/*")
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")

	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("sina http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return nil, fmt.Errorf("sina http %d: %s", resp.StatusCode, string(b))
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, sinaMaxBodyBytes))
	if err != nil {
		return nil, fmt.Errorf("sina read: %w", err)
	}
	text, err := gbkToUTF8(raw)
	if err != nil {
		return nil, fmt.Errorf("sina gbk decode: %w", err)
	}
	return parseSinaLines(text), nil
}

// gbkToUTF8 把新浪返回的 GBK bytes 解为 UTF-8 string。
func gbkToUTF8(b []byte) (string, error) {
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

// parseSinaLines 把
//
//	var hq_str_sh600519="贵州茅台,1273.380,...";
//	var hq_str_nf_IF2606="4847.0,4902.4,...";
//
// 解析为 map[symbol] = []string{字段列表}。空字符串行 ("") 被丢弃。
func parseSinaLines(text string) map[string][]string {
	out := make(map[string][]string)
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		// 形态：var hq_str_<sym>="<payload>";
		const head = "var hq_str_"
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
		payload := strings.TrimSpace(rest[eq+1:])
		payload = strings.TrimSuffix(payload, ";")
		payload = strings.TrimSpace(payload)
		payload = strings.Trim(payload, `"`)
		if payload == "" {
			// 标的不存在 / 已退市
			continue
		}
		out[sym] = strings.Split(payload, ",")
	}
	return out
}

// sinaParseFloat 把 "1273.380" / "" / "0.000" 安全转 float64。
func sinaParseFloat(s string) float64 {
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
		intPart = parseDigits(s)
	} else {
		intPart = parseDigits(s[:dot])
		frac := s[dot+1:]
		fracPart = parseDigits(frac)
		// 缩放到小数
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

// sinaParseInt 把 "4593162" 安全转 int64。
func sinaParseInt(s string) int64 {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	neg := false
	if strings.HasPrefix(s, "-") {
		neg = true
		s = s[1:]
	}
	// 兼容 "12345.000" 这种当 int 用
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

func parseDigits(s string) float64 {
	var n float64
	for _, ch := range s {
		if ch < '0' || ch > '9' {
			return 0
		}
		n = n*10 + float64(ch-'0')
	}
	return n
}

// sinaFieldAt 安全取第 i 个字段，越界返回 ""。
func sinaFieldAt(fields []string, i int) string {
	if i < 0 || i >= len(fields) {
		return ""
	}
	return fields[i]
}
