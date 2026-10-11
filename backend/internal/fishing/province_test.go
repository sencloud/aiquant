package fishing

import (
	"context"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/weather"
)

func TestProvinceAt(t *testing.T) {
	cases := []struct {
		name     string
		lat, lon float64
		want     string
	}{
		{"千岛湖", 29.61, 119.03, "浙江"},
		{"杭州", 30.27, 120.15, "浙江"},
		{"武汉", 30.59, 114.31, "湖北"},
		{"鄱阳湖", 29.10, 116.30, "江西"},
		{"上海", 31.23, 121.47, "上海"},
		{"西宁", 36.62, 101.78, "青海"},
		{"银川", 38.49, 106.23, "宁夏"},
		{"呼和浩特", 40.84, 111.75, "内蒙古"},
		{"广州", 23.13, 113.26, "广东"},
		{"南宁", 22.82, 108.37, "广西"},
		{"乌鲁木齐", 43.83, 87.62, "新疆"},
		{"北京", 39.90, 116.40, "北京"},
		{"哈尔滨", 45.80, 126.53, "黑龙江"},
		{"海口", 20.04, 110.20, "海南"},
		{"东京", 35.68, 139.69, ""},
		{"纽约", 40.71, -74.01, ""},
	}
	for _, c := range cases {
		if got := ProvinceAt(c.lat, c.lon); got != c.want {
			t.Errorf("%s (%v,%v) = %q, want %q", c.name, c.lat, c.lon, got, c.want)
		}
	}
}

func TestShortProvinceAndLabel(t *testing.T) {
	for in, want := range map[string]string{
		"浙江省": "浙江", "广西壮族自治区": "广西", "新疆维吾尔自治区": "新疆", "宁夏回族自治区": "宁夏",
		"内蒙古自治区": "内蒙古", "北京市": "北京", "香港特别行政区": "香港", "四川": "四川",
	} {
		if got := ShortProvince(in); got != want {
			t.Errorf("ShortProvince(%q) = %q, want %q", in, got, want)
		}
	}
	if got := provinceFromLabel("中国·浙江·千岛湖"); got != "浙江" {
		t.Errorf("label 浙江 = %q", got)
	}
	if got := provinceFromLabel("中国·湖北省·武汉"); got != "湖北" {
		t.Errorf("label 湖北 = %q", got)
	}
	if got := provinceFromLabel("日本·东京都·东京"); got != "" {
		t.Errorf("label 日本 = %q", got)
	}
}

func TestActiveBansFor(t *testing.T) {
	oct := time.Date(2026, 10, 11, 9, 0, 0, 0, cst)
	apr := time.Date(2026, 4, 15, 9, 0, 0, 0, cst)
	jun := time.Date(2026, 6, 1, 9, 0, 0, 0, cst)
	has := func(bans []string, sub string) bool {
		return slices.ContainsFunc(bans, func(b string) bool { return contains(b, sub) })
	}
	// 千岛湖（浙江）：10 月没有任何全国性禁渔期；春季只有钱塘江，永远不提示长江 / 黄河。
	if b := ActiveBansFor(oct, "浙江"); len(b) != 0 {
		t.Errorf("浙江 10 月 = %v, want none", b)
	}
	b := ActiveBansFor(apr, "浙江")
	if !has(b, "钱塘江") || has(b, "长江") || has(b, "黄河") {
		t.Errorf("浙江 4 月 = %v", b)
	}
	if b := ActiveBansFor(oct, "湖北"); !has(b, "长江") || has(b, "黄河") {
		t.Errorf("湖北 10 月 = %v", b)
	}
	if b := ActiveBansFor(oct, "青海"); !has(b, "长江") || !has(b, "黄河") {
		t.Errorf("青海 10 月 = %v", b)
	}
	if b := ActiveBansFor(oct, "宁夏"); len(b) != 0 {
		t.Errorf("宁夏 10 月 = %v（黄河中下游 4–7 月）", b)
	}
	if b := ActiveBansFor(jun, "广东"); !has(b, "珠江") || has(b, "长江") {
		t.Errorf("广东 6 月 = %v", b)
	}
	if b := ActiveBansFor(jun, "黑龙江"); !has(b, "松花江") {
		t.Errorf("黑龙江 6 月 = %v", b)
	}
	if b := ActiveBansFor(oct, "新疆"); len(b) != 0 {
		t.Errorf("新疆 = %v", b)
	}
	if b := ActiveBansFor(oct, ""); b != nil {
		t.Errorf("未知省份 = %v", b)
	}
}

// 每条制度都写了流经省份，且省名都能在边界数据里找到（防止写错字导致永远不提示）。
func TestRegulationProvincesKnown(t *testing.T) {
	provOnce.Do(loadProvinces)
	known := map[string]bool{}
	for _, s := range provShapes {
		known[s.name] = true
	}
	if len(known) < 34 {
		t.Fatalf("边界数据只有 %d 个省级行政区", len(known))
	}
	for _, r := range Regulations {
		if len(r.Provinces) == 0 {
			t.Errorf("%s 没写省份", r.ID)
		}
		for _, p := range r.Provinces {
			if !known[p] {
				t.Errorf("%s: 未知省份 %q", r.ID, p)
			}
		}
	}
}

type fakeWeather struct{}

func (fakeWeather) FetchHourly(context.Context, float64, float64, int) (*weather.Hourly, error) {
	return &weather.Hourly{}, nil
}
func (fakeWeather) Geocode(context.Context, string) (weather.City, bool, error) {
	return weather.City{}, false, nil
}

func TestForCoordBansByLocation(t *testing.T) {
	f := &Forecaster{W: fakeWeather{}, Now: func() time.Time { return time.Date(2026, 10, 11, 9, 0, 0, 0, cst) }}
	fc, err := f.ForCoord(context.Background(), "中国·浙江·千岛湖", 29.61, 119.03, 3)
	if err != nil {
		t.Fatal(err)
	}
	if len(fc.ActiveBans) != 0 {
		t.Errorf("千岛湖 active_bans = %v, want none（不应提示长江 / 黄河）", fc.ActiveBans)
	}
	fc, err = f.ForCoord(context.Background(), "武汉", 30.59, 114.31, 3)
	if err != nil {
		t.Fatal(err)
	}
	if len(fc.ActiveBans) != 1 || !contains(fc.ActiveBans[0], "长江") {
		t.Errorf("武汉 active_bans = %v, want 只有长江", fc.ActiveBans)
	}
}

func contains(s, sub string) bool {
	return strings.Contains(s, sub)
}
