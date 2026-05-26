package live

import (
	"context"
	"encoding/json"
	"fmt"
	"html"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/realtime"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// KlineBuilder 拼装"AI 直播主图"的 K 线 HTML 片段(给 Flutter webview_flutter 直接 loadHtmlString)。
//
// 数据来源:
//   * 日线 K 线:tushare HistoryFor(最近 60 个交易日,自动按代码路由 daily/index/fund/fut)
//   * 实时报价:realtime FetchSnapshot(走新浪 hq,稳定)— 用于顶部 hud(最新价 / 涨跌幅)
//
// 渲染:
//   * ECharts 5.4.3(阿里云 lib.baomitu.com CDN,生产服务器在国内可达)
//   * 深色主题 + 中国习惯(红涨绿跌)
//   * K 线 + MA5/MA10/MA20 + 成交量副图
//   * 顶部条:股票名 · 代码 · 最新价 · 涨跌幅 · 数据时间
type KlineBuilder struct {
	tu *tushare.Client
	rt *realtime.Client
}

func NewKlineBuilder(tu *tushare.Client, rt *realtime.Client) *KlineBuilder {
	return &KlineBuilder{tu: tu, rt: rt}
}

// Build 返回 self-contained HTML 字符串,前端 webview 直接加载。
//
// symbol 接受 tushare ts_code(600519.SH / 000300.SH / RB2610.SHF 等)。
// 失败时返回一个"加载失败"的占位 HTML(永远不返回 error,保证前端可渲染)。
func (b *KlineBuilder) Build(ctx context.Context, symbol string) string {
	symbol = strings.TrimSpace(symbol)
	if symbol == "" {
		return errHTML("缺少 symbol")
	}

	// 1. 拉近 90 个自然日的日线(去掉非交易日大概 60 根)
	end := time.Now()
	start := end.AddDate(0, 0, -120)
	candles, err := b.tu.HistoryFor(ctx, symbol, start, end)
	if err != nil {
		return errHTML(fmt.Sprintf("加载 %s K 线失败:%s", symbol, err.Error()))
	}
	if len(candles) == 0 {
		return errHTML(fmt.Sprintf("%s 暂无日线数据", symbol))
	}
	// 只取最后 60 根
	if len(candles) > 60 {
		candles = candles[len(candles)-60:]
	}

	// 2. 拉实时报价(失败不阻塞主图,只显示日线最末一根)
	var (
		lastPrice   float64
		pctChg      float64
		dataTimeLab string
		nameLabel   = symbol
	)
	if b.rt != nil {
		if q, e2 := b.rt.FetchSnapshot(ctx, symbol); e2 == nil && q != nil {
			lastPrice = q.Last
			pctChg = q.PctChg
			nameLabel = q.Name
			dataTimeLab = "实时"
		}
	}
	if lastPrice == 0 {
		// 用日线最末一根做兜底显示(不算"兜底数据源",只是同源 fallback)
		last := candles[len(candles)-1]
		lastPrice = last.Close
		if last.PreClose > 0 {
			pctChg = (last.Close - last.PreClose) / last.PreClose * 100
		}
		dataTimeLab = formatTradeDate(last.TradeDate)
	}

	// 3. 准备 ECharts 数据
	dates := make([]string, 0, len(candles))
	klineData := make([][]float64, 0, len(candles))
	volData := make([][]any, 0, len(candles))
	closes := make([]float64, 0, len(candles))

	for i, c := range candles {
		dates = append(dates, shortDate(c.TradeDate))
		// ECharts candlestick 顺序:[open, close, low, high]
		klineData = append(klineData, []float64{c.Open, c.Close, c.Low, c.High})
		closes = append(closes, c.Close)
		// 成交量:1=涨绿,0=跌红(中国习惯反转,后面 itemStyle 用 ma 函数判断)
		upDown := 1
		if i > 0 && c.Close < candles[i-1].Close {
			upDown = -1
		}
		volData = append(volData, []any{i, c.Vol, upDown})
	}
	ma5 := movingAverage(closes, 5)
	ma10 := movingAverage(closes, 10)
	ma20 := movingAverage(closes, 20)

	payload := map[string]any{
		"name":         nameLabel,
		"symbol":       symbol,
		"last":         round2f(lastPrice),
		"pct_chg":      round2f(pctChg),
		"data_time":    dataTimeLab,
		"dates":        dates,
		"kline":        klineData,
		"volume":       volData,
		"ma5":          ma5,
		"ma10":         ma10,
		"ma20":         ma20,
	}
	jsonBytes, err := json.Marshal(payload)
	if err != nil {
		return errHTML("序列化失败")
	}

	return renderKlineHTML(string(jsonBytes))
}

// renderKlineHTML 把数据 JSON 嵌入 ECharts 模板。
func renderKlineHTML(dataJSON string) string {
	return `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1" />
<title>K线</title>
<style>
  html, body {
    margin: 0; padding: 0; background: #0E0E10; color: #E8E8EE;
    font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
    -webkit-touch-callout: none; -webkit-user-select: none;
  }
  #hud {
    position: absolute; top: 8px; left: 12px; right: 12px;
    display: flex; align-items: baseline; gap: 10px; z-index: 10;
    pointer-events: none;
  }
  #hud .name { font-size: 15px; font-weight: 700; color: #E8E8EE; }
  #hud .code { font-size: 11px; color: #8C8C99; }
  #hud .price { font-size: 18px; font-weight: 800; margin-left: auto; }
  #hud .pct { font-size: 13px; font-weight: 600; }
  #hud .time { font-size: 10px; color: #8C8C99; margin-left: 6px; }
  .up { color: #FF4D4F; }
  .down { color: #52C41A; }
  .flat { color: #E8E8EE; }
  #chart { position: absolute; top: 36px; left: 0; right: 0; bottom: 0; }
  #err { padding: 40px 20px; color: #FF7875; font-size: 13px; }
</style>
</head>
<body>
<div id="hud">
  <span class="name" id="nm"></span>
  <span class="code" id="cd"></span>
  <span class="price" id="px"></span>
  <span class="pct" id="pc"></span>
  <span class="time" id="tm"></span>
</div>
<div id="chart"></div>
<script src="https://lib.baomitu.com/echarts/5.4.3/echarts.min.js"></script>
<script>
(function(){
  var DATA = ` + dataJSON + `;
  document.getElementById('nm').textContent = DATA.name;
  document.getElementById('cd').textContent = DATA.symbol;
  document.getElementById('px').textContent = DATA.last.toFixed(2);
  document.getElementById('tm').textContent = DATA.data_time || '';
  var pcEl = document.getElementById('pc');
  var sign = DATA.pct_chg > 0 ? '+' : (DATA.pct_chg < 0 ? '' : '');
  pcEl.textContent = sign + DATA.pct_chg.toFixed(2) + '%';
  pcEl.className = 'pct ' + (DATA.pct_chg > 0 ? 'up' : (DATA.pct_chg < 0 ? 'down' : 'flat'));
  document.getElementById('px').className = 'price ' + (DATA.pct_chg > 0 ? 'up' : (DATA.pct_chg < 0 ? 'down' : 'flat'));

  if (typeof echarts === 'undefined') {
    document.getElementById('chart').innerHTML = '<div id="err">ECharts 加载失败</div>';
    return;
  }
  var chart = echarts.init(document.getElementById('chart'), null, { renderer: 'canvas' });
  var option = {
    backgroundColor: '#0E0E10',
    animation: false,
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'cross', lineStyle: { color: '#666' } },
      backgroundColor: 'rgba(20,20,24,.9)',
      borderColor: '#333',
      textStyle: { color: '#fff', fontSize: 11 }
    },
    legend: {
      data: ['K线', 'MA5', 'MA10', 'MA20'],
      top: 4, textStyle: { color: '#999', fontSize: 11 }
    },
    grid: [
      { left: '8%', right: '4%', top: 32, height: '60%' },
      { left: '8%', right: '4%', top: '72%', bottom: 24 }
    ],
    xAxis: [
      {
        type: 'category', data: DATA.dates, gridIndex: 0,
        axisLine: { lineStyle: { color: '#333' } },
        axisLabel: { color: '#888', fontSize: 9, hideOverlap: true }
      },
      {
        type: 'category', data: DATA.dates, gridIndex: 1,
        axisLine: { lineStyle: { color: '#333' } },
        axisLabel: { color: '#888', fontSize: 9, hideOverlap: true }
      }
    ],
    yAxis: [
      {
        scale: true, gridIndex: 0,
        splitLine: { lineStyle: { color: '#1d1d22' } },
        axisLabel: { color: '#888', fontSize: 9 }
      },
      {
        scale: true, gridIndex: 1,
        splitNumber: 2,
        splitLine: { show: false },
        axisLabel: { color: '#888', fontSize: 9 }
      }
    ],
    dataZoom: [{ type: 'inside', xAxisIndex: [0, 1], start: 50, end: 100 }],
    series: [
      {
        name: 'K线', type: 'candlestick', data: DATA.kline,
        xAxisIndex: 0, yAxisIndex: 0,
        itemStyle: {
          color: '#FF4D4F', color0: '#52C41A',
          borderColor: '#FF4D4F', borderColor0: '#52C41A'
        }
      },
      {
        name: 'MA5', type: 'line', data: DATA.ma5,
        xAxisIndex: 0, yAxisIndex: 0,
        smooth: true, showSymbol: false, lineStyle: { color: '#FFD666', width: 1 }
      },
      {
        name: 'MA10', type: 'line', data: DATA.ma10,
        xAxisIndex: 0, yAxisIndex: 0,
        smooth: true, showSymbol: false, lineStyle: { color: '#69C0FF', width: 1 }
      },
      {
        name: 'MA20', type: 'line', data: DATA.ma20,
        xAxisIndex: 0, yAxisIndex: 0,
        smooth: true, showSymbol: false, lineStyle: { color: '#B37FEB', width: 1 }
      },
      {
        name: '成交量', type: 'bar',
        xAxisIndex: 1, yAxisIndex: 1,
        data: DATA.volume.map(function(d){
          return { value: d[1], itemStyle: { color: d[2] > 0 ? '#FF4D4F' : '#52C41A' } };
        })
      }
    ]
  };
  chart.setOption(option);
  window.addEventListener('resize', function(){ chart.resize(); });
})();
</script>
</body>
</html>`
}

func errHTML(msg string) string {
	return `<!doctype html><html><head><meta charset="utf-8"/><style>
body{background:#0E0E10;color:#FF7875;font-family:-apple-system,sans-serif;
padding:40px 20px;font-size:13px;text-align:center;}
</style></head><body>` + html.EscapeString(msg) + `</body></html>`
}

// movingAverage 返回长度同 closes 的 MA 序列。窗口未满时该位 = nil(ECharts 跳过)。
//
// 输出元素类型用 any:满足条件填 float64,否则填 nil(JSON marshal 出来是 null)。
func movingAverage(closes []float64, window int) []any {
	out := make([]any, len(closes))
	if window <= 1 || window > len(closes) {
		for i := range out {
			out[i] = nil
		}
		return out
	}
	var sum float64
	for i, v := range closes {
		sum += v
		if i >= window {
			sum -= closes[i-window]
		}
		if i >= window-1 {
			out[i] = round2f(sum / float64(window))
		} else {
			out[i] = nil
		}
	}
	return out
}

func round2f(v float64) float64 {
	if v == 0 {
		return 0
	}
	return float64(int64(v*100+0.5)) / 100
}

// shortDate 20260526 → "05-26"
func shortDate(d string) string {
	if len(d) != 8 {
		return d
	}
	return d[4:6] + "-" + d[6:8]
}

// formatTradeDate 20260526 → "05-26 收盘"
func formatTradeDate(d string) string {
	if len(d) != 8 {
		return d
	}
	return d[4:6] + "-" + d[6:8] + " 收盘"
}
