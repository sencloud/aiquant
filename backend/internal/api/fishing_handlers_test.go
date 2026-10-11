package api

import (
	"context"
	"encoding/base64"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/weather"
	"github.com/sencloud/finme-backend/internal/fishing"
)

type stubWeather struct{}

func (stubWeather) FetchHourly(_ context.Context, _, _ float64, days int) (*weather.Hourly, error) {
	today := time.Now().In(time.FixedZone("CST", 8*3600))
	hr := &weather.Hourly{Source: "stub", UTCOffset: 8 * 3600, Today: today.Format("2006-01-02")}
	for d := -1; d < days; d++ {
		date := today.AddDate(0, 0, d).Format("2006-01-02")
		for h := 0; h < 24; h++ {
			hr.Hours = append(hr.Hours, weather.Hour{Time: fmt.Sprintf("%sT%02d:00", date, h),
				Temp: 20, Pressure: 1013, Wind: 3, Gust: 5})
		}
	}
	return hr, nil
}

func (stubWeather) Geocode(_ context.Context, name string) (weather.City, bool, error) {
	if name == "千岛湖" {
		return weather.City{Name: "中国·浙江·千岛湖", Lat: 29.6, Lon: 119.0}, true, nil
	}
	return weather.City{}, false, nil
}

type stubVision struct{ fail bool }

func (stubVision) Configured() bool { return true }
func (v stubVision) ImageJSON(_ context.Context, _, _, _ string, out any) error {
	if v.fail {
		return fmt.Errorf("boom")
	}
	*(out.(*fishing.IdentifyResult)) = fishing.IdentifyResult{IsFish: true,
		Candidates: []fishing.Candidate{{Name: "鲫鱼", Confidence: 0.9}}}
	return nil
}

func newFishingEnv(t *testing.T, v fishing.Vision) *testEnv {
	return newTestEnvWith(t, func(d *Deps) {
		d.Fishing = fishing.NewService(d.Store, stubWeather{}, v, nil)
	})
}

func TestFishingPublicEndpoints(t *testing.T) {
	e := newFishingEnv(t, stubVision{})
	rec, out := e.do(t, http.MethodGet, "/v1/fishing/forecast?place=千岛湖&days=2", "", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("forecast %d %s", rec.Code, rec.Body.String())
	}
	if days, _ := out["days"].([]any); len(days) != 2 || out["formula"] == "" {
		t.Fatalf("forecast body %v", out)
	}
	rec, _ = e.do(t, http.MethodGet, "/v1/fishing/forecast?lat=30.2&lon=120.1", "", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("coord %d", rec.Code)
	}
	for path, want := range map[string]int{
		"/v1/fishing/forecast":                    http.StatusBadRequest,
		"/v1/fishing/forecast?place=火星基地":         http.StatusNotFound,
		"/v1/fishing/forecast?lat=abc&lon=1":      http.StatusBadRequest,
		"/v1/fishing/forecast?lat=95&lon=1":       http.StatusBadRequest,
		"/v1/fishing/regulations?date=bad":        http.StatusBadRequest,
		"/v1/fishing/regulations?date=2026-05-20": http.StatusOK,
	} {
		if rec, _ := e.do(t, http.MethodGet, path, "", nil); rec.Code != want {
			t.Fatalf("%s = %d want %d (%s)", path, rec.Code, want, rec.Body.String())
		}
	}
	_, out = e.do(t, http.MethodGet, "/v1/fishing/regulations", "", nil)
	if !strings.Contains(fmt.Sprint(out["disclaimer"]), "以当地渔政部门公告为准") {
		t.Fatalf("regs %v", out)
	}
}

func TestFishingPrivateEndpointsRequireAuth(t *testing.T) {
	e := newFishingEnv(t, stubVision{})
	for _, c := range []struct{ m, p string }{
		{http.MethodPost, "/v1/fishing/identify"},
		{http.MethodGet, "/v1/fishing/catches"},
		{http.MethodPost, "/v1/fishing/catches"},
		{http.MethodDelete, "/v1/fishing/catches/x"},
		{http.MethodGet, "/v1/fishing/catches/x/photo"},
		{http.MethodGet, "/v1/fishing/spots"},
		{http.MethodPost, "/v1/fishing/spots"},
		{http.MethodPatch, "/v1/fishing/spots/x"},
		{http.MethodDelete, "/v1/fishing/spots/x"},
	} {
		if rec, _ := e.do(t, c.m, c.p, "", map[string]any{}); rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s %s = %d", c.m, c.p, rec.Code)
		}
	}
}

func TestFishingIdentifyAndJournalFlow(t *testing.T) {
	e := newFishingEnv(t, stubVision{})
	_, tok := e.user(t, 4)
	img := "data:image/jpeg;base64," + base64.StdEncoding.EncodeToString([]byte{0xff, 0xd8, 1})
	body := map[string]any{"request_id": "req-api-0001", "image": img}

	rec, out := e.do(t, http.MethodPost, "/v1/fishing/identify", tok, body)
	if rec.Code != http.StatusOK || out["balance"].(float64) != 1 {
		t.Fatalf("identify %d %s", rec.Code, rec.Body.String())
	}
	ident := out["identification"].(map[string]any)
	if ident["status"] != "done" || !strings.Contains(ident["disclaimer"].(string), "AI 识别仅供参考") {
		t.Fatalf("ident %v", ident)
	}
	// 重放不扣费
	_, out = e.do(t, http.MethodPost, "/v1/fishing/identify", tok, body)
	if out["balance"].(float64) != 1 || out["identification"].(map[string]any)["replayed"] != true {
		t.Fatalf("replay %v", out)
	}
	// 余额 1 < 3
	rec, out = e.do(t, http.MethodPost, "/v1/fishing/identify", tok, map[string]any{"request_id": "req-api-0002", "image": img})
	if rec.Code != http.StatusPaymentRequired || out["code"] != "FISHING.INSUFFICIENT_BALANCE" {
		t.Fatalf("insufficient %d %v", rec.Code, out)
	}

	rec, out = e.do(t, http.MethodPost, "/v1/fishing/spots", tok, map[string]any{"name": "水库北岸", "lat": 30.1, "lon": 120.1})
	if rec.Code != http.StatusCreated {
		t.Fatalf("spot %d %s", rec.Code, rec.Body.String())
	}
	spotID := out["spot"].(map[string]any)["uuid"].(string)
	rec, out = e.do(t, http.MethodPost, "/v1/fishing/catches", tok, map[string]any{
		"species": "鲫鱼", "count": 2, "spot_uuid": spotID, "photo": img})
	if rec.Code != http.StatusCreated {
		t.Fatalf("catch %d %s", rec.Code, rec.Body.String())
	}
	catchID := out["catch"].(map[string]any)["uuid"].(string)
	_, out = e.do(t, http.MethodGet, "/v1/fishing/catches", tok, nil)
	if items, _ := out["items"].([]any); len(items) != 1 || out["stats"].(map[string]any)["fish"].(float64) != 2 {
		t.Fatalf("list %v", out)
	}
	rec, _ = e.do(t, http.MethodGet, "/v1/fishing/catches/"+catchID+"/photo", tok, nil)
	if rec.Code != http.StatusOK || rec.Header().Get("Content-Type") != "image/jpeg" || rec.Body.Len() != 3 {
		t.Fatalf("photo %d %s", rec.Code, rec.Header().Get("Content-Type"))
	}
	_, tok2 := e.user(t, 0)
	if rec, _ := e.do(t, http.MethodGet, "/v1/fishing/catches/"+catchID+"/photo", tok2, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("other user photo %d", rec.Code)
	}
	if rec, _ := e.do(t, http.MethodDelete, "/v1/fishing/catches/"+catchID, tok, nil); rec.Code != http.StatusOK {
		t.Fatalf("delete %d", rec.Code)
	}
	if rec, _ := e.do(t, http.MethodPost, "/v1/fishing/catches", tok, map[string]any{"species": ""}); rec.Code != http.StatusBadRequest {
		t.Fatalf("invalid %d", rec.Code)
	}
}

func TestFishingIdentifyRefundViaAPI(t *testing.T) {
	e := newFishingEnv(t, stubVision{fail: true})
	_, tok := e.user(t, 3)
	img := "data:image/jpeg;base64," + base64.StdEncoding.EncodeToString([]byte{0xff, 0xd8, 1})
	rec, out := e.do(t, http.MethodPost, "/v1/fishing/identify", tok, map[string]any{"request_id": "req-api-fail", "image": img})
	if rec.Code != http.StatusOK || out["balance"].(float64) != 3 {
		t.Fatalf("refund %d %s", rec.Code, rec.Body.String())
	}
	ident := out["identification"].(map[string]any)
	if ident["status"] != "failed" || ident["refunded"] != true {
		t.Fatalf("ident %v", ident)
	}
}
