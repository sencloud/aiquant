package weather

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestResolveAliasesFromProductionFailures(t *testing.T) {
	// 线上真实失败的入参：模型自拟的「马来·柔佛州」「印尼·廖内」等。
	cases := map[string]string{
		"马来·柔佛州":       "my_palm_johor",
		"印尼·廖内":        "id_palm_riau",
		"马来·沙捞越":       "my_palm_sarawak",
		"印尼·南苏门答腊":     "id_palm_ssumatra",
		"us_corn_belt": "us_corn_belt",
		"美国玉米带·爱荷华":    "us_corn_belt",
		"黑龙江":          "cn_corn_heilongjiang",
		"Johor":        "my_palm_johor",
	}
	for in, want := range cases {
		got := Resolve(in)
		if len(got) != 1 || got[0].Key != want {
			t.Errorf("Resolve(%q) = %v, want %s", in, keys(got), want)
		}
	}
	palm := Resolve("棕榈油主产区")
	if len(palm) < 4 {
		t.Fatalf("crop expansion: got %v", keys(palm))
	}
	if Resolve("火星基地") != nil {
		t.Fatal("unknown place should not resolve")
	}
}

func keys(cs []City) []string {
	out := []string{}
	for _, c := range cs {
		out = append(out, c.Key)
	}
	return out
}

const omBody = `{"utc_offset_seconds":28800,"daily":{
 "time":["2026-10-08","2026-10-09","2026-10-10","2026-10-11","2026-10-12"],
 "temperature_2m_max":[31.2,30.1,29.5,32.0,null],
 "temperature_2m_min":[24.0,23.5,23.1,24.2,null],
 "precipitation_sum":[12.5,0.0,3.2,null,null]}}`

func TestFetchForecastOpenMeteo(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("forecast_days") != "5" || r.URL.Query().Get("past_days") != "2" {
			t.Errorf("unexpected query %s", r.URL.RawQuery)
		}
		_, _ = w.Write([]byte(omBody))
	}))
	defer srv.Close()
	c := New(5)
	c.OpenMeteoURL = srv.URL
	c.MetNoURL = "http://127.0.0.1:1/unused"
	fc, err := c.FetchForecast(context.Background(), 1.9, 103.3, 5, 2)
	if err != nil {
		t.Fatal(err)
	}
	if fc.Source != "open-meteo" {
		t.Fatalf("source %s", fc.Source)
	}
	if len(fc.Days) != 4 { // 最后一天全 null 被跳过
		t.Fatalf("days %d", len(fc.Days))
	}
	if fc.Days[3].Precip != 0 {
		t.Fatalf("null precip should be 0, got %v", fc.Days[3].Precip)
	}
}

func TestFetchForecastFallsBackToMetNo(t *testing.T) {
	var omHits int
	om := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		omHits++
		w.WriteHeader(http.StatusBadGateway)
	}))
	defer om.Close()
	now := time.Now().UTC().Truncate(time.Hour)
	var sb strings.Builder
	sb.WriteString(`{"properties":{"timeseries":[`)
	for i := 0; i < 48; i++ {
		if i > 0 {
			sb.WriteString(",")
		}
		ts := now.Add(time.Duration(i) * time.Hour).Format(time.RFC3339)
		sb.WriteString(`{"time":"` + ts + `","data":{"instant":{"details":{"air_temperature":` +
			[]string{"20", "30"}[i%2] + `}},"next_1_hours":{"details":{"precipitation_amount":0.5}}}}`)
	}
	sb.WriteString(`]}}`)
	metHits := 0
	met := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		metHits++
		if !strings.Contains(r.UserAgent(), "finme-backend") {
			t.Errorf("met.no requires identifying UA, got %q", r.UserAgent())
		}
		_, _ = w.Write([]byte(sb.String()))
	}))
	defer met.Close()

	c := New(5)
	c.OpenMeteoURL = om.URL
	c.MetNoURL = met.URL
	fc, err := c.FetchForecast(context.Background(), 1.9, 103.3, 7, 0)
	if err != nil {
		t.Fatal(err)
	}
	if fc.Source != "met.no" || omHits != 2 || metHits != 1 {
		t.Fatalf("source=%s omHits=%d metHits=%d", fc.Source, omHits, metHits)
	}
	if len(fc.Days) < 2 {
		t.Fatalf("days %d", len(fc.Days))
	}
	var total float64
	for _, d := range fc.Days {
		if d.TMax < d.TMin {
			t.Fatalf("bad agg %+v", d)
		}
		total += d.Precip
	}
	if total < 23 || total > 25 { // 48 小时 × 0.5mm
		t.Fatalf("precip total %v", total)
	}
	// 第二次命中缓存，不再请求上游。
	if _, err := c.FetchForecast(context.Background(), 1.9, 103.3, 7, 0); err != nil || metHits != 1 {
		t.Fatalf("cache miss: err=%v metHits=%d", err, metHits)
	}
}

func TestFetchForecastAllFail(t *testing.T) {
	bad := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer bad.Close()
	c := New(5)
	c.OpenMeteoURL = bad.URL
	c.MetNoURL = bad.URL
	_, err := c.FetchForecast(context.Background(), 0, 0, 3, 0)
	if err == nil || !strings.Contains(err.Error(), "open-meteo") || !strings.Contains(err.Error(), "met.no") {
		t.Fatalf("want combined error, got %v", err)
	}
}

func TestGeocode(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("name") == "宋卡" {
			_, _ = w.Write([]byte(`{"results":[{"name":"宋卡","latitude":7.19,"longitude":100.59,"country":"泰国","admin1":"宋卡府"}]}`))
			return
		}
		_, _ = w.Write([]byte(`{}`))
	}))
	defer srv.Close()
	c := New(5)
	c.GeocodeURL = srv.URL
	city, ok, err := c.Geocode(context.Background(), "宋卡")
	if err != nil || !ok || city.Lat != 7.19 || !strings.Contains(city.Name, "泰国") {
		t.Fatalf("geocode: %+v ok=%v err=%v", city, ok, err)
	}
	if _, ok, _ := c.Geocode(context.Background(), "不存在"); ok {
		t.Fatal("expected miss")
	}
}
