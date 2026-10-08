# 生成喜宽正式 App 图标（三个候选）与「真实场景」效果图。
#
# 用法：
#   python marketing/logo/tools/outline_xi.py      # 先生成 src/xi-900.path
#   powershell -ExecutionPolicy Bypass -File marketing/logo/build-final.ps1

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $here "src"
$iconDir = Join-Path $here "icons"
New-Item -ItemType Directory -Force -Path $iconDir | Out-Null

$chrome = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw "找不到 Chrome/Edge，无法渲染。" }

$xiPath = Join-Path $src "xi-900.path"
if (-not (Test-Path $xiPath)) {
    throw "缺少 src/xi-900.path，请先执行：python marketing/logo/tools/outline_xi.py"
}
$xi = [System.IO.File]::ReadAllText($xiPath, [System.Text.Encoding]::UTF8).Trim()

function Render {
    param([string]$Page, [int]$W, [int]$H, [string]$Out, [double]$Scale = 2)
    if (Test-Path $Out) { Remove-Item -LiteralPath $Out -Force }
    $uri = ([System.Uri]$Page).AbsoluteUri
    $chromeArgs = @(
        "--headless=new", "--disable-gpu", "--hide-scrollbars",
        "--force-device-scale-factor=$Scale",
        "--virtual-time-budget=2500",
        "--window-size=$([int]($W / $Scale)),$([int]($H / $Scale))",
        "--screenshot=$Out", $uri
    )
    Start-Process -FilePath $chrome -ArgumentList $chromeArgs -Wait -WindowStyle Hidden `
        -RedirectStandardError (Join-Path $env:TEMP "xikuan_final.err.log") `
        -RedirectStandardOutput (Join-Path $env:TEMP "xikuan_final.out.log")
    if (-not (Test-Path $Out)) { throw "渲染失败：$Out" }
}

$variants = @(
    @{ t = "icon-A-template.svg"; n = "喜宽_appicon_A_推荐"; d = "「喜」精确居中，背景加一层中心暖光，不再是死黑。" },
    @{ t = "icon-B-template.svg"; n = "喜宽_appicon_B_小尺寸优化"; d = "字放大到 590，只留一颗星；29px 下更稳。" },
    @{ t = "icon-C-template.svg"; n = "喜宽_appicon_C_原稿"; d = "完全等于你看中的那张，未做任何调整。" }
)

$miniCss = 'html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#0b0b0c}svg{display:block;width:100%;height:100%}'
$finals = @()

foreach ($v in $variants) {
    $svg = [System.IO.File]::ReadAllText((Join-Path $src $v.t), [System.Text.Encoding]::UTF8).Replace("{{XI_PATH}}", $xi)
    $svgOut = Join-Path $iconDir ($v.n + ".svg")
    [System.IO.File]::WriteAllText($svgOut, $svg, (New-Object System.Text.UTF8Encoding($false)))

    $page = Join-Path $here ("render-" + $v.t + ".html")
    $html = '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><style>' + $miniCss + '</style></head><body>' + $svg + '</body></html>'
    [System.IO.File]::WriteAllText($page, $html, (New-Object System.Text.UTF8Encoding($false)))

    Render -Page $page -W 1024 -H 1024 -Out (Join-Path $iconDir ($v.n + ".png"))
    Write-Host ("[ok] {0}.png / .svg" -f $v.n)
    $finals += @{ name = $v.n; d = $v.d; svg = $svg }
}

# ── 真实场景效果图 ──────────────────────────────────────────────────
function Size-Strip {
    param([string]$Svg)
    $parts = foreach ($s in @(29, 44, 60, 76)) {
        '<div class="sz"><div class="szbox" style="width:' + $s + 'px;height:' + $s + 'px">' +
        $Svg + '</div><span>' + $s + 'px</span></div>'
    }
    return '<div class="strip">' + ($parts -join '') + '</div>'
}

$cards = foreach ($f in $finals) {
    '<div class="card"><div class="art">' + $f.svg + '</div><h3>' +
    $f.name.Replace("喜宽_appicon_", "") + '</h3><p>' + $f.d + '</p>' + (Size-Strip -Svg $f.svg) + '</div>'
}

$hero = $finals[0].svg
$appsHtml = ""
for ($i = 0; $i -lt 8; $i++) {
    if ($i -eq 0) {
        $appsHtml += '<div class="app"><div class="ico">' + $hero + '</div><div class="lbl">喜宽</div></div>'
    } else {
        $appsHtml += '<div class="app"><div class="ico ph"></div><div class="lbl">&nbsp;</div></div>'
    }
}

$board = @'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>喜宽 · 图标定稿</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{width:1200px;background:#0b0b0c;color:#e8e6e3;
       font-family:"Noto Sans SC","Microsoft YaHei","PingFang SC",sans-serif;padding:36px 40px 34px}
  h1{font-size:26px;font-weight:900}
  h1 em{font-style:normal;color:#f0a02a}
  header p{margin-top:8px;font-size:13px;color:#8f8a83;line-height:1.6}
  h2{margin:32px 0 14px;font-size:15px;font-weight:800;color:#f0a02a;letter-spacing:1px}
  .grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}
  .card{background:#141416;border:1px solid #262628;border-radius:14px;padding:16px}
  .card:first-child{border-color:#4a3d2a}
  .art{height:200px;display:flex;align-items:center;justify-content:center;background:#0b0b0c;border-radius:10px}
  .art svg{width:200px;height:200px;border-radius:10px}
  .card h3{margin-top:12px;font-size:14px;font-weight:800}
  .card p{margin-top:5px;font-size:11.5px;line-height:1.55;color:#8f8a83}
  .strip{display:flex;align-items:flex-end;gap:16px;margin-top:14px;padding-top:12px;border-top:1px solid #222}
  .sz{display:flex;flex-direction:column;align-items:center;gap:5px}
  .szbox{border-radius:22%;overflow:hidden;background:#0b0b0c}
  .szbox svg{width:100%;height:100%;display:block}
  .sz span{font-size:9.5px;color:#6b6660}
  .scenes{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}
  .phone{height:520px;border-radius:34px;overflow:hidden;position:relative;padding:26px 18px}
  .phone.dark{background:linear-gradient(160deg,#20222c 0%,#0d0e13 60%,#16181f 100%)}
  .phone.light{background:linear-gradient(160deg,#eef0f4 0%,#d9dde6 60%,#e8ebf1 100%)}
  .apps{display:grid;grid-template-columns:repeat(4,1fr);gap:18px 14px}
  .app{display:flex;flex-direction:column;align-items:center;gap:6px}
  .ico{width:58px;height:58px;border-radius:14px;overflow:hidden;box-shadow:0 4px 10px rgba(0,0,0,.45)}
  .ico svg{width:100%;height:100%;display:block}
  .ico.ph{background:rgba(255,255,255,.10)}
  .phone.light .ico.ph{background:rgba(0,0,0,.08);box-shadow:0 4px 10px rgba(0,0,0,.12)}
  .phone.light .ico{box-shadow:0 4px 10px rgba(0,0,0,.18)}
  .lbl{font-size:9.5px;color:rgba(255,255,255,.9)}
  .phone.light .lbl{color:rgba(0,0,0,.75)}
  .srwrap{background:#141416;border:1px solid #262628;border-radius:14px;padding:18px}
  .sr{background:#f7f7f7;border-radius:14px;padding:16px;display:flex;align-items:center;gap:14px;color:#1a1a1a}
  .sr .sico{width:64px;height:64px;border-radius:15px;overflow:hidden;flex:none}
  .sr .sico svg{width:100%;height:100%;display:block}
  .sr .tx b{display:block;font-size:16px;font-weight:800}
  .sr .tx i{display:block;font-style:normal;font-size:12.5px;color:#6b6b6b;margin-top:3px}
  .sr .tx em{display:block;font-style:normal;font-size:11px;color:#9a9a9a;margin-top:6px}
  .sr .btn{margin-left:auto;background:#e9e9e9;color:#0a7cff;font-size:14px;font-weight:800;
           border-radius:999px;padding:7px 20px}
</style>
</head>
<body>
  <header>
    <h1>喜宽 · <em>图标定稿</em></h1>
    <p>A 把你选中的方向做了两处工程化修正（字形转矢量轮廓、精确居中）；B 是给小尺寸做的加强版；C 完全等于原稿。下面同时给出主屏与商店搜索里的真实观感。</p>
  </header>
  <div class="grid3">{{CARDS}}</div>
  <h2>主屏幕实际效果（左：深色壁纸　右：浅色壁纸）</h2>
  <div class="scenes">
    <div class="phone dark"><div class="apps">{{APPS}}</div></div>
    <div class="phone light"><div class="apps">{{APPS}}</div></div>
    <div class="srwrap"><div class="sr">
      <div class="sico">{{HERO}}</div>
      <div class="tx"><b>喜宽</b><i>AI 投研助理</i><em>免费 · App 内购买</em></div>
      <div class="btn">获取</div>
    </div></div>
  </div>
</body>
</html>
'@

$board = $board.Replace("{{CARDS}}", ($cards -join ""))
$board = $board.Replace("{{APPS}}", $appsHtml)
$board = $board.Replace("{{HERO}}", $hero)

$page = Join-Path $here "final-board.html"
[System.IO.File]::WriteAllText($page, $board, (New-Object System.Text.UTF8Encoding($false)))
$out = Join-Path $here "喜宽_图标定稿对比.png"
Render -Page $page -W 1200 -H 1140 -Out $out -Scale 1
Write-Host "[ok] 喜宽_图标定稿对比.png"
Write-Host ""
Write-Host "输出目录：$iconDir"
