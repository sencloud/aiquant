package fishing

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/ai/weather"
)

// mkHourly 生成昨天 + n 天的逐小时序列，每小时用 f 填值。
func mkHourly(today string, n int, f func(day, hour int) weather.Hour) *weather.Hourly {
	t0, _ := time.Parse("2006-01-02", today)
	hr := &weather.Hourly{Source: "test", UTCOffset: 8 * 3600, Today: today}
	for d := -1; d < n; d++ {
		date := t0.AddDate(0, 0, d).Format("2006-01-02")
		for h := 0; h < 24; h++ {
			x := f(d, h)
			x.Time = fmt.Sprintf("%sT%02d:00", date, h)
			hr.Hours = append(hr.Hours, x)
		}
	}
	return hr
}

func calm(_, _ int) weather.Hour {
	return weather.Hour{Temp: 22, Pressure: 1013, Wind: 3, Gust: 5, Precip: 0}
}

func TestScoreIdealDay(t *testing.T) {
	// 2026-10-11 农历初一前后（新月），稳定气压、微风、22℃、零星小雨
	hr := mkHourly("2026-10-11", 3, func(d, h int) weather.Hour {
		x := calm(d, h)
		if d == 0 && h == 3 {
			x.Precip = 1
		}
		return x
	})
	ds := ScoreDays(hr, 30.27, 120.15, 3)
	if len(ds) != 3 {
		t.Fatalf("days=%d", len(ds))
	}
	d := ds[0]
	if d.Date != "2026-10-11" {
		t.Fatalf("date %s", d.Date)
	}
	sum := 0
	for _, f := range d.Factors {
		sum += f.Score
		if f.Score > f.Max || f.Score < 0 || f.Note == "" || f.Value == "" {
			t.Fatalf("bad factor %+v", f)
		}
	}
	if sum != d.Score {
		t.Fatalf("score %d != sum %d", d.Score, sum)
	}
	// 30 + 20 + 20 + 20(小雨) + 月相
	if d.Score < 90 || d.Level != "很适合" {
		t.Fatalf("ideal day score=%d level=%s factors=%+v", d.Score, d.Level, d.Factors)
	}
	if len(d.Windows) != 2 || d.Sunrise == "" || d.Sunset == "" {
		t.Fatalf("windows=%+v sunrise=%s sunset=%s", d.Windows, d.Sunrise, d.Sunset)
	}
	if !strings.HasPrefix(d.Summary, "很适合：") {
		t.Fatalf("summary %q", d.Summary)
	}
}

func TestScoreStormDay(t *testing.T) {
	hr := mkHourly("2026-10-11", 1, func(d, h int) weather.Hour {
		if d < 0 {
			return weather.Hour{Temp: 26, Pressure: 1012, Wind: 2}
		}
		return weather.Hour{Temp: 17, Pressure: 1002, Wind: 10, Gust: 18, Precip: 3}
	})
	d := ScoreDays(hr, 30.27, 120.15, 1)[0]
	if d.Level != "不太适合" {
		t.Fatalf("storm score=%d level=%s", d.Score, d.Level)
	}
	byKey := map[string]Factor{}
	for _, f := range d.Factors {
		byKey[f.Key] = f
	}
	if byKey["pressure"].Score != 8 || byKey["wind"].Score != 4 || byKey["precip"].Score != 0 {
		t.Fatalf("factors %+v", d.Factors)
	}
	if byKey["temp"].Score != 20-5 { // 17℃ 满分，骤降 9℃ 扣 5
		t.Fatalf("temp %+v", byKey["temp"])
	}
	if len(d.Warnings) != 2 {
		t.Fatalf("warnings %v", d.Warnings)
	}
	if len(d.Windows) != 0 {
		t.Fatalf("storm should have no windows: %+v", d.Windows)
	}
}

func TestScoreMissingPressureNeutral(t *testing.T) {
	hr := mkHourly("2026-10-11", 1, func(d, h int) weather.Hour {
		x := calm(d, h)
		x.Pressure = 0
		return x
	})
	d := ScoreDays(hr, 30, 120, 1)[0]
	if d.Factors[0].Score != MaxPressure/2 || d.Pressure != 0 {
		t.Fatalf("pressure factor %+v", d.Factors[0])
	}
}

func TestLevels(t *testing.T) {
	for s, want := range map[int]string{100: "很适合", 80: "很适合", 79: "适合", 65: "适合", 64: "一般", 50: "一般", 49: "不太适合"} {
		if Level(s) != want {
			t.Fatalf("Level(%d)=%s", s, Level(s))
		}
	}
}

func TestRegulationsActive(t *testing.T) {
	at := func(s string) map[string]bool {
		d, _ := ParseDate(s, time.Now())
		m := map[string]bool{}
		for _, r := range RegulationsOn(d) {
			m[r.ID] = r.Active
		}
		return m
	}
	oct := at("2026-10-11")
	if !oct["yangtze_10y"] || !oct["yellow_upper"] || oct["huai_spring"] || oct["north_summer"] || oct["yellow_lower"] {
		t.Fatalf("october %v", oct)
	}
	may := at("2026-05-20")
	for _, id := range []string{"yangtze_10y", "huai_spring", "pearl_spring", "qiantang_spring", "yellow_lower", "north_summer"} {
		if !may[id] {
			t.Fatalf("may: %s should be active", id)
		}
	}
	if at("2026-07-31")["pearl_spring"] || !at("2026-06-30")["pearl_spring"] || !at("2026-03-01")["huai_spring"] {
		t.Fatal("boundaries")
	}
	if !strings.Contains(RegulationDisclaimer, "以当地") {
		t.Fatal("disclaimer")
	}
}

type fakeWX struct {
	hr   *weather.Hourly
	geo  map[string]weather.City
	hits int
}

func (f *fakeWX) FetchHourly(_ context.Context, _, _ float64, _ int) (*weather.Hourly, error) {
	f.hits++
	return f.hr, nil
}
func (f *fakeWX) Geocode(_ context.Context, name string) (weather.City, bool, error) {
	c, ok := f.geo[name]
	return c, ok, nil
}

func TestForecastToolAndRegistry(t *testing.T) {
	wx := &fakeWX{
		hr:  mkHourly("2026-10-11", 3, calm),
		geo: map[string]weather.City{"千岛湖": {Name: "中国·浙江·千岛湖", Lat: 29.6, Lon: 119.0}},
	}
	fc := NewForecaster(wx)
	fc.Now = func() time.Time { return time.Date(2026, 10, 11, 9, 0, 0, 0, cst) }
	reg := tool.New()
	RegisterTools(reg, fc)
	if got := strings.Join(reg.Names(), ","); got != "get_fishing_forecast,get_fishing_regulations" {
		t.Fatalf("names %s", got)
	}
	out := reg.Dispatch(context.Background(), "get_fishing_forecast", `{"place":"千岛湖","days":2}`)
	var res Forecast
	if err := json.Unmarshal([]byte(out), &res); err != nil {
		t.Fatalf("%v: %s", err, out)
	}
	if res.Place != "中国·浙江·千岛湖" || len(res.Days) != 2 || res.Formula == "" || len(res.ActiveBans) != 0 {
		// 千岛湖在浙江（钱塘江 / 新安江），10 月不涉及任何全国性禁渔期，更不能提示长江 / 黄河
		t.Fatalf("res %+v", res)
	}
	// 内置城市不走地理编码
	out = reg.Dispatch(context.Background(), "get_fishing_forecast", `{"place":"杭州"}`)
	if !strings.Contains(out, "error") {
		// 杭州不在内置城市表 → geocode 未命中 → 友好错误
		t.Fatalf("expected friendly error, got %s", out)
	}
	out = reg.Dispatch(context.Background(), "get_fishing_forecast", `{"place":"北京"}`)
	if !strings.Contains(out, `"place":"北京"`) {
		t.Fatalf("builtin city: %s", out)
	}
	out = reg.Dispatch(context.Background(), "get_fishing_forecast", `{"lat":0,"lon":0}`)
	if !strings.Contains(out, "error") {
		t.Fatalf("bad coord should error: %s", out)
	}
	out = reg.Dispatch(context.Background(), "get_fishing_regulations", `{"date":"2026-05-20"}`)
	if !strings.Contains(out, "以当地渔政部门公告为准") || !strings.Contains(out, `"active":true`) {
		t.Fatalf("regs %s", out)
	}
	out = reg.Dispatch(context.Background(), "get_fishing_regulations", `{"date":"20260520"}`)
	if !strings.Contains(out, "error") {
		t.Fatalf("bad date %s", out)
	}
}
