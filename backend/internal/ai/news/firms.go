package news

import (
	"context"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
)

// ErrFirmsNotConfigured 服务端未配 FIRMS map_key 时返回；调用工具应回错误 JSON。
var ErrFirmsNotConfigured = errors.New("firms map_key not configured on server")

// FetchFireHotspots 调 NASA FIRMS area CSV API。
//
// 文档：https://firms.modaps.eosdis.nasa.gov/api/area/
//
// 路径：/api/area/csv/{MAP_KEY}/{SOURCE}/{AREA_COORDINATES}/{DAY_RANGE}/{DATE}
//
// 这里只暴露常用形态：boundingBox = "minLon,minLat,maxLon,maxLat"，dayRange ∈ [1,10]。
func (c *Client) FetchFireHotspots(
	ctx context.Context,
	source string,
	boundingBox string,
	dayRange int,
) ([]Event, error) {
	if c.cfg.FirmsMapKey == "" {
		return nil, ErrFirmsNotConfigured
	}
	if source == "" {
		source = "VIIRS_SNPP_NRT"
	}
	if dayRange <= 0 || dayRange > 10 {
		dayRange = 1
	}
	bb := strings.ReplaceAll(boundingBox, " ", "")
	if bb == "" {
		return nil, errors.New("bounding_box required: 'minLon,minLat,maxLon,maxLat'")
	}
	u := fmt.Sprintf("%s/%s/%s/%s/%d",
		strings.TrimRight(c.cfg.FirmsBaseURL, "/"),
		c.cfg.FirmsMapKey, source, bb, dayRange)
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("firms http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return nil, fmt.Errorf("firms %d: %s", resp.StatusCode, string(b))
	}
	r := csv.NewReader(resp.Body)
	r.FieldsPerRecord = -1
	rows, err := r.ReadAll()
	if err != nil {
		return nil, fmt.Errorf("firms csv: %w", err)
	}
	if len(rows) <= 1 {
		return []Event{}, nil
	}
	header := rows[0]
	idx := func(name string) int {
		for i, h := range header {
			if strings.EqualFold(h, name) {
				return i
			}
		}
		return -1
	}
	latIdx, lonIdx := idx("latitude"), idx("longitude")
	briIdx := idx("bright_ti4")
	if briIdx < 0 {
		briIdx = idx("brightness")
	}
	confIdx := idx("confidence")
	dateIdx := idx("acq_date")
	timeIdx := idx("acq_time")
	out := make([]Event, 0, len(rows)-1)
	for _, row := range rows[1:] {
		if latIdx < 0 || lonIdx < 0 {
			break
		}
		lat, _ := strconv.ParseFloat(strings.TrimSpace(safeIdx(row, latIdx)), 64)
		lon, _ := strconv.ParseFloat(strings.TrimSpace(safeIdx(row, lonIdx)), 64)
		bri, _ := strconv.ParseFloat(strings.TrimSpace(safeIdx(row, briIdx)), 64)
		ev := Event{
			Source: "firms",
			Type:   "hotspot",
			Title:  fmt.Sprintf("%s 火点 %.4f,%.4f", source, lat, lon),
			Lat:    lat,
			Lon:    lon,
			Score:  bri,
			Extra: map[string]any{
				"confidence": safeIdx(row, confIdx),
				"date":       safeIdx(row, dateIdx),
				"time":       safeIdx(row, timeIdx),
			},
		}
		out = append(out, ev)
	}
	return out, nil
}

func safeIdx(row []string, i int) string {
	if i < 0 || i >= len(row) {
		return ""
	}
	return row[i]
}
