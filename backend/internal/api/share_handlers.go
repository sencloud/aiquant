package api

import (
	"bytes"
	"context"
	"errors"
	"html/template"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/extension"
	gmhtml "github.com/yuin/goldmark/renderer/html"

	"github.com/sencloud/finme-backend/internal/platform"
)

const (
	maxShareAnswerLen   = 64 * 1024
	maxShareQuestionLen = 4 * 1024
)

// markdownEngine：开启 GFM（表格 / 删除线 / 链接化），默认不渲染裸 HTML，
// 因此 AI 正文里夹带的 <script> 等会被转义，分享页天然安全。
var markdownEngine = goldmark.New(
	goldmark.WithExtensions(extension.GFM),
	goldmark.WithRendererOptions(gmhtml.WithHardWraps()),
)

// mountAIShare 挂载分享创建（受 JWT 保护）。
func mountAIShare(r chi.Router, d *Deps) {
	r.Post("/ai/share", handleCreateShare(d))
}

// handleCreateShare 把一条问答存成分享，返回 { id, url }。
func handleCreateShare(d *Deps) http.HandlerFunc {
	type reqBody struct {
		Question string `json:"question,omitempty"`
		Answer   string `json:"answer"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		uc := MustUser(r)
		if d.Share == nil {
			WriteError(w, r, platform.ErrUnavailable("SHARE.NOT_CONFIGURED", errors.New("share repo nil")))
			return
		}
		var body reqBody
		if err := DecodeJSON(r, &body); err != nil {
			WriteError(w, r, err)
			return
		}
		answer := strings.TrimSpace(body.Answer)
		if answer == "" {
			WriteError(w, r, platform.ErrBadRequest("SHARE.EMPTY", "分享内容为空", nil))
			return
		}
		if len(answer) > maxShareAnswerLen {
			answer = answer[:maxShareAnswerLen]
		}
		question := strings.TrimSpace(body.Question)
		if len(question) > maxShareQuestionLen {
			question = question[:maxShareQuestionLen]
		}

		s, err := d.Share.Create(r.Context(), uc.UserID, question, answer)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("SHARE.CREATE", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"id":  s.ID,
			"url": shareURL(r, s.ID),
		})
	}
}

// handleSharePage 公开渲染分享网页（无需登录）。
func handleSharePage(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := chi.URLParam(r, "id")
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		if d.Share == nil {
			w.WriteHeader(http.StatusNotFound)
			_ = shareNotFoundTpl.Execute(w, nil)
			return
		}
		s, err := d.Share.Get(r.Context(), id)
		if err != nil {
			w.WriteHeader(http.StatusNotFound)
			_ = shareNotFoundTpl.Execute(w, nil)
			return
		}

		var buf bytes.Buffer
		if err := markdownEngine.Convert([]byte(s.Answer), &buf); err != nil {
			buf.Reset()
			buf.WriteString(template.HTMLEscapeString(s.Answer))
		}

		w.Header().Set("Cache-Control", "public, max-age=600")
		_ = sharePageTpl.Execute(w, sharePageData{
			Question:    s.Question,
			AnswerRaw:   template.HTML(buf.String()), //nolint:gosec // goldmark 默认转义裸 HTML
			Date:        time.UnixMilli(s.CreatedAt).Format("2006-01-02 15:04"),
			DownloadURL: downloadURL(r.Context(), d, s.UserID),
		})
	}
}

// downloadURL 拼接「下载落地页」链接：带上创建者邀请码做拉新归因。
// 取不到邀请码(未配置/异常)时退化为无 ref 的下载页。
func downloadURL(ctx context.Context, d *Deps, userID int64) string {
	const base = "https://www.singzquant.com/d/"
	if d.Invite == nil {
		return base
	}
	code, err := d.Invite.EnsureCode(ctx, userID)
	if err != nil || code == "" {
		return base
	}
	return base + "?ref=" + url.QueryEscape(code) + "&utm_source=share"
}

// shareURL 用请求自身的 host/scheme 拼分享链接（部署在 api.singzquant.com 时即
// https://api.singzquant.com/s/{id}）。
func shareURL(r *http.Request, id string) string {
	scheme := "https"
	if p := r.Header.Get("X-Forwarded-Proto"); p != "" {
		scheme = p
	} else if r.TLS == nil {
		scheme = "http"
	}
	return scheme + "://" + r.Host + "/s/" + id
}

type sharePageData struct {
	Question    string
	AnswerRaw   template.HTML
	Date        string
	DownloadURL string
}

var sharePageTpl = template.Must(template.New("share").Parse(sharePageHTML))
var shareNotFoundTpl = template.Must(template.New("404").Parse(shareNotFoundHTML))

const sharePageHTML = `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>喜宽 · AI 投资助理</title>
<meta name="description" content="来自喜宽 AI 投资助理的对话内容，仅供参考。">
<meta property="og:title" content="喜宽 · AI 投资助理">
<meta property="og:description" content="来自喜宽 AI 投资助理的对话内容，仅供参考。">
<meta property="og:type" content="article">
<meta property="og:image" content="https://www.singzquant.com/og.png">
<meta property="og:url" content="https://www.singzquant.com">
<style>
:root{--accent:#D97706;--bg:#F5F2EA;--card:#fff;--fg:#1A1A1A;--fg2:#5A5A5A;--fg3:#999;--soft:#FAF5EC;--border:#E6E1D5}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.7 -apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif;-webkit-font-smoothing:antialiased}
.wrap{max-width:680px;margin:0 auto;padding:16px}
.card{background:var(--card);border:1px solid var(--border);border-radius:16px;overflow:hidden}
.head{display:flex;align-items:center;gap:10px;padding:16px 18px;background:linear-gradient(135deg,#FCE7B5,#FFF4D8)}
.logo{width:38px;height:38px;border-radius:10px;background:var(--accent);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:20px}
.head h1{margin:0;font-size:15px;color:var(--accent);font-weight:800;letter-spacing:.4px}
.head p{margin:2px 0 0;font-size:11px;color:var(--fg2)}
.head .date{margin-left:auto;font-size:11px;color:var(--fg3)}
.label{display:flex;align-items:center;gap:6px;font-size:11px;font-weight:800;letter-spacing:.6px;color:var(--fg2);margin:0 0 8px}
.dot{width:16px;height:16px;border-radius:4px;background:var(--accent)}
.q{margin:16px 18px 0}
.q .box{background:var(--soft);border:1px solid var(--border);border-radius:10px;padding:10px 12px;font-size:13.5px;color:var(--fg);white-space:pre-wrap}
.a{padding:16px 18px 18px}
.a .md>:first-child{margin-top:0}
.a h1,.a h2,.a h3{font-weight:800;line-height:1.35}
.a h1{font-size:20px}.a h2{font-size:17px}.a h3{font-size:15px}
.a code{background:var(--soft);color:var(--accent);font-family:ui-monospace,Menlo,monospace;font-size:.88em;padding:1px 4px;border-radius:4px}
.a pre{background:var(--soft);border:1px solid var(--border);border-radius:6px;padding:12px;overflow:auto}
.a pre code{background:none;color:var(--fg);padding:0}
.a blockquote{margin:10px 0;padding:6px 12px;background:var(--soft);border-left:3px solid var(--accent);color:var(--fg2)}
.a table{border-collapse:collapse;width:100%;font-size:13px;margin:10px 0}
.a th,.a td{border:1px solid var(--border);padding:6px 8px;text-align:left}
.a th{background:var(--soft);font-weight:800}
.a img{max-width:100%}
.foot{display:flex;align-items:center;gap:6px;padding:12px 18px 16px;background:var(--soft);border-top:1px solid var(--border);font-size:11px;color:var(--fg3)}
.brand{margin-left:auto;background:var(--accent);color:#fff;font-weight:800;font-size:11px;letter-spacing:.5px;padding:3px 9px;border-radius:10px;text-decoration:none}
.tip{max-width:680px;margin:14px auto 28px;padding:0 18px;font-size:11px;color:var(--fg3);text-align:center;line-height:1.7}
.dl{display:flex;align-items:center;justify-content:center;gap:8px;max-width:680px;margin:16px auto 0;padding:14px;background:var(--accent);color:#fff;border-radius:14px;font-weight:800;font-size:15px;text-decoration:none;box-shadow:0 6px 18px rgba(217,118,6,.25)}
.dl:active{opacity:.85}
.dl small{font-weight:600;opacity:.85;font-size:11px}
</style>
</head>
<body>
<div class="wrap">
  <div class="card">
    <div class="head">
      <div class="logo">喜</div>
      <div>
        <h1>喜宽 · AI 投资助理</h1>
        <p>由喜宽生成的对话内容 · 仅供参考</p>
      </div>
      <span class="date">{{.Date}}</span>
    </div>
    {{if .Question}}
    <div class="q">
      <p class="label"><span class="dot"></span>我的提问</p>
      <div class="box">{{.Question}}</div>
    </div>
    {{end}}
    <div class="a">
      <p class="label"><span class="dot"></span>AI 回答</p>
      <div class="md">{{.AnswerRaw}}</div>
    </div>
    <div class="foot">
      <span>喜宽 AI 助理</span>
      <a class="brand" href="https://www.singzquant.com">singzquant.com</a>
    </div>
  </div>
  <a class="dl" href="{{.DownloadURL}}">下载喜宽 App，体验 AI 投研助理 <small>· 填邀请码得螺壳</small></a>
  <p class="tip">本内容由 AI 生成，不构成任何投资建议。投资有风险，决策需谨慎。</p>
</div>
</body>
</html>`

const shareNotFoundHTML = `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>内容不存在 · 喜宽</title>
<style>body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#F5F2EA;color:#5A5A5A;font:15px/1.6 -apple-system,"PingFang SC",sans-serif}
.b{text-align:center}.b .c{font-size:28px;font-weight:800;color:#D97706}</style></head>
<body><div class="b"><div class="c">喜宽</div><p>分享内容不存在或已过期</p></div></body></html>`
