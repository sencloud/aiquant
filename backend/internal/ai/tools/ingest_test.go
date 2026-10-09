package tools

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/ingest"
)

// 采集端按主力连续推送，而模型手里常是具体月份合约：两种形态都要能命中。
func TestContinuousCode(t *testing.T) {
	cases := map[string]string{
		"RB2601.SHF": "RB.SHF",
		"IF2603.CFX": "IF.CFX",
		"M2605.DCE":  "M.DCE",
		"T2612.CFX":  "T.CFX",
		"RB.SHF":     "", // 本来就是连续合约
		"600519.SH":  "", // 股票不会被折算
		"":           "",
	}
	for in, want := range cases {
		if got := continuousCode(in); got != want {
			t.Errorf("continuousCode(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestIngestLookup(t *testing.T) {
	reg := ingest.NewRegistry(nil)
	reg.Put([]ingest.Quote{{
		Symbol: "RB.SHF", Name: "螺纹钢连续", Last: 3097, PctChg: 0.55,
		PreClose: 3080, OI: 1677048, Ts: time.Now().UnixMilli(),
	}})

	t.Run("连续合约直接命中", func(t *testing.T) {
		q, ok := ingestLookup(reg, time.Minute, "RB.SHF")
		if !ok {
			t.Fatal("应命中")
		}
		if q["source"] != "local_agent" || q["realtime"] != true {
			t.Fatalf("应标记为采集端实时数据: %+v", q)
		}
		if q["last"].(float64) != 3097 {
			t.Fatalf("价格不对: %+v", q)
		}
	})

	t.Run("具体月份折算到连续", func(t *testing.T) {
		q, ok := ingestLookup(reg, time.Minute, "RB2601.SHF")
		if !ok {
			t.Fatal("应折算命中")
		}
		if q["requested"] != "RB2601.SHF" || q["ts_code"] != "RB.SHF" {
			t.Fatalf("折算信息缺失: %+v", q)
		}
	})

	t.Run("过期不命中", func(t *testing.T) {
		time.Sleep(5 * time.Millisecond)
		if _, ok := ingestLookup(reg, time.Millisecond, "RB.SHF"); ok {
			t.Fatal("超过新鲜度窗口不应命中")
		}
	})

	t.Run("空缓存安全", func(t *testing.T) {
		if _, ok := ingestLookup(nil, time.Minute, "RB.SHF"); ok {
			t.Fatal("nil 缓存不应命中")
		}
	})
}

// 采集端推送的 JSON 契约必须与后端解析一致。
func TestIngestContractJSON(t *testing.T) {
	body := `{"source":"local_quote_agent","quotes":[
		{"symbol":"RB.SHF","name":"螺纹钢连续","last":3097,"pct_chg":0.55,
		 "open":3082,"high":3105,"low":3080,"pre_close":3080,"volume":271754,
		 "oi":1677048,"ts":1791586000000}]}`
	var parsed struct {
		Quotes []ingest.Quote `json:"quotes"`
	}
	if err := json.Unmarshal([]byte(body), &parsed); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(parsed.Quotes) != 1 || parsed.Quotes[0].Symbol != "RB.SHF" ||
		parsed.Quotes[0].OI != 1677048 {
		t.Fatalf("契约不匹配: %+v", parsed.Quotes)
	}
}
