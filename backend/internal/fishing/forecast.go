package fishing

import (
	"context"
	"errors"
	"math"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/weather"
)

// WeatherSource 是出钓指数需要的天气能力（*weather.Client 实现；测试可替换）。
type WeatherSource interface {
	FetchHourly(ctx context.Context, lat, lon float64, days int) (*weather.Hourly, error)
	Geocode(ctx context.Context, name string) (weather.City, bool, error)
}

// Forecaster 计算出钓指数。
type Forecaster struct {
	W WeatherSource
	// Now 可注入（测试）；默认 time.Now。
	Now func() time.Time
}

// NewForecaster 构造。
func NewForecaster(w WeatherSource) *Forecaster { return &Forecaster{W: w} }

// ErrPlaceNotFound 地名解析不到坐标。
var ErrPlaceNotFound = errors.New("place not found")

// ErrBadCoord 坐标非法。
var ErrBadCoord = errors.New("invalid coordinates")

// Forecast 是出钓指数的完整输出。
type Forecast struct {
	Place      string     `json:"place"`
	Lat        float64    `json:"lat"`
	Lon        float64    `json:"lon"`
	Source     string     `json:"source"`
	Days       []DayScore `json:"days"`
	Formula    string     `json:"formula"`
	Disclaimer string     `json:"disclaimer"`
	// Regulations 当天生效的全国性禁渔 / 休渔制度（只列名字，详情走 regulations 接口）。
	ActiveBans []string `json:"active_bans,omitempty"`
}

// ForecastDisclaimer 出钓指数说明。
const ForecastDisclaimer = "出钓指数只根据天气打分，鱼口还取决于水温、水色、钓点和钓法，仅供参考；雷雨、大风天请注意安全。"

// ForPlace 用地名查（内置城市表 → 地理编码）。
func (f *Forecaster) ForPlace(ctx context.Context, place string, days int) (*Forecast, error) {
	place = strings.TrimSpace(place)
	if place == "" {
		return nil, ErrPlaceNotFound
	}
	var city weather.City
	if cs := weather.Resolve(place); len(cs) == 1 && cs[0].Sub == weather.SubCity {
		city = cs[0]
	} else {
		c, ok, err := f.W.Geocode(ctx, place)
		if err != nil {
			return nil, err
		}
		if !ok {
			return nil, ErrPlaceNotFound
		}
		city = c
	}
	return f.ForCoord(ctx, city.Name, city.Lat, city.Lon, days)
}

// ForCoord 用坐标查。
func (f *Forecaster) ForCoord(ctx context.Context, name string, lat, lon float64, days int) (*Forecast, error) {
	if math.IsNaN(lat) || math.IsNaN(lon) || lat < -90 || lat > 90 || lon < -180 || lon > 180 || (lat == 0 && lon == 0) {
		return nil, ErrBadCoord
	}
	if days <= 0 {
		days = 3
	}
	if days > 7 {
		days = 7
	}
	hr, err := f.W.FetchHourly(ctx, lat, lon, days)
	if err != nil {
		return nil, err
	}
	if name == "" {
		name = "所选位置"
	}
	now := time.Now
	if f.Now != nil {
		now = f.Now
	}
	var bans []string
	for _, r := range RegulationsOn(now().In(cst)) {
		if r.Active {
			bans = append(bans, r.Name)
		}
	}
	return &Forecast{
		Place:      name,
		Lat:        math.Round(lat*1e4) / 1e4,
		Lon:        math.Round(lon*1e4) / 1e4,
		Source:     hr.Source,
		Days:       ScoreDays(hr, lat, lon, days),
		Formula:    FormulaText,
		Disclaimer: ForecastDisclaimer,
		ActiveBans: bans,
	}, nil
}

var cst = time.FixedZone("CST", 8*3600)
