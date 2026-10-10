package weather

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
)

// metnoUserAgent：api.met.no 的使用条款要求 UA 里带可联系的标识，否则 403。
const metnoUserAgent = "finme-backend/1.0 (+https://api.singzquant.com)"

// Forecast 是某地点的逐日天气，给 AI 工具用。
//
// Days 按日期升序，包含最近 PastDays 天实况 + 未来若干天预报；Today 是该地点
// 当地时区的「今天」，调用方据此把实况和预报分开。
type Forecast struct {
	Source string  `json:"source"` // open-meteo / met.no
	Today  string  `json:"today"`
	Days   []Daily `json:"days"`
}

type fcEntry struct {
	at time.Time
	fc *Forecast
}

type geoEntry struct {
	at   time.Time
	city City
	ok   bool
}

func (c *Client) openMeteoBase() string {
	if c.OpenMeteoURL != "" {
		return c.OpenMeteoURL
	}
	return forecastURL
}

// FetchForecast 取某坐标「近 pastDays 天实况 + 未来 days 天预报」。
//
// 主源 Open-Meteo（重试一次）；失败再退到 MET Norway。两个都失败才返回错误，
// 错误里带上两个源各自的原因，便于在日志里定位是哪一段网络出了问题。
func (c *Client) FetchForecast(ctx context.Context, lat, lon float64, days, pastDays int) (*Forecast, error) {
	if days <= 0 {
		days = 7
	}
	if days > 16 {
		days = 16
	}
	if pastDays < 0 {
		pastDays = 0
	}
	if pastDays > 7 {
		pastDays = 7
	}
	key := fmt.Sprintf("%.4f,%.4f,%d,%d", lat, lon, days, pastDays)
	c.mu.Lock()
	if e, ok := c.fcCache[key]; ok && time.Since(e.at) < c.ttl {
		c.mu.Unlock()
		return e.fc, nil
	}
	c.mu.Unlock()

	var errs []string
	var fc *Forecast
	for attempt := 0; attempt < 2 && fc == nil; attempt++ {
		f, err := c.fetchOpenMeteo(ctx, lat, lon, days, pastDays)
		if err == nil {
			fc = f
			break
		}
		errs = append(errs, err.Error())
		if ctx.Err() != nil {
			break
		}
	}
	if fc == nil && ctx.Err() == nil {
		f, err := c.fetchMetNo(ctx, lat, lon, days)
		if err == nil {
			fc = f
		} else {
			errs = append(errs, err.Error())
		}
	}
	if fc == nil {
		if ctx.Err() != nil {
			errs = append(errs, ctx.Err().Error())
		}
		err := errors.New("weather: all providers failed: " + strings.Join(errs, "; "))
		if c.Logger != nil {
			c.Logger.Warn().Err(err).Float64("lat", lat).Float64("lon", lon).Msg("weather: forecast failed")
		}
		return nil, err
	}
	if len(errs) > 0 && c.Logger != nil {
		c.Logger.Warn().Strs("errors", errs).Str("used", fc.Source).
			Float64("lat", lat).Float64("lon", lon).Msg("weather: primary failed, used fallback")
	}
	c.mu.Lock()
	c.fcCache[key] = fcEntry{at: time.Now(), fc: fc}
	c.mu.Unlock()
	return fc, nil
}

func (c *Client) fetchOpenMeteo(ctx context.Context, lat, lon float64, days, pastDays int) (*Forecast, error) {
	q := url.Values{}
	q.Set("latitude", strconv.FormatFloat(lat, 'f', 4, 64))
	q.Set("longitude", strconv.FormatFloat(lon, 'f', 4, 64))
	q.Set("daily", "temperature_2m_max,temperature_2m_min,precipitation_sum")
	q.Set("past_days", strconv.Itoa(pastDays))
	q.Set("forecast_days", strconv.Itoa(days))
	q.Set("timezone", "auto")
	body, err := c.get(ctx, c.openMeteoBase()+"?"+q.Encode(), "finme-backend")
	if err != nil {
		return nil, fmt.Errorf("open-meteo: %w", err)
	}
	var r struct {
		UTCOffset int `json:"utc_offset_seconds"`
		Daily     struct {
			Time   []string   `json:"time"`
			TMax   []*float64 `json:"temperature_2m_max"`
			TMin   []*float64 `json:"temperature_2m_min"`
			Precip []*float64 `json:"precipitation_sum"`
		} `json:"daily"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("open-meteo parse: %w", err)
	}
	if len(r.Daily.Time) == 0 {
		return nil, errors.New("open-meteo: empty daily series")
	}
	at := func(xs []*float64, i int) float64 {
		if i < len(xs) && xs[i] != nil {
			return *xs[i]
		}
		return math.NaN()
	}
	fc := &Forecast{
		Source: "open-meteo",
		Today:  time.Now().UTC().Add(time.Duration(r.UTCOffset) * time.Second).Format("2006-01-02"),
	}
	for i, d := range r.Daily.Time {
		tmax, tmin, p := at(r.Daily.TMax, i), at(r.Daily.TMin, i), at(r.Daily.Precip, i)
		if math.IsNaN(tmax) && math.IsNaN(tmin) {
			continue // 上游对超出模型范围的日子给 null，跳过而不是当 0℃
		}
		if math.IsNaN(p) {
			p = 0
		}
		fc.Days = append(fc.Days, Daily{Date: d, TMax: nanTo0(tmax), TMin: nanTo0(tmin), Precip: p})
	}
	if len(fc.Days) == 0 {
		return nil, errors.New("open-meteo: all values null")
	}
	return fc, nil
}

// fetchMetNo 用 MET Norway 的逐小时预报聚合成逐日（按当地经度近似时区）。
// 没有历史实况，只有未来约 9 天。
func (c *Client) fetchMetNo(ctx context.Context, lat, lon float64, days int) (*Forecast, error) {
	base := c.MetNoURL
	if base == "" {
		base = metnoURL
	}
	u := fmt.Sprintf("%s?lat=%.4f&lon=%.4f", base, lat, lon)
	body, err := c.get(ctx, u, metnoUserAgent)
	if err != nil {
		return nil, fmt.Errorf("met.no: %w", err)
	}
	var r struct {
		Properties struct {
			Timeseries []struct {
				Time string `json:"time"`
				Data struct {
					Instant struct {
						Details struct {
							T *float64 `json:"air_temperature"`
						} `json:"details"`
					} `json:"instant"`
					Next1h *struct {
						Details struct {
							P *float64 `json:"precipitation_amount"`
						} `json:"details"`
					} `json:"next_1_hours"`
					Next6h *struct {
						Details struct {
							P *float64 `json:"precipitation_amount"`
						} `json:"details"`
					} `json:"next_6_hours"`
				} `json:"data"`
			} `json:"timeseries"`
		} `json:"properties"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("met.no parse: %w", err)
	}
	// 当地日期：按经度粗略换算时区（每 15° 一小时），产区天气够用。
	offset := time.Duration(math.Round(lon/15)) * time.Hour
	type agg struct {
		tmax, tmin, precip float64
		n                  int
	}
	byDay := map[string]*agg{}
	// 降水：有 1h 的段用 1h；之后只有 6h 的段，用 6h 并跳过被覆盖的时刻。
	var coveredUntil time.Time
	for _, ts := range r.Properties.Timeseries {
		t, err := time.Parse(time.RFC3339, ts.Time)
		if err != nil {
			continue
		}
		day := t.Add(offset).Format("2006-01-02")
		a := byDay[day]
		if a == nil {
			a = &agg{tmax: math.Inf(-1), tmin: math.Inf(1)}
			byDay[day] = a
		}
		if v := ts.Data.Instant.Details.T; v != nil {
			a.tmax = math.Max(a.tmax, *v)
			a.tmin = math.Min(a.tmin, *v)
			a.n++
		}
		if t.Before(coveredUntil) {
			continue
		}
		if n := ts.Data.Next1h; n != nil && n.Details.P != nil {
			a.precip += *n.Details.P
			coveredUntil = t.Add(time.Hour)
		} else if n := ts.Data.Next6h; n != nil && n.Details.P != nil {
			a.precip += *n.Details.P
			coveredUntil = t.Add(6 * time.Hour)
		}
	}
	dates := make([]string, 0, len(byDay))
	for d, a := range byDay {
		if a.n > 0 {
			dates = append(dates, d)
		}
	}
	sort.Strings(dates)
	if len(dates) == 0 {
		return nil, errors.New("met.no: empty timeseries")
	}
	if len(dates) > days {
		dates = dates[:days]
	}
	fc := &Forecast{Source: "met.no", Today: time.Now().UTC().Add(offset).Format("2006-01-02")}
	for _, d := range dates {
		a := byDay[d]
		fc.Days = append(fc.Days, Daily{Date: d, TMax: a.tmax, TMin: a.tmin, Precip: math.Round(a.precip*10) / 10})
	}
	return fc, nil
}

// Geocode 把未内置的地名解析成坐标（Open-Meteo geocoding，免费无 key）。
// 支持中文；找不到返回 ok=false。结果缓存 24 小时。
func (c *Client) Geocode(ctx context.Context, name string) (City, bool, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return City{}, false, nil
	}
	c.mu.Lock()
	if e, ok := c.geoCache[name]; ok && time.Since(e.at) < 24*time.Hour {
		c.mu.Unlock()
		return e.city, e.ok, nil
	}
	c.mu.Unlock()

	base := c.GeocodeURL
	if base == "" {
		base = geocodeURL
	}
	q := url.Values{}
	q.Set("name", name)
	q.Set("count", "1")
	q.Set("language", "zh")
	q.Set("format", "json")
	body, err := c.get(ctx, base+"?"+q.Encode(), "finme-backend")
	if err != nil {
		return City{}, false, fmt.Errorf("geocode: %w", err)
	}
	var r struct {
		Results []struct {
			Name      string  `json:"name"`
			Latitude  float64 `json:"latitude"`
			Longitude float64 `json:"longitude"`
			Country   string  `json:"country"`
			Admin1    string  `json:"admin1"`
		} `json:"results"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return City{}, false, fmt.Errorf("geocode parse: %w", err)
	}
	var city City
	ok := len(r.Results) > 0
	if ok {
		g := r.Results[0]
		label := g.Name
		if g.Admin1 != "" && g.Admin1 != g.Name {
			label = g.Admin1 + "·" + label
		}
		if g.Country != "" {
			label = g.Country + "·" + label
		}
		city = City{
			Key:  "geo:" + name,
			Name: label,
			Lat:  g.Latitude,
			Lon:  g.Longitude,
			Sub:  SubCity,
		}
	}
	c.mu.Lock()
	c.geoCache[name] = geoEntry{at: time.Now(), city: city, ok: ok}
	c.mu.Unlock()
	return city, ok, nil
}

func (c *Client) get(ctx context.Context, u, ua string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", ua)
	req.Header.Set("Accept", "application/json")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status %d", resp.StatusCode)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 4<<20))
}

func nanTo0(v float64) float64 {
	if math.IsNaN(v) {
		return 0
	}
	return v
}
