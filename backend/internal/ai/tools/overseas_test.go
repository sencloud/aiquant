package tools

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/sencloud/finme-backend/internal/ai/weather"
)

func TestRegionWeatherToolResolvesFreeTextAndSplitsForecast(t *testing.T) {
	om := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"utc_offset_seconds":0,"daily":{
 "time":["2000-01-01","2000-01-02","2999-01-01","2999-01-02"],
 "temperature_2m_max":[30,31,36,29],"temperature_2m_min":[22,23,24,21],
 "precipitation_sum":[5,0,0.2,12]}}`))
	}))
	defer om.Close()
	geo := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{}`))
	}))
	defer geo.Close()
	wx := weather.New(5)
	wx.OpenMeteoURL = om.URL
	wx.GeocodeURL = geo.URL
	wx.MetNoURL = om.URL

	tl := &getRegionWeatherTool{w: wx}
	out, err := tl.Run(context.Background(), json.RawMessage(`{"keys":["马来·柔佛州","印尼·廖内","火星基地"],"days":7}`))
	if err != nil {
		t.Fatal(err)
	}
	var r struct {
		OK         int      `json:"ok"`
		Unresolved []string `json:"unresolved"`
		Places     []struct {
			Key      string           `json:"key"`
			Recent   []map[string]any `json:"recent"`
			Forecast []map[string]any `json:"forecast"`
			HotDays  int              `json:"hot_days"`
			Precip   float64          `json:"precip_total"`
		} `json:"places"`
	}
	if err := json.Unmarshal([]byte(out), &r); err != nil {
		t.Fatalf("%v: %s", err, out)
	}
	if r.OK != 2 || len(r.Places) != 2 || r.Places[0].Key != "my_palm_johor" || r.Places[1].Key != "id_palm_riau" {
		t.Fatalf("unexpected places: %s", out)
	}
	if len(r.Unresolved) != 1 || r.Unresolved[0] != "火星基地" {
		t.Fatalf("unresolved: %v", r.Unresolved)
	}
	p := r.Places[0]
	if len(p.Recent) != 2 || len(p.Forecast) != 2 || p.HotDays != 1 || p.Precip != 12.2 {
		t.Fatalf("split wrong: %+v", p)
	}

	// 全都解析不了：返回 error + 可用 key 列表，而不是一句干巴巴的「没有匹配」。
	out, _ = tl.Run(context.Background(), json.RawMessage(`{"keys":["火星基地"]}`))
	if !strings.Contains(out, "available") || !strings.Contains(out, "my_palm_johor") {
		t.Fatalf("want hint list: %s", out)
	}
}
