package weather

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Hour 是某地点一个小时的天气（当地时间）。
//
// 钓鱼「出钓指数」要看气压趋势、风、气温和降水，逐日数据不够，所以单独取逐小时。
type Hour struct {
	Time     string  `json:"time"`     // 当地时间 YYYY-MM-DDTHH:00
	Temp     float64 `json:"temp"`     // ℃
	Pressure float64 `json:"pressure"` // 海平面气压 hPa（0 = 上游没给）
	Wind     float64 `json:"wind"`     // 10m 风速 m/s
	Gust     float64 `json:"gust"`     // 阵风 m/s（0 = 上游没给）
	Precip   float64 `json:"precip"`   // 该小时降水 mm
	Cloud    float64 `json:"cloud"`    // 云量 %
}

// Hourly 是逐小时序列：包含昨天（用于算气压 24h 变化）+ 未来若干天。
type Hourly struct {
	Source    string `json:"source"`     // open-meteo / met.no
	UTCOffset int    `json:"utc_offset"` // 秒
	Today     string `json:"today"`      // 当地「今天」
	Hours     []Hour `json:"hours"`
}

type hrEntry struct {
	at time.Time
	hr *Hourly
}

// FetchHourly 取某坐标「昨天 + 未来 days 天」的逐小时天气。
//
// 主源 Open-Meteo（重试一次），失败退到 MET Norway（没有昨天的实况，气压趋势
// 只能从未来序列里算）。结果按坐标缓存 TTL（默认 10 分钟）。
func (c *Client) FetchHourly(ctx context.Context, lat, lon float64, days int) (*Hourly, error) {
	if days <= 0 {
		days = 3
	}
	if days > 7 {
		days = 7
	}
	key := fmt.Sprintf("%.3f,%.3f,%d", lat, lon, days)
	c.mu.Lock()
	if c.hrCache == nil {
		c.hrCache = map[string]hrEntry{}
	}
	if e, ok := c.hrCache[key]; ok && time.Since(e.at) < c.ttl {
		c.mu.Unlock()
		return e.hr, nil
	}
	c.mu.Unlock()

	var errs []string
	var hr *Hourly
	for attempt := 0; attempt < 2 && hr == nil; attempt++ {
		h, err := c.fetchOpenMeteoHourly(ctx, lat, lon, days)
		if err == nil {
			hr = h
			break
		}
		errs = append(errs, err.Error())
		if ctx.Err() != nil {
			break
		}
	}
	if hr == nil && ctx.Err() == nil {
		h, err := c.fetchMetNoHourly(ctx, lat, lon, days)
		if err == nil {
			hr = h
		} else {
			errs = append(errs, err.Error())
		}
	}
	if hr == nil {
		if ctx.Err() != nil {
			errs = append(errs, ctx.Err().Error())
		}
		err := errors.New("weather: hourly providers failed: " + strings.Join(errs, "; "))
		if c.Logger != nil {
			c.Logger.Warn().Err(err).Float64("lat", lat).Float64("lon", lon).Msg("weather: hourly failed")
		}
		return nil, err
	}
	if len(errs) > 0 && c.Logger != nil {
		c.Logger.Warn().Strs("errors", errs).Str("used", hr.Source).Msg("weather: hourly primary failed, used fallback")
	}
	c.mu.Lock()
	c.hrCache[key] = hrEntry{at: time.Now(), hr: hr}
	c.mu.Unlock()
	return hr, nil
}

func (c *Client) fetchOpenMeteoHourly(ctx context.Context, lat, lon float64, days int) (*Hourly, error) {
	q := url.Values{}
	q.Set("latitude", strconv.FormatFloat(lat, 'f', 4, 64))
	q.Set("longitude", strconv.FormatFloat(lon, 'f', 4, 64))
	q.Set("hourly", "temperature_2m,pressure_msl,wind_speed_10m,wind_gusts_10m,precipitation,cloud_cover")
	q.Set("wind_speed_unit", "ms")
	q.Set("past_days", "1")
	q.Set("forecast_days", strconv.Itoa(days))
	q.Set("timezone", "auto")
	body, err := c.get(ctx, c.openMeteoBase()+"?"+q.Encode(), "finme-backend")
	if err != nil {
		return nil, fmt.Errorf("open-meteo hourly: %w", err)
	}
	var r struct {
		UTCOffset int `json:"utc_offset_seconds"`
		Hourly    struct {
			Time     []string   `json:"time"`
			Temp     []*float64 `json:"temperature_2m"`
			Pressure []*float64 `json:"pressure_msl"`
			Wind     []*float64 `json:"wind_speed_10m"`
			Gust     []*float64 `json:"wind_gusts_10m"`
			Precip   []*float64 `json:"precipitation"`
			Cloud    []*float64 `json:"cloud_cover"`
		} `json:"hourly"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("open-meteo hourly parse: %w", err)
	}
	if len(r.Hourly.Time) == 0 {
		return nil, errors.New("open-meteo hourly: empty series")
	}
	at := func(xs []*float64, i int) (float64, bool) {
		if i < len(xs) && xs[i] != nil {
			return *xs[i], true
		}
		return 0, false
	}
	out := &Hourly{
		Source:    "open-meteo",
		UTCOffset: r.UTCOffset,
		Today:     time.Now().UTC().Add(time.Duration(r.UTCOffset) * time.Second).Format("2006-01-02"),
	}
	for i, t := range r.Hourly.Time {
		temp, ok := at(r.Hourly.Temp, i)
		if !ok {
			continue
		}
		h := Hour{Time: t, Temp: temp}
		h.Pressure, _ = at(r.Hourly.Pressure, i)
		h.Wind, _ = at(r.Hourly.Wind, i)
		h.Gust, _ = at(r.Hourly.Gust, i)
		h.Precip, _ = at(r.Hourly.Precip, i)
		h.Cloud, _ = at(r.Hourly.Cloud, i)
		out.Hours = append(out.Hours, h)
	}
	if len(out.Hours) == 0 {
		return nil, errors.New("open-meteo hourly: all values null")
	}
	return out, nil
}

// fetchMetNoHourly 用 MET Norway 的 complete 预报（带气压、风、云量）。
// 当地时间按经度近似（每 15° 一小时）。
func (c *Client) fetchMetNoHourly(ctx context.Context, lat, lon float64, days int) (*Hourly, error) {
	base := c.MetNoURL
	if base == "" {
		base = metnoURL
	}
	// compact 已含气压 / 风 / 云量；不另外请求 complete。
	u := fmt.Sprintf("%s?lat=%.4f&lon=%.4f", base, lat, lon)
	body, err := c.get(ctx, u, metnoUserAgent)
	if err != nil {
		return nil, fmt.Errorf("met.no hourly: %w", err)
	}
	var r struct {
		Properties struct {
			Timeseries []struct {
				Time string `json:"time"`
				Data struct {
					Instant struct {
						Details struct {
							T     *float64 `json:"air_temperature"`
							P     *float64 `json:"air_pressure_at_sea_level"`
							Wind  *float64 `json:"wind_speed"`
							Gust  *float64 `json:"wind_speed_of_gust"`
							Cloud *float64 `json:"cloud_area_fraction"`
						} `json:"details"`
					} `json:"instant"`
					Next1h *struct {
						Details struct {
							P *float64 `json:"precipitation_amount"`
						} `json:"details"`
					} `json:"next_1_hours"`
				} `json:"data"`
			} `json:"timeseries"`
		} `json:"properties"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("met.no hourly parse: %w", err)
	}
	offset := time.Duration(math.Round(lon/15)) * time.Hour
	out := &Hourly{
		Source:    "met.no",
		UTCOffset: int(offset / time.Second),
		Today:     time.Now().UTC().Add(offset).Format("2006-01-02"),
	}
	limit := time.Now().UTC().Add(time.Duration(days) * 24 * time.Hour)
	v := func(p *float64) float64 {
		if p == nil {
			return 0
		}
		return *p
	}
	for _, ts := range r.Properties.Timeseries {
		t, err := time.Parse(time.RFC3339, ts.Time)
		if err != nil || t.After(limit) {
			continue
		}
		d := ts.Data.Instant.Details
		if d.T == nil {
			continue
		}
		h := Hour{
			Time:     t.Add(offset).Format("2006-01-02T15:04"),
			Temp:     *d.T,
			Pressure: v(d.P),
			Wind:     v(d.Wind),
			Gust:     v(d.Gust),
			Cloud:    v(d.Cloud),
		}
		if n := ts.Data.Next1h; n != nil {
			h.Precip = v(n.Details.P)
		}
		out.Hours = append(out.Hours, h)
	}
	if len(out.Hours) == 0 {
		return nil, errors.New("met.no hourly: empty timeseries")
	}
	return out, nil
}
