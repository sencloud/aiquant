package fishing

import (
	"testing"
	"time"
)

func TestMoonPhases(t *testing.T) {
	cases := []struct {
		at    time.Time
		phase string
	}{
		// 2024-01-11 11:57 UTC 新月；2024-01-25 17:54 UTC 满月（天文台公布值）。
		{time.Date(2024, 1, 11, 12, 0, 0, 0, time.UTC), "新月"},
		{time.Date(2024, 1, 25, 18, 0, 0, 0, time.UTC), "满月"},
		{time.Date(2024, 1, 18, 3, 0, 0, 0, time.UTC), "上弦月"},
	}
	for _, c := range cases {
		got := Moon(c.at)
		if got.Phase != c.phase {
			t.Errorf("%s: phase=%s age=%.1f, want %s", c.at, got.Phase, got.Age, c.phase)
		}
	}
	if m := Moon(time.Date(2024, 1, 25, 18, 0, 0, 0, time.UTC)); m.Illumination < 0.97 {
		t.Errorf("full moon illumination = %v", m.Illumination)
	}
}

func TestSunTimesShanghai(t *testing.T) {
	// 上海 2024-06-21：日出约 04:50、日落约 19:01（北京时间）。
	rise, set, ok := SunTimes(time.Date(2024, 6, 21, 0, 0, 0, 0, time.UTC), 31.23, 121.47)
	if !ok {
		t.Fatal("expected sunrise")
	}
	cst := time.FixedZone("CST", 8*3600)
	r, s := rise.In(cst), set.In(cst)
	if r.Hour() != 4 || r.Minute() < 40 || r.Minute() > 59 {
		t.Errorf("sunrise %s", r.Format("15:04"))
	}
	if s.Hour() != 19 || s.Minute() > 10 {
		t.Errorf("sunset %s", s.Format("15:04"))
	}
}
