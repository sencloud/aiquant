package live

import (
	"encoding/json"
	"fmt"
	"html"
	"regexp"
	"strconv"
	"strings"
)

// ExtractedMeta 是从 LLM 输出的 ===META=== 块解析出的结构化字段。
//
// 所有指针字段允许 nil，前端在缺失时显示"--"。
type ExtractedMeta struct {
	View         string   `json:"view"`
	Rating       string   `json:"rating"`
	TargetPrice  *float64 `json:"target_price"`
	StopLoss     *float64 `json:"stop_loss"`
	TakeProfit   *float64 `json:"take_profit"`
	PositionHint string   `json:"position_hint"`
	Summary      string   `json:"summary"`
}

var (
	reMetaBlock   = regexp.MustCompile(`(?s)===META===\s*(\{.*?\})\s*===REPORT===`)
	reReportBlock = regexp.MustCompile(`(?s)===REPORT===\s*(.*)$`)
)

// ParseLLMOutput 把 LLM 原始输出切成 (meta, markdown_body)。
//
// 容错：若 ===META=== 块缺失，则把整段视为 markdown body，meta 为空。
// JSON 解析失败 → 返回 meta 空 + error。
func ParseLLMOutput(raw string) (*ExtractedMeta, string, error) {
	raw = strings.TrimSpace(raw)
	mm := reMetaBlock.FindStringSubmatch(raw)
	rm := reReportBlock.FindStringSubmatch(raw)

	body := raw
	if rm != nil {
		body = strings.TrimSpace(rm[1])
	}

	var meta *ExtractedMeta
	if mm != nil {
		var m ExtractedMeta
		if err := json.Unmarshal([]byte(mm[1]), &m); err != nil {
			return nil, body, fmt.Errorf("parse meta json: %w", err)
		}
		meta = &m
	}
	return meta, body, nil
}

// RenderInput 是 RenderReportHTML 的入参。
type RenderInput struct {
	PersonaName    string
	PersonaTitle   string // 副标题，如"价值投资 · 长期持有 · 护城河"
	SymbolName     string
	SymbolCode     string
	Summary        string
	View           string // bullish / neutral / bearish
	Rating         string
	TargetPrice    *float64
	StopLoss       *float64
	TakeProfit     *float64
	PositionHint   string
	MarkdownBody   string
	CreatedAtLabel string // 已格式化的时间字符串，如"2026-05-25 14:30"
}

// RenderReportHTML 把单份报告渲染成完整 HTML 片段，直接喂给客户端 WebView。
//
// HTML 结构（含内联 CSS）：
//
//	<style>...</style>
//	<div class="ai-live-report">
//	  <header>分析师头像+姓名+评级徽章+标的名+时间</header>
//	  <div class="summary">一句话总结</div>
//	  <section class="meta-grid">目标价 / 止损 / 止盈 / 仓位 4 个卡片</section>
//	  <article class="body">…markdown 转 HTML…</article>
//	</div>
func RenderReportHTML(in RenderInput) string {
	var b strings.Builder
	b.WriteString(htmlPrelude())
	b.WriteString(`<div class="ai-live-report">`)

	// Header
	b.WriteString(`<header class="hdr">`)
	b.WriteString(`<div class="hdr-l">`)
	b.WriteString(`<div class="avatar">` + html.EscapeString(initialOf(in.PersonaName)) + `</div>`)
	b.WriteString(`<div class="title">`)
	b.WriteString(`<div class="persona">` + html.EscapeString(in.PersonaName))
	if in.PersonaTitle != "" {
		b.WriteString(` <span class="persona-sub">· ` + html.EscapeString(in.PersonaTitle) + `</span>`)
	}
	b.WriteString(`</div>`)
	b.WriteString(`<div class="symbol">` + html.EscapeString(in.SymbolName))
	if in.SymbolCode != "" {
		b.WriteString(` <span class="sym-code">(` + html.EscapeString(in.SymbolCode) + `)</span>`)
	}
	b.WriteString(`</div>`)
	b.WriteString(`</div></div>`)
	b.WriteString(`<div class="hdr-r">`)
	b.WriteString(htmlRatingBadge(in.Rating, in.View))
	if in.CreatedAtLabel != "" {
		b.WriteString(`<div class="time">` + html.EscapeString(in.CreatedAtLabel) + `</div>`)
	}
	b.WriteString(`</div>`)
	b.WriteString(`</header>`)

	// Summary banner
	if s := strings.TrimSpace(in.Summary); s != "" {
		b.WriteString(`<div class="summary">` + html.EscapeString(s) + `</div>`)
	}

	// Meta grid
	b.WriteString(`<section class="meta-grid">`)
	b.WriteString(metaCard("目标价", fmtPrice(in.TargetPrice)))
	b.WriteString(metaCard("止盈位", fmtPrice(in.TakeProfit)))
	b.WriteString(metaCard("止损位", fmtPrice(in.StopLoss)))
	b.WriteString(metaCard("建议仓位", strings.TrimSpace(in.PositionHint)))
	b.WriteString(`</section>`)

	// Body
	b.WriteString(`<article class="body">`)
	b.WriteString(markdownToHTML(in.MarkdownBody))
	b.WriteString(`</article>`)

	b.WriteString(`</div>`) // ai-live-report
	return b.String()
}

// htmlPrelude 是内联 CSS（暗色调，与客户端 amber 主题一致）。
//
// WebView 兼容性：iOS WKWebView / Android WebView 都支持 flex grid，
// 不依赖 viewport meta（外层 widget 控制大小）；字体大小用 px 而不是 rem，
// 方便客户端调整。
func htmlPrelude() string {
	return `<style>
body { margin: 0; padding: 0; background:#15171b; color:#e7e9ed; font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif; }
.ai-live-report { padding: 16px 14px 28px; max-width: 720px; margin: 0 auto; font-size: 14px; line-height: 1.65; }
.hdr { display:flex; align-items:center; justify-content:space-between; gap:12px; margin-bottom:10px; }
.hdr-l { display:flex; align-items:center; gap:10px; min-width:0; }
.avatar { width:36px; height:36px; border-radius:50%; background:linear-gradient(135deg,#f5b53a,#d97706); color:#fff; font-weight:700; font-size:15px; display:flex; align-items:center; justify-content:center; flex-shrink:0; }
.title { min-width:0; }
.persona { font-weight:700; color:#f5b53a; font-size:14px; line-height:1.2; }
.persona-sub { color:#8a8f99; font-weight:500; font-size:12px; }
.symbol { color:#e7e9ed; font-size:13px; line-height:1.3; margin-top:2px; }
.sym-code { color:#8a8f99; font-size:11px; }
.hdr-r { text-align:right; flex-shrink:0; }
.time { color:#8a8f99; font-size:11px; margin-top:4px; }

.rating { display:inline-block; padding:4px 10px; border-radius:14px; font-weight:700; font-size:12px; border:1px solid; }
.rating.bullish { color:#16a34a; border-color:rgba(22,163,74,.6); background:rgba(22,163,74,.12); }
.rating.bearish { color:#ef4444; border-color:rgba(239,68,68,.6); background:rgba(239,68,68,.12); }
.rating.neutral { color:#cbd5e1; border-color:rgba(203,213,225,.4); background:rgba(203,213,225,.08); }

.summary { background:rgba(245,181,58,.10); border-left:3px solid #f5b53a; color:#f5d68f; padding:10px 12px; border-radius:6px; margin:8px 0 14px; font-size:13px; }

.meta-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:8px; margin:0 0 18px; }
.meta-card { background:#1f2228; border-radius:8px; padding:10px 12px; }
.meta-card .k { font-size:11px; color:#8a8f99; }
.meta-card .v { font-size:15px; font-weight:700; color:#e7e9ed; margin-top:4px; }
.meta-card .v.dim { color:#8a8f99; font-weight:500; }

.body h1, .body h2, .body h3 { color:#f5b53a; font-weight:700; margin: 18px 0 8px; }
.body h1 { font-size:18px; }
.body h2 { font-size:15px; }
.body h3 { font-size:14px; }
.body p { margin:6px 0; color:#d6d8dc; }
.body ul { margin:6px 0; padding-left:22px; }
.body li { margin:3px 0; color:#d6d8dc; }
.body strong { color:#f5d68f; font-weight:700; }
.body em { color:#9aa0aa; font-style:normal; border-bottom:1px dashed #555; }
.body code { background:#0f1115; color:#f5b53a; padding:0 4px; border-radius:3px; font-family: SFMono-Regular, Consolas, monospace; font-size:12px; }
.body blockquote { border-left:3px solid #4b5160; color:#9aa0aa; padding:0 12px; margin:8px 0; font-style:italic; }
.body hr { border:0; border-top:1px solid #2a2d33; margin:14px 0; }
.body table { border-collapse:collapse; margin:8px 0; font-size:12px; width:100%; }
.body th, .body td { border:1px solid #2a2d33; padding:5px 8px; text-align:left; }
.body th { background:#1f2228; color:#f5b53a; }
</style>`
}

func htmlRatingBadge(rating, view string) string {
	cls := "neutral"
	switch view {
	case "bullish":
		cls = "bullish"
	case "bearish":
		cls = "bearish"
	}
	label := strings.TrimSpace(rating)
	if label == "" {
		label = "—"
	}
	return `<span class="rating ` + cls + `">` + html.EscapeString(label) + `</span>`
}

func metaCard(k, v string) string {
	dim := ""
	if strings.TrimSpace(v) == "" {
		v = "--"
		dim = " dim"
	}
	return `<div class="meta-card"><div class="k">` + html.EscapeString(k) + `</div><div class="v` + dim + `">` + html.EscapeString(v) + `</div></div>`
}

func fmtPrice(p *float64) string {
	if p == nil {
		return ""
	}
	if *p == 0 {
		return ""
	}
	return strconv.FormatFloat(*p, 'f', 2, 64)
}

func initialOf(name string) string {
	r := []rune(strings.TrimSpace(name))
	if len(r) == 0 {
		return "?"
	}
	return string(r[0])
}

// ── 最小化 markdown → HTML 转换器 ────────────────────────────────
//
// 不引入第三方库（避免新增依赖），手写支持：
//   - 标题 # / ## / ###
//   - 无序列表 -
//   - 段落（连续行合并）
//   - 粗体 **x**、斜体 *x*、行内代码 `x`
//   - 链接 [text](url)  → 渲染成 <a target=_blank>
//   - 引用 > x
//   - 水平分隔 ---
//   - 表格（| a | b | / |---|---| 简化版）
//
// LLM 偶发输出更复杂的 markdown（如嵌套列表、代码块），我们用降级策略：
// 不识别的行原样 escape 输出，不会崩；UI 上看着会少格式但内容仍可读。

var (
	reBold   = regexp.MustCompile(`\*\*([^*]+)\*\*`)
	reItalic = regexp.MustCompile(`\*([^*]+)\*`)
	reCode   = regexp.MustCompile("`([^`]+)`")
	reLink   = regexp.MustCompile(`\[([^\]]+)\]\(([^)\s]+)\)`)
	reTable  = regexp.MustCompile(`^\|.+\|$`)
)

func markdownToHTML(src string) string {
	if src == "" {
		return ""
	}
	lines := strings.Split(strings.ReplaceAll(src, "\r\n", "\n"), "\n")
	var out strings.Builder
	var (
		inUL    bool
		inPara  []string
		inQuote []string
		// table state
		inTable   bool
		tableRows [][]string
	)

	flushPara := func() {
		if len(inPara) == 0 {
			return
		}
		out.WriteString("<p>")
		out.WriteString(inlineRender(strings.Join(inPara, " ")))
		out.WriteString("</p>")
		inPara = inPara[:0]
	}
	flushUL := func() {
		if inUL {
			out.WriteString("</ul>")
			inUL = false
		}
	}
	flushQuote := func() {
		if len(inQuote) == 0 {
			return
		}
		out.WriteString("<blockquote>")
		out.WriteString(inlineRender(strings.Join(inQuote, " ")))
		out.WriteString("</blockquote>")
		inQuote = inQuote[:0]
	}
	flushTable := func() {
		if !inTable {
			return
		}
		out.WriteString("<table>")
		for i, row := range tableRows {
			if i == 0 {
				out.WriteString("<thead><tr>")
				for _, c := range row {
					out.WriteString("<th>" + inlineRender(strings.TrimSpace(c)) + "</th>")
				}
				out.WriteString("</tr></thead><tbody>")
			} else {
				out.WriteString("<tr>")
				for _, c := range row {
					out.WriteString("<td>" + inlineRender(strings.TrimSpace(c)) + "</td>")
				}
				out.WriteString("</tr>")
			}
		}
		out.WriteString("</tbody></table>")
		inTable = false
		tableRows = nil
	}
	flushAll := func() {
		flushPara()
		flushUL()
		flushQuote()
		flushTable()
	}

	for _, raw := range lines {
		line := strings.TrimRight(raw, " \t")
		trim := strings.TrimSpace(line)

		if trim == "" {
			flushAll()
			continue
		}

		// 水平分隔
		if trim == "---" || trim == "***" {
			flushAll()
			out.WriteString("<hr/>")
			continue
		}

		// 标题
		if strings.HasPrefix(trim, "### ") {
			flushAll()
			out.WriteString("<h3>" + inlineRender(strings.TrimPrefix(trim, "### ")) + "</h3>")
			continue
		}
		if strings.HasPrefix(trim, "## ") {
			flushAll()
			out.WriteString("<h2>" + inlineRender(strings.TrimPrefix(trim, "## ")) + "</h2>")
			continue
		}
		if strings.HasPrefix(trim, "# ") {
			flushAll()
			out.WriteString("<h1>" + inlineRender(strings.TrimPrefix(trim, "# ")) + "</h1>")
			continue
		}

		// 表格
		if reTable.MatchString(trim) {
			if !inTable {
				flushPara()
				flushUL()
				flushQuote()
				inTable = true
			}
			cols := splitTableRow(trim)
			// 第二行通常是 |---|---| 分隔，仅用于判别，不渲染
			if isTableDivider(cols) {
				continue
			}
			tableRows = append(tableRows, cols)
			continue
		}
		if inTable {
			flushTable()
		}

		// 列表
		if strings.HasPrefix(trim, "- ") || strings.HasPrefix(trim, "* ") {
			flushPara()
			flushQuote()
			if !inUL {
				out.WriteString("<ul>")
				inUL = true
			}
			out.WriteString("<li>")
			out.WriteString(inlineRender(strings.TrimSpace(trim[2:])))
			out.WriteString("</li>")
			continue
		}
		flushUL()

		// 引用
		if strings.HasPrefix(trim, "> ") {
			flushPara()
			inQuote = append(inQuote, strings.TrimSpace(trim[2:]))
			continue
		}
		flushQuote()

		// 普通段落（连续行合并）
		inPara = append(inPara, trim)
	}
	flushAll()

	return out.String()
}

func inlineRender(s string) string {
	out := html.EscapeString(s)
	// 顺序：代码 → 链接 → 粗体 → 斜体（避免相互吞并）
	out = reCode.ReplaceAllString(out, "<code>$1</code>")
	out = reLink.ReplaceAllString(out, `<a href="$2" target="_blank" rel="noopener">$1</a>`)
	out = reBold.ReplaceAllString(out, "<strong>$1</strong>")
	out = reItalic.ReplaceAllString(out, "<em>$1</em>")
	return out
}

func splitTableRow(line string) []string {
	// 去掉首尾 |，再按 | 切分
	line = strings.TrimPrefix(strings.TrimSuffix(line, "|"), "|")
	parts := strings.Split(line, "|")
	out := make([]string, len(parts))
	for i, p := range parts {
		out[i] = strings.TrimSpace(p)
	}
	return out
}

func isTableDivider(cols []string) bool {
	for _, c := range cols {
		t := strings.TrimSpace(c)
		t = strings.TrimLeft(t, ":")
		t = strings.TrimRight(t, ":")
		if t == "" {
			return false
		}
		for _, ch := range t {
			if ch != '-' {
				return false
			}
		}
	}
	return true
}
