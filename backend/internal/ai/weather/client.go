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

// 天气位置的子分类（与 predict 的 weather 子类字符串一致）。
const (
	SubCity  = "city"  // 城市天气
	SubGrain = "grain" // 谷物油籽产区
	SubSoft  = "soft"  // 软商品产区
)

// City 是内置的天气位置（城市 + 大宗商品产区）经纬度。
type City struct {
	Key  string  // 稳定标识(resolve_rule 里存这个)
	Name string  // 展示名
	Lat  float64
	Lon  float64
	Sub  string  // 子分类：city / grain / soft
	Crop string  // 关联作物/品种（产区用，城市为空）
}

// Cities 内置天气位置表：
//   - 大宗商品产区(grain/soft)：天气直接影响产量与期货价格，是主力出题对象；
//   - 城市(city)：保留少量一线/海外城市，丰富玩法。
var Cities = []City{
	// ── 谷物油籽产区 ──────────────────────────────────────────────
	{"us_corn_belt", "美国玉米带·爱荷华", 41.8780, -93.0977, SubGrain, "玉米/大豆"},
	{"us_wheat_kansas", "美国小麦带·堪萨斯", 38.5000, -98.0000, SubGrain, "冬小麦"},
	{"brazil_soy_mt", "巴西大豆·马托格罗索", -12.6400, -55.4200, SubGrain, "大豆"},
	{"argentina_pampas", "阿根廷潘帕斯", -34.0000, -61.0000, SubGrain, "大豆/玉米"},
	{"blacksea_wheat", "黑海小麦·乌克兰", 49.0000, 32.0000, SubGrain, "小麦"},
	// ── 软商品产区 ────────────────────────────────────────────────
	{"brazil_coffee_mg", "巴西咖啡·米纳斯", -18.5000, -44.5000, SubSoft, "阿拉比卡咖啡"},
	{"ivorycoast_cocoa", "科特迪瓦可可", 6.8500, -5.3000, SubSoft, "可可"},
	{"us_cotton_texas", "美国棉花·得州", 33.5000, -101.8500, SubSoft, "棉花"},
	{"india_sugar_up", "印度糖·北方邦", 26.8500, 80.9100, SubSoft, "甘蔗/原糖"},
	// ── 城市 ──────────────────────────────────────────────────────
	{"beijing", "北京", 39.9042, 116.4074, SubCity, ""},
	{"shanghai", "上海", 31.2304, 121.4737, SubCity, ""},
	{"guangzhou", "广州", 23.1291, 113.2644, SubCity, ""},
	{"shenzhen", "深圳", 22.5431, 114.0579, SubCity, ""},
	{"chengdu", "成都", 30.5728, 104.0668, SubCity, ""},
	{"harbin", "哈尔滨", 45.8038, 126.5350, SubCity, ""},
	{"newyork", "纽约", 40.7128, -74.0060, SubCity, ""},
	{"london", "伦敦", 51.5074, -0.1278, SubCity, ""},
	{"tokyo", "东京", 35.6762, 139.6503, SubCity, ""},
	{"singapore", "新加坡", 1.3521, 103.8198, SubCity, ""},
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
