# 渲染喜宽 Logo 方案。
#
# 用法（仓库根目录或本目录下均可执行）：
#   powershell -ExecutionPolicy Bypass -File marketing/logo/build.ps1
#
# 产出：
#   - 每个方案的 1024×1024 App 图标 PNG（可直接上传 / 替换 assets/branding/app_icon.png）
#   - 一张方案总览图（含现状对比、小尺寸可读性检查、配色策略、横版组合标）
#
# 设计稿按 CSS px 排版，用 --force-device-scale-factor=2 输出 2 倍图。

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $here "src"
$repo = (Resolve-Path (Join-Path $here "..\..")).Path

$chrome = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw "找不到 Chrome/Edge，无法渲染。" }

function Render {
    param([string]$Page, [int]$W, [int]$H, [string]$Out, [double]$Scale = 2)

    if (Test-Path $Out) { Remove-Item -LiteralPath $Out -Force }
    $uri = ([System.Uri]$Page).AbsoluteUri
    $logOut = Join-Path $env:TEMP "xikuan_logo.out.log"
    $logErr = Join-Path $env:TEMP "xikuan_logo.err.log"
    $chromeArgs = @(
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        "--force-device-scale-factor=$Scale",
        "--virtual-time-budget=2500",
        "--window-size=$([int]($W / $Scale)),$([int]($H / $Scale))",
        "--screenshot=$Out",
        $uri
    )
    Start-Process -FilePath $chrome -ArgumentList $chromeArgs -Wait -WindowStyle Hidden `
        -RedirectStandardError $logErr -RedirectStandardOutput $logOut
    if (-not (Test-Path $Out)) { throw "渲染失败：$Out" }
}

# ── 一、每个方案单独出 1024×1024 App 图标 ────────────────────────────
$marks = @(
    @{ f = "mark-1-uptrend.svg";  n = "喜宽_logo_1_上扬行情线";  d = "最干净的一稿：一条上行的行情折线，末端一颗光点。" },
    @{ f = "mark-2-chat.svg";     n = "喜宽_logo_2_对话气泡";    d = "对话气泡里装着行情线：AI 问答 + 行情，最贴产品。" },
    @{ f = "mark-3-openbox.svg";  n = "喜宽_logo_3_开口方框";    d = "方框右上角被推开、留出缺口：把「宽」画成空间。" },
    @{ f = "mark-4-roof.svg";     n = "喜宽_logo_4_宽字宀头";    d = "「宽」的宝盖头罩着一条上行线：宽绰的空间里向上。" },
    @{ f = "mark-5-candle.svg";   n = "喜宽_logo_5_单根K线";     d = "一根放大的圆角 K 线，形体感强，缩到最小也认得出。" },
    @{ f = "mark-6-xi-bright.svg";n = "喜宽_logo_6_喜字亮底";    d = "亮琥珀底 + 深色「喜」，商店列表里最跳，识别靠字。" },
    @{ f = "mark-7-xi-line.svg";  n = "喜宽_logo_7_喜字行情线";  d = "「喜」字压在上行线之上：名字 + 品类一句话说清。" },
    @{ f = "mark-8-xi-ai.svg";    n = "喜宽_logo_8_喜字AI星";    d = "「喜」字加 AI 星点，强化「AI 助理」这层身份。" }
)

$iconDir = Join-Path $here "icons"
New-Item -ItemType Directory -Force -Path $iconDir | Out-Null

$miniCss = 'html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#0b0b0c}svg{display:block;width:100%;height:100%}'

foreach ($m in $marks) {
    $svg = [System.IO.File]::ReadAllText((Join-Path $src $m.f), [System.Text.Encoding]::UTF8)
    $html = '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><style>' +
        $miniCss + '</style></head><body>' + $svg + '</body></html>'
    $page = Join-Path $here ("render-" + $m.f + ".html")
    [System.IO.File]::WriteAllText($page, $html, (New-Object System.Text.UTF8Encoding($false)))
    Render -Page $page -W 1024 -H 1024 -Out (Join-Path $iconDir ($m.n + ".png"))
    Write-Host ("[ok] {0}.png  1024x1024" -f $m.n)
}

# 配色策略三稿（同一图形，不同底）
$colorways = @(
    @{ f = "colorway-amber.svg"; n = "喜宽_logo_配色_亮琥珀底" },
    @{ f = "colorway-cream.svg"; n = "喜宽_logo_配色_浅米底" },
    @{ f = "colorway-mono.svg";  n = "喜宽_logo_配色_纯黑白" }
)
foreach ($c in $colorways) {
    $svg = [System.IO.File]::ReadAllText((Join-Path $src $c.f), [System.Text.Encoding]::UTF8)
    $html = '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><style>' +
        $miniCss + '</style></head><body>' + $svg + '</body></html>'
    $page = Join-Path $here ("render-" + $c.f + ".html")
    [System.IO.File]::WriteAllText($page, $html, (New-Object System.Text.UTF8Encoding($false)))
    Render -Page $page -W 1024 -H 1024 -Out (Join-Path $iconDir ($c.n + ".png"))
    Write-Host ("[ok] {0}.png  1024x1024" -f $c.n)
}

# ── 二、方案总览图 ──────────────────────────────────────────────────
# 对照用的旧图标已归档，assets/branding/app_icon.png 现在是新标。
$currentIcon = Join-Path $here "archive\app_icon_旧_三柱.png"
$currentData = ""
if (Test-Path $currentIcon) {
    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($currentIcon))
    $currentData = "data:image/png;base64,$b64"
}

function Size-Strip {
    param([string]$Svg)
    $sizes = @(29, 44, 64)
    $parts = foreach ($s in $sizes) {
        '<div class="sz"><div class="szbox" style="width:' + $s + 'px;height:' + $s + 'px">' +
        $Svg + '</div><span>' + $s + 'px</span></div>'
    }
    return '<div class="strip">' + ($parts -join '') + '</div>'
}

$cards = @()
if ($currentData -ne "") {
    $cards += '<div class="card cur"><div class="art"><img src="' + $currentData + '" alt=""></div>' +
        '<h3>现用图标（对照）</h3><p>三根竖向圆角柱：容易被读成柱状图 / 信号 / 暂停键，和「喜宽」这个名字没有关系。</p></div>'
}

foreach ($m in $marks) {
    $svg = [System.IO.File]::ReadAllText((Join-Path $src $m.f), [System.Text.Encoding]::UTF8)
    $cards += '<div class="card"><div class="art">' + $svg + '</div>' +
        '<h3>' + $m.n.Replace("喜宽_logo_", "") + '</h3><p>' + $m.d + '</p>' +
        (Size-Strip -Svg $svg) + '</div>'
}

$cwCards = foreach ($c in $colorways) {
    $svg = [System.IO.File]::ReadAllText((Join-Path $src $c.f), [System.Text.Encoding]::UTF8)
    '<div class="card"><div class="art">' + $svg + '</div><h3>' +
    $c.n.Replace("喜宽_logo_配色_", "") + '</h3>' + (Size-Strip -Svg $svg) + '</div>'
}

$lockSvg = [System.IO.File]::ReadAllText((Join-Path $src "mark-7-xi-line.svg"), [System.Text.Encoding]::UTF8)
$lockSvg2 = [System.IO.File]::ReadAllText((Join-Path $src "mark-1-uptrend.svg"), [System.Text.Encoding]::UTF8)

$boardHtml = @'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>喜宽 · Logo 方案总览</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{width:1200px;background:#0b0b0c;color:#e8e6e3;
       font-family:"Noto Sans SC","Microsoft YaHei","PingFang SC",sans-serif;padding:36px 40px 32px}
  header{margin-bottom:26px}
  h1{font-size:27px;font-weight:900;letter-spacing:.5px}
  h1 em{font-style:normal;color:#f0a02a}
  header p{margin-top:8px;font-size:13px;color:#8f8a83;line-height:1.6}
  h2{margin:30px 0 14px;font-size:15px;font-weight:800;color:#f0a02a;letter-spacing:1px}
  .grid{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}
  .card{background:#141416;border:1px solid #262628;border-radius:14px;padding:16px}
  .card.cur{border-color:#3a332a}
  .art{width:100%;height:200px;display:flex;align-items:center;justify-content:center;
       border-radius:10px;overflow:hidden;background:#0b0b0c}
  .art svg,.art img{width:200px;height:200px;display:block;border-radius:10px}
  .card h3{margin-top:12px;font-size:14px;font-weight:800}
  .card p{margin-top:5px;font-size:11.5px;line-height:1.55;color:#8f8a83;min-height:36px}
  .strip{display:flex;align-items:flex-end;gap:16px;margin-top:12px;padding-top:12px;border-top:1px solid #222}
  .sz{display:flex;flex-direction:column;align-items:center;gap:5px}
  .szbox{border-radius:22%;overflow:hidden;background:#0b0b0c}
  .szbox svg{width:100%;height:100%;display:block}
  .sz span{font-size:9.5px;color:#6b6660}
  .lock{display:flex;gap:22px;align-items:center;background:#141416;border:1px solid #262628;
        border-radius:14px;padding:26px 30px}
  .lock .lk{width:104px;height:104px;border-radius:23px;overflow:hidden;flex:none}
  .lock .lk svg{width:104px;height:104px;display:block}
  .lkname{font-size:52px;font-weight:900;line-height:1;letter-spacing:6px}
  .lksub{margin-top:12px;font-size:15px;color:#8f8a83;letter-spacing:5px}
  .two{display:grid;grid-template-columns:1fr 1fr;gap:18px}
</style>
</head>
<body>
  <header>
    <h1>喜宽 · <em>Logo 方案</em></h1>
    <p>5 个维度共 8 稿：字形（喜）／意象（宽）／品类（行情）／AI（对话·星）／配色策略。每稿都附 29 / 44 / 64px 的真实小尺寸检查，App 图标按 1024×1024 输出。</p>
  </header>
  <div class="grid">{{CARDS}}</div>
  <h2>配色策略 —— 同一个图形，三种底</h2>
  <div class="grid">{{COLORWAYS}}</div>
  <h2>横版组合标（图标 + 字标）</h2>
  <div class="two">
    <div class="lock"><div class="lk">{{LOCK7}}</div>
      <div><div class="lkname">喜宽</div><div class="lksub">AI 投研助理</div></div></div>
    <div class="lock"><div class="lk">{{LOCK1}}</div>
      <div><div class="lkname">喜宽</div><div class="lksub">AI 投研助理</div></div></div>
  </div>
</body>
</html>
'@

$boardHtml = $boardHtml.Replace("{{CARDS}}", ($cards -join ""))
$boardHtml = $boardHtml.Replace("{{COLORWAYS}}", ($cwCards -join ""))
$boardHtml = $boardHtml.Replace("{{LOCK7}}", $lockSvg)
$boardHtml = $boardHtml.Replace("{{LOCK1}}", $lockSvg2)

$boardPage = Join-Path $here "board.html"
[System.IO.File]::WriteAllText($boardPage, $boardHtml, (New-Object System.Text.UTF8Encoding($false)))
$boardOut = Join-Path $here "喜宽_logo_方案总览.png"
Render -Page $boardPage -W 1200 -H 2120 -Out $boardOut -Scale 1
Write-Host "[ok] 喜宽_logo_方案总览.png"

Write-Host ""
Write-Host "输出目录：$here\icons"
