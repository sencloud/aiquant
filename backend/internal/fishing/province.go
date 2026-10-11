package fishing

import (
	_ "embed"
	"encoding/json"
	"math"
	"strings"
	"sync"
)

// 坐标 → 省份。只用于判断「这个地方涉及哪些流域禁渔期」，不用于展示地图。
//
// 数据：data/provinces.json，由 tools/gen_province_bounds.py 从阿里云 DataV.GeoAtlas
// 省级边界简化而来（Douglas-Peucker 0.02°，坐标 GCJ-02；与 WGS-84 相差几百米，
// 只在省界附近 1–2 km 内可能判错，对「提示哪个流域的禁渔期」可以接受）。

//go:embed data/provinces.json
var provincesJSON []byte

type provinceShape struct {
	name                   string
	rings                  [][][2]float64
	minX, minY, maxX, maxY float64
}

var (
	provOnce   sync.Once
	provShapes []provinceShape
)

func loadProvinces() {
	var raw struct {
		Provinces []struct {
			Name  string         `json:"name"`
			Rings [][][2]float64 `json:"rings"`
		} `json:"provinces"`
	}
	if err := json.Unmarshal(provincesJSON, &raw); err != nil {
		return
	}
	for _, p := range raw.Provinces {
		s := provinceShape{name: ShortProvince(p.Name), rings: p.Rings,
			minX: math.Inf(1), minY: math.Inf(1), maxX: math.Inf(-1), maxY: math.Inf(-1)}
		for _, r := range p.Rings {
			for _, pt := range r {
				s.minX, s.maxX = math.Min(s.minX, pt[0]), math.Max(s.maxX, pt[0])
				s.minY, s.maxY = math.Min(s.minY, pt[1]), math.Max(s.maxY, pt[1])
			}
		}
		provShapes = append(provShapes, s)
	}
}

// ProvinceAt 返回 (lat, lon) 所在省级行政区的简称（「浙江」「广西」「北京」）；
// 不在中国境内或落在简化边界的缝隙里时返回 ""。
func ProvinceAt(lat, lon float64) string {
	provOnce.Do(loadProvinces)
	for _, s := range provShapes {
		if lon < s.minX || lon > s.maxX || lat < s.minY || lat > s.maxY {
			continue
		}
		in := false
		for _, r := range s.rings { // 奇偶规则：洞自然被扣掉
			for i, j := 0, len(r)-1; i < len(r); j, i = i, i+1 {
				xi, yi, xj, yj := r[i][0], r[i][1], r[j][0], r[j][1]
				if (yi > lat) != (yj > lat) && lon < (xj-xi)*(lat-yi)/(yj-yi)+xi {
					in = !in
				}
			}
		}
		if in {
			return s.name
		}
	}
	return ""
}

var provinceSuffixes = []string{"维吾尔自治区", "壮族自治区", "回族自治区", "特别行政区", "自治区", "省", "市"}

// ShortProvince 把「浙江省」「广西壮族自治区」规整成「浙江」「广西」。
func ShortProvince(s string) string {
	s = strings.TrimSpace(s)
	for _, suf := range provinceSuffixes {
		if strings.HasSuffix(s, suf) && len(s) > len(suf) {
			return strings.TrimSuffix(s, suf)
		}
	}
	return s
}

// provinceFromLabel 从地名标签（「中国·浙江·千岛湖」「中国·浙江省·杭州」）里认出省份；认不出返回 ""。
func provinceFromLabel(label string) string {
	provOnce.Do(loadProvinces)
	for _, part := range strings.Split(label, "·") {
		p := ShortProvince(part)
		for _, s := range provShapes {
			if s.name == p {
				return p
			}
		}
	}
	return ""
}
