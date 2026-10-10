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

	"github.com/rs/zerolog"
)

const (
	forecastURL = "https://api.open-meteo.com/v1/forecast"
	geocodeURL  = "https://geocoding-api.open-meteo.com/v1/search"
	metnoURL    = "https://api.met.no/weatherapi/locationforecast/2.0/compact"
)

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
	// ── 以下为 AI 工具扩充的产区（不进每日出题，见 predict.weatherDailyKeys）──
	// 棕榈油：马来西亚 + 印尼（全球约 85% 产量）
	{"my_palm_johor", "马来西亚棕榈油·柔佛", 1.9344, 103.3587, SubSoft, "棕榈油"},
	{"my_palm_pahang", "马来西亚棕榈油·彭亨", 3.8126, 103.3256, SubSoft, "棕榈油"},
	{"my_palm_sabah", "马来西亚棕榈油·沙巴", 5.4204, 117.0, SubSoft, "棕榈油"},
	{"my_palm_sarawak", "马来西亚棕榈油·砂拉越", 2.5, 112.5, SubSoft, "棕榈油"},
	{"id_palm_riau", "印尼棕榈油·廖内", 0.5071, 101.4478, SubSoft, "棕榈油"},
	{"id_palm_ssumatra", "印尼棕榈油·南苏门答腊", -3.3194, 104.9147, SubSoft, "棕榈油"},
	{"id_palm_nsumatra", "印尼棕榈油·北苏门答腊", 2.1154, 99.5451, SubSoft, "棕榈油"},
	{"id_palm_ckalimantan", "印尼棕榈油·中加里曼丹", -1.6815, 113.3824, SubSoft, "棕榈油"},
	{"id_palm_wkalimantan", "印尼棕榈油·西加里曼丹", -0.2788, 111.4753, SubSoft, "棕榈油"},
	// 天然橡胶
	{"th_rubber_south", "泰国橡胶·南部", 7.0, 100.47, SubSoft, "天然橡胶"},
	{"cn_rubber_hainan", "中国橡胶·海南", 19.2, 109.7, SubSoft, "天然橡胶"},
	{"cn_rubber_yunnan", "中国橡胶·西双版纳", 22.0, 100.8, SubSoft, "天然橡胶"},
	// 美国 / 南美谷物油籽补充
	{"us_soy_illinois", "美国大豆·伊利诺伊", 40.0, -89.0, SubGrain, "大豆/玉米"},
	{"us_corn_nebraska", "美国玉米·内布拉斯加", 41.5, -99.8, SubGrain, "玉米"},
	{"brazil_soy_parana", "巴西大豆·巴拉那", -24.5, -51.5, SubGrain, "大豆/玉米"},
	{"brazil_soy_goias", "巴西大豆·戈亚斯", -16.0, -49.5, SubGrain, "大豆"},
	{"brazil_sugar_sp", "巴西甘蔗·圣保罗", -21.5, -48.5, SubSoft, "甘蔗/原糖"},
	{"argentina_cordoba", "阿根廷·科尔多瓦", -31.4, -64.2, SubGrain, "大豆/玉米"},
	{"canada_canola", "加拿大油菜籽·萨斯喀彻温", 52.0, -106.0, SubGrain, "油菜籽"},
	{"australia_wheat_nsw", "澳大利亚小麦·新南威尔士", -33.0, 147.0, SubGrain, "小麦"},
	{"russia_wheat_south", "俄罗斯小麦·南部联邦区", 45.0, 40.0, SubGrain, "小麦"},
	{"india_soy_mp", "印度大豆·中央邦", 23.5, 77.5, SubGrain, "大豆"},
	{"thailand_sugar", "泰国甘蔗·东北部", 15.5, 102.5, SubSoft, "甘蔗/原糖"},
	{"vietnam_coffee", "越南咖啡·中部高原", 12.7, 108.0, SubSoft, "罗布斯塔咖啡"},
	// 中国主产区
	{"cn_corn_heilongjiang", "中国玉米大豆·黑龙江", 46.5, 127.5, SubGrain, "玉米/大豆"},
	{"cn_corn_jilin", "中国玉米·吉林", 43.9, 125.3, SubGrain, "玉米"},
	{"cn_wheat_henan", "中国小麦·河南", 34.0, 114.0, SubGrain, "小麦"},
	{"cn_wheat_shandong", "中国小麦·山东", 36.4, 117.0, SubGrain, "小麦/花生"},
	{"cn_cotton_xinjiang", "中国棉花·新疆", 41.2, 80.3, SubSoft, "棉花"},
	{"cn_sugar_guangxi", "中国甘蔗·广西", 22.8, 108.3, SubSoft, "甘蔗/白糖"},
	{"cn_apple_shaanxi", "中国苹果·陕西", 35.5, 109.5, SubSoft, "苹果"},
	{"cn_rapeseed_hubei", "中国油菜籽·湖北", 30.6, 113.0, SubGrain, "油菜籽"},
	{"cn_hog_sichuan", "中国生猪·四川", 30.0, 104.5, SubGrain, "生猪"},
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
//
// 三个上游地址做成字段，测试里用 httptest 替换：
//   - OpenMeteoURL  主源（预报 + 近期实况）
//   - MetNoURL      备用源（挪威气象局 locationforecast，免费、需带联系方式的 UA）
//   - GeocodeURL    未内置的地名 → 经纬度（Open-Meteo geocoding）
type Client struct {
	httpc *http.Client

	OpenMeteoURL string
	MetNoURL     string
	GeocodeURL   string

	// Logger 非空时记录上游失败与备用源切换（nil = 不打日志）。
	Logger *zerolog.Logger

	mu       sync.Mutex
	cache    map[string]cacheEntry
	ttl      time.Duration
	fcCache  map[string]fcEntry
	geoCache map[string]geoEntry
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

		OpenMeteoURL: forecastURL,
		MetNoURL:     metnoURL,
		GeocodeURL:   geocodeURL,
		fcCache:      map[string]fcEntry{},
		geoCache:     map[string]geoEntry{},
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
	u := c.openMeteoBase() + "?" + q.Encode()

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
