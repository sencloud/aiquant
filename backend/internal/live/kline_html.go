package live

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"html"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/realtime"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// echartsJS 在编译期由 //go:embed 嵌入二进制(~1MB),
// 用于把 K 线 HTML 做成 self-contained 文档 — 完全脱离 CDN,
// 客户端 webview 不需要任何外网请求即可渲染。
//
// 这是用户在 v1 反馈 "ECharts 加载失败 / 未就绪" 之后选定的根治方案 —
// 之前用 CDN(lib.baomitu / staticfile / elemecdn)的路径全部不可达或返回 404 占位,
// 内嵌彻底消除了 CDN 命中失败 / 跨域 / ATS 拦截等所有可能性。
//
//go:embed assets/echarts.min.js
var echartsJS string

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
	ma60 := movingAverage(closes, 60)

	// MACD(12, 26, 9)— DIF/DEA 折线 + MACD 柱
	dif, dea, macdHist := calcMACD(closes, 12, 26, 9)

	// 60 日内最高 / 最低点 — 给 markPoint 用(主图标注)
	hiIdx, hiVal := -1, -1.0
	loIdx, loVal := -1, -1.0
	for i, c := range candles {
		if hiIdx < 0 || c.High > hiVal {
			hiIdx, hiVal = i, c.High
		}
		if loIdx < 0 || c.Low < loVal {
			loIdx, loVal = i, c.Low
		}
	}

	payload := map[string]any{
		"name":      nameLabel,
		"symbol":    symbol,
		"last":      round2f(lastPrice),
		"pct_chg":   round2f(pctChg),
		"data_time": dataTimeLab,
		"dates":     dates,
		"kline":     klineData,
		"volume":    volData,
		"ma5":       ma5,
		"ma10":      ma10,
		"ma20":      ma20,
		"ma60":      ma60,
		"dif":       dif,
		"dea":       dea,
		"macd":      macdHist,
		"hi_idx":    hiIdx,
		"hi_val":    round2f(hiVal),
		"lo_idx":    loIdx,
		"lo_val":    round2f(loVal),
	}
	jsonBytes, err := json.Marshal(payload)
	if err != nil {
		return errHTML("序列化失败")
	}

	return renderKlineHTML(string(jsonBytes))
}

// renderKlineHTML 把数据 JSON 嵌入 ECharts 模板。
//
// ECharts JS 通过 //go:embed 内嵌(echartsJS 变量),HTML 内 <script> 直接内联,
// 客户端 webview 不再依赖任何 CDN,彻底消除"加载失败"问题。
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
<script>` + echartsJS + `</script>
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
    document.getElementById('chart').innerHTML = '<div id="err">ECharts 未就绪</div>';
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
      data: ['K线', 'MA5', 'MA10', 'MA20', 'MA60', 'DIF', 'DEA', 'MACD'],
      top: 4, textStyle: { color: '#999', fontSize: 10 },
      itemWidth: 10, itemHeight: 6, itemGap: 8
    },
    // 3 个区域:主图(K)/ 成交量 / MACD
    grid: [
      { left: '9%', right: '4%', top: 30, height: '50%' },
      { left: '9%', right: '4%', top: '64%', height: '14%' },
      { left: '9%', right: '4%', top: '82%', bottom: 22 }
    ],
    xAxis: [
      {
        type: 'category', data: DATA.dates, gridIndex: 0,
        axisLine: { lineStyle: { color: '#333' } },
        axisLabel: { show: false },
        axisPointer: { label: { show: false } }
      },
      {
        type: 'category', data: DATA.dates, gridIndex: 1,
        axisLine: { lineStyle: { color: '#333' } },
        axisLabel: { show: false },
        axisPointer: { label: { show: false } }
      },
      {
        type: 'category', data: DATA.dates, gridIndex: 2,
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
      },
      {
        scale: true, gridIndex: 2,
        splitNumber: 2,
        splitLine: { show: false },
        axisLabel: { color: '#888', fontSize: 9 }
      }
    ],
    axisPointer: {
      link: [{ xAxisIndex: 'all' }],
      label: { backgroundColor: '#555' }
    },
    dataZoom: [{ type: 'inside', xAxisIndex: [0, 1, 2], start: 50, end: 100 }],
    series: [
      {
        name: 'K线', type: 'candlestick', data: DATA.kline,
        xAxisIndex: 0, yAxisIndex: 0,
        itemStyle: {
          color: '#FF4D4F', color0: '#52C41A',
          borderColor: '#FF4D4F', borderColor0: '#52C41A'
        },
        // 60 日高 / 低点标注(直接画在 K 线上,直观看到极值位置)
        markPoint: {
          symbol: 'pin', symbolSize: 38,
          label: { color: '#fff', fontSize: 9, fontWeight: 700 },
          data: [
            { name: '高', coord: [DATA.hi_idx, DATA.hi_val], value: DATA.hi_val,
              itemStyle: { color: '#FF4D4F' } },
            { name: '低', coord: [DATA.lo_idx, DATA.lo_val], value: DATA.lo_val,
              itemStyle: { color: '#52C41A' } }
          ]
        },
        // 当前价水平虚线 — 给人一个"现在在哪个位置"的直观参考
        markLine: {
          symbol: ['none', 'none'],
          lineStyle: { color: '#FFD666', type: 'dashed', width: 1 },
          label: {
            color: '#FFD666', fontSize: 10, fontWeight: 700,
            formatter: function(p){ return '现价 ' + Number(p.value).toFixed(2); },
            position: 'insideEndTop'
          },
          data: [{ yAxis: DATA.last }]
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
        name: 'MA60', type: 'line', data: DATA.ma60,
        xAxisIndex: 0, yAxisIndex: 0,
        smooth: true, showSymbol: false, lineStyle: { color: '#F759AB', width: 1.5 }
      },
      {
        name: '成交量', type: 'bar',
        xAxisIndex: 1, yAxisIndex: 1,
        data: DATA.volume.map(function(d){
          return { value: d[1], itemStyle: { color: d[2] > 0 ? '#FF4D4F' : '#52C41A' } };
        })
      },
      // MACD 副图 — 柱 + DIF/DEA 折线
      {
        name: 'MACD', type: 'bar',
        xAxisIndex: 2, yAxisIndex: 2,
        data: DATA.macd.map(function(v){
          if (v == null) return { value: null };
          return { value: v, itemStyle: { color: v >= 0 ? '#FF4D4F' : '#52C41A' } };
        })
      },
      {
        name: 'DIF', type: 'line', data: DATA.dif,
        xAxisIndex: 2, yAxisIndex: 2,
        smooth: true, showSymbol: false, lineStyle: { color: '#FFD666', width: 1 }
      },
      {
        name: 'DEA', type: 'line', data: DATA.dea,
        xAxisIndex: 2, yAxisIndex: 2,
        smooth: true, showSymbol: false, lineStyle: { color: '#69C0FF', width: 1 }
      },
      // 嘉宾发言标注承载 series — 数据线本身永远空,只用 markLine.data 装价位线。
      // window.__setAnnotations(...) 调用时只重设这个 series 的 markLine,
      // 不影响主图其他 series(K 线 / MA / MACD)。
      {
        name: '__annotations__',
        type: 'line',
        data: [],
        xAxisIndex: 0, yAxisIndex: 0,
        silent: true, showSymbol: false,
        markLine: { silent: true, symbol: ['none','none'], data: [] }
      }
    ]
  };
  chart.setOption(option);
  window.addEventListener('resize', function(){ chart.resize(); });

  // ── 嘉宾发言「与 K 线共振」JS Hook ─────────────────────────────────
  // 前端拿到嘉宾新消息后聚合当前焦点的所有 annotations,
  // 通过 webview.runJavaScript("window.__setAnnotations(JSON)") 推过来。
  //
  // annot 结构(来自 backend live.Annotation,前端拼上 persona 后传入):
  //   { type, price, label, persona }
  // type 颜色映射(必须和 guest_speaker.go 的 prompt 描述一致):
  var ANNOT_STYLE = {
    support:    { color: '#16A34A', type: 'solid'  },
    resistance: { color: '#EF4444', type: 'solid'  },
    stop:       { color: '#F97316', type: 'dashed' },
    target:     { color: '#06B6D4', type: 'dashed' },
    note:       { color: '#FACC15', type: 'dashed' }
  };
  window.__setAnnotations = function(arr){
    if (!Array.isArray(arr)) arr = [];
    var lines = arr.map(function(a){
      var st = ANNOT_STYLE[a.type] || ANNOT_STYLE.note;
      var who = a.persona ? (a.persona + '·') : '';
      var labelText = who + (a.label || '') + ' ' + Number(a.price).toFixed(2);
      return {
        yAxis: Number(a.price),
        name: labelText,
        lineStyle: { color: st.color, type: st.type, width: 1 },
        label: {
          show: true,
          formatter: '{b}',
          color: '#fff',
          backgroundColor: st.color,
          padding: [1, 4],
          borderRadius: 2,
          position: 'insideEndTop',
          fontSize: 9,
          fontWeight: 700
        }
      };
    });
    chart.setOption({
      series: [{ name: '__annotations__', markLine: { data: lines } }]
    });
  };
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

// calcMACD 计算 EMA12/EMA26/DIF/DEA/MACD柱(长度同 closes,前置位用 nil)。
//
// 标准定义:
//   DIF = EMA(close, short) - EMA(close, long)
//   DEA = EMA(DIF, signal)
//   MACD = (DIF - DEA) * 2
//
// 输出元素类型 any:数据点合法时填 float64,前置位填 nil(JSON null,ECharts 跳过)。
func calcMACD(closes []float64, short, long, signal int) (dif, dea, macd []any) {
	n := len(closes)
	dif = make([]any, n)
	dea = make([]any, n)
	macd = make([]any, n)
	if n == 0 || short <= 0 || long <= 0 || signal <= 0 {
		return
	}

	emaShort := ema(closes, short)
	emaLong := ema(closes, long)

	difVals := make([]float64, n)
	difValid := make([]bool, n)
	for i := 0; i < n; i++ {
		if i < long-1 {
			continue
		}
		difVals[i] = emaShort[i] - emaLong[i]
		difValid[i] = true
		dif[i] = round2f(difVals[i])
	}

	// DEA = EMA(DIF, signal),只在 DIF 有效区段算
	deaVals := make([]float64, n)
	deaValid := make([]bool, n)
	alpha := 2.0 / float64(signal+1)
	for i := 0; i < n; i++ {
		if !difValid[i] {
			continue
		}
		if i == long-1 {
			deaVals[i] = difVals[i]
		} else {
			deaVals[i] = difVals[i]*alpha + deaVals[i-1]*(1-alpha)
		}
		deaValid[i] = true
		dea[i] = round2f(deaVals[i])
		macd[i] = round2f((difVals[i] - deaVals[i]) * 2)
	}
	return
}

// ema 计算指数移动平均(长度同 closes)。前 window-1 位用 SMA 启动后续递推。
func ema(closes []float64, window int) []float64 {
	out := make([]float64, len(closes))
	if window <= 0 || len(closes) == 0 {
		return out
	}
	alpha := 2.0 / float64(window+1)
	var sum float64
	for i, v := range closes {
		if i < window-1 {
			sum += v
			continue
		}
		if i == window-1 {
			sum += v
			out[i] = sum / float64(window)
			continue
		}
		out[i] = v*alpha + out[i-1]*(1-alpha)
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
