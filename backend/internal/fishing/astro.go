// Package fishing 是「喜爱钓鱼」主题的服务端：出钓指数、禁渔提示、拍照识鱼、
// 渔获日记与私人钓点。
package fishing

import (
	"math"
	"time"
)

// SynodicMonth 朔望月长度（天）。
const SynodicMonth = 29.530588853

// refNewMoon 2000-01-06 18:14 UTC 的新月，作为月龄起算点。
var refNewMoon = time.Date(2000, 1, 6, 18, 14, 0, 0, time.UTC)

// MoonInfo 是某一时刻的月相（本地计算，不依赖外部接口）。
type MoonInfo struct {
	Age          float64 `json:"age"`          // 月龄（天，0 = 新月，≈14.8 = 满月）
	Illumination float64 `json:"illumination"` // 照亮比例 0–1
	Phase        string  `json:"phase"`        // 新月 / 蛾眉月 / 上弦月 / 盈凸月 / 满月 / 亏凸月 / 下弦月 / 残月
}

// Moon 计算 t 时刻的月相。平均朔望月近似，误差在半天以内，够做出钓参考。
func Moon(t time.Time) MoonInfo {
	days := t.UTC().Sub(refNewMoon).Hours() / 24
	age := math.Mod(days, SynodicMonth)
	if age < 0 {
		age += SynodicMonth
	}
	illum := (1 - math.Cos(2*math.Pi*age/SynodicMonth)) / 2
	return MoonInfo{
		Age:          math.Round(age*10) / 10,
		Illumination: math.Round(illum*100) / 100,
		Phase:        moonPhaseName(age),
	}
}

func moonPhaseName(age float64) string {
	switch {
	case age < 1.85:
		return "新月"
	case age < 5.54:
		return "蛾眉月"
	case age < 9.23:
		return "上弦月"
	case age < 12.92:
		return "盈凸月"
	case age < 16.61:
		return "满月"
	case age < 20.30:
		return "亏凸月"
	case age < 23.99:
		return "下弦月"
	case age < 27.68:
		return "残月"
	default:
		return "新月"
	}
}

// SunTimes 用标准日出方程估算某地某日的日出 / 日落（UTC），精度约 1–2 分钟。
// 极昼 / 极夜返回 ok=false。
func SunTimes(date time.Time, lat, lon float64) (rise, set time.Time, ok bool) {
	const deg = math.Pi / 180
	noon := time.Date(date.Year(), date.Month(), date.Day(), 12, 0, 0, 0, time.UTC)
	jd := float64(noon.Unix())/86400 + 2440587.5
	n := math.Round(jd - 2451545.0 + 0.0008)
	jStar := n - lon/360
	m := math.Mod(357.5291+0.98560028*jStar, 360)
	c := 1.9148*math.Sin(m*deg) + 0.02*math.Sin(2*m*deg) + 0.0003*math.Sin(3*m*deg)
	lambda := math.Mod(m+c+180+102.9372, 360)
	jTransit := 2451545.0 + jStar + 0.0053*math.Sin(m*deg) - 0.0069*math.Sin(2*lambda*deg)
	sinDec := math.Sin(lambda*deg) * math.Sin(23.44*deg)
	cosDec := math.Cos(math.Asin(sinDec))
	cosW := (math.Sin(-0.83*deg) - math.Sin(lat*deg)*sinDec) / (math.Cos(lat*deg) * cosDec)
	if cosW < -1 || cosW > 1 {
		return time.Time{}, time.Time{}, false
	}
	w := math.Acos(cosW) / deg
	toTime := func(j float64) time.Time {
		sec := (j - 2440587.5) * 86400
		return time.Unix(int64(math.Round(sec)), 0).UTC()
	}
	return toTime(jTransit - w/360), toTime(jTransit + w/360), true
}
