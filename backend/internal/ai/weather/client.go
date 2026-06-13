// Package weather 对接 Open-Meteo 公开天气接口（免费、无需 API Key）。
//
// 用途：鹦鹉螺天气类预测市场的自动结算 + 每日出题。
//   - 自动结算：取「目标日」的实况(最高温/最低温/日降水)判定盘口结果；
//   - 每日出题：取「次日」预报最高温，生成温度/降水盘口。
//
// 接口：
//
//	https://api.open-meteo.com/v1/forecast?latitude=&longitude=
//	  &daily=temperature_2m_max,temperature_2m_min,precipitation_sum
//	  &past_days=7&forecast_days=3&timezone=auto
//
// past_days 覆盖近期实况(用于结算)，forecast_days 覆盖未来预报(用于出题)。
package weather

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"sync"
	"time"
)

const forecastURL = "https://api.open-meteo.com/v1/forecast"

// 结算/出题用的天气指标。
const (
	MetricTMax   = "tmax"   // 当日最高温(℃)
	MetricTMin   = "tmin"   // 当日最低温(℃)
	MetricPrecip = "precip" // 当日降水量(mm)
)

// City 是内置的热门城市经纬度。
type City struct {
	Key  string  // 稳定标识(resolve_rule 里存这个)
	Name string  // 展示名
	Lat  float64
	Lon  float64
}

// Cities 内置热门城市表（国内一线 + 主要海外城市）。
var Cities = []City{
	{"beijing", "北京", 39.9042, 116.4074},
	{"shanghai", "上海", 31.2304, 121.4737},
	{"guangzhou", "广州", 23.1291, 113.2644},
	{"shenzhen", "深圳", 22.5431, 114.0579},
	{"hangzhou", "杭州", 30.2741, 120.1551},
	{"chengdu", "成都", 30.5728, 104.0668},
	{"wuhan", "武汉", 30.5928, 114.3055},
	{"xian", "西安", 34.3416, 108.9398},
	{"chongqing", "重庆", 29.5630, 106.5516},
	{"harbin", "哈尔滨", 45.8038, 126.5350},
	{"newyork", "纽约", 40.7128, -74.0060},
	{"london", "伦敦", 51.5074, -0.1278},
	{"tokyo", "东京", 35.6762, 139.6503},
	{"singapore", "新加坡", 1.3521, 103.8198},
}

// CityByKey 按 key 查城市。
func CityByKey(key string) (City, bool) {
	for _, c := range Cities {
		if c.Key == key {
			return c, true
		}
	}
	return City{}, false
}

// Daily 一天的天气聚合。
type Daily struct {
	Date   string  `json:"date"`
	TMax   float64 `json:"tmax"`
	TMin   float64 `json:"tmin"`
	Precip float64 `json:"precip"`
}

// Client 持有 *http.Client + 短 TTL 缓存（按经纬度去重，吸收高频重复请求）。
type Client struct {
	httpc *http.Client

	mu    sync.Mutex
	cache map[string]cacheEntry
	ttl   time.Duration
}

type cacheEntry struct {
	at   time.Time
	data map[string]Daily
}

// New 默认 timeout 8s、缓存 TTL 10 分钟。
func New(timeoutSec int) *Client {
	if timeoutSec <= 0 {
		timeoutSec = 8
	}
	return &Client{
		httpc: &http.Client{Timeout: time.Duration(timeoutSec) * time.Second},
		cache: map[string]cacheEntry{},
		ttl:   10 * time.Minute,
	}
}

// FetchDaily 拉某坐标近 7 天 + 未来 3 天的逐日天气，返回按日期(YYYY-MM-DD)索引的 map。
func (c *Client) FetchDaily(ctx context.Context, lat, lon float64) (map[string]Daily, error) {
	key := strconv.FormatFloat(lat, 'f', 4, 64) + "," + strconv.FormatFloat(lon, 'f', 4, 64)

	c.mu.Lock()
	if e, ok := c.cache[key]; ok && time.Since(e.at) < c.ttl {
		c.mu.Unlock()
		return e.data, nil
	}
	c.mu.Unlock()

	q := url.Values{}
	q.Set("latitude", strconv.FormatFloat(lat, 'f', 4, 64))
	q.Set("longitude", strconv.FormatFloat(lon, 'f', 4, 64))
	q.Set("daily", "temperature_2m_max,temperature_2m_min,precipitation_sum")
	q.Set("past_days", "7")
	q.Set("forecast_days", "3")
	q.Set("timezone", "auto")
	u := forecastURL + "?" + q.Encode()

	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("User-Agent", "finme-backend")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("open-meteo http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("open-meteo status %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	var r struct {
		Daily struct {
			Time   []string  `json:"time"`
			TMax   []float64 `json:"temperature_2m_max"`
			TMin   []float64 `json:"temperature_2m_min"`
			Precip []float64 `json:"precipitation_sum"`
		} `json:"daily"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("open-meteo parse: %w", err)
	}
	out := make(map[string]Daily, len(r.Daily.Time))
	for i, day := range r.Daily.Time {
		d := Daily{Date: day}
		if i < len(r.Daily.TMax) {
			d.TMax = r.Daily.TMax[i]
		}
		if i < len(r.Daily.TMin) {
			d.TMin = r.Daily.TMin[i]
		}
		if i < len(r.Daily.Precip) {
			d.Precip = r.Daily.Precip[i]
		}
		out[day] = d
	}

	c.mu.Lock()
	c.cache[key] = cacheEntry{at: time.Now(), data: out}
	c.mu.Unlock()
	return out, nil
}

// MetricValue 取某城市某日的指定指标值。date 为 YYYY-MM-DD。
func (c *Client) MetricValue(ctx context.Context, lat, lon float64, date, metric string) (float64, bool, error) {
	daily, err := c.FetchDaily(ctx, lat, lon)
	if err != nil {
		return 0, false, err
	}
	d, ok := daily[date]
	if !ok {
		return 0, false, nil
	}
	switch metric {
	case MetricTMax:
		return d.TMax, true, nil
	case MetricTMin:
		return d.TMin, true, nil
	case MetricPrecip:
		return d.Precip, true, nil
	default:
		return 0, false, fmt.Errorf("unknown weather metric %q", metric)
	}
}
