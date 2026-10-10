# 生成「喜爱」的正式 App 图标：纸墨金。产物两处：
#   1. marketing/logo/icons/喜爱_appicon_1024.png （版式总览用）
#   2. assets/branding/app_icon.png             （flutter_launcher_icons 的输入）
# 另出一张多尺寸对照图，用来检查 29px 下还读不读得出来。
#
# 用法：
#   python marketing/logo/tools/outline_glyph.py
#   powershell -ExecutionPolicy Bypass -File marketing/logo/build-xiai.ps1
#   flutter pub run flutter_launcher_icons

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Resolve-Path (Join-Path $here "..\..")
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
    throw "缺少 src/xi-900.path，请先执行：python marketing/logo/tools/outline_glyph.py"
}
$xi = [System.IO.File]::ReadAllText($xiPath, [System.Text.Encoding]::UTF8).Trim()

function Render {
    param([string]$Page, [int]$W, [int]$H, [string]$Out, [double]$Scale = 2)
    if (Test-Path $Out) { Remove-Item -LiteralPath $Out -Force }
    $uri = ([System.Uri]$Page).AbsoluteUri
    Start-Process -FilePath $chrome -ArgumentList @(
        "--headless=new", "--disable-gpu", "--hide-scrollbars",
        "--default-background-color=00000000",
        "--force-device-scale-factor=$Scale",
        "--virtual-time-budget=2500",
        "--window-size=$([int]($W / $Scale)),$([int]($H / $Scale))",
        "--screenshot=$Out", $uri
    ) -Wait -WindowStyle Hidden `
        -RedirectStandardError (Join-Path $env:TEMP "xiai_icon.err.log") `
        -RedirectStandardOutput (Join-Path $env:TEMP "xiai_icon.out.log")
    if (-not (Test-Path $Out)) { throw "渲染失败：$Out" }
}

$svg = [System.IO.File]::ReadAllText(
    (Join-Path $src "icon-xiai-template.svg"), [System.Text.Encoding]::UTF8
).Replace("{{XI_PATH}}", $xi)
[System.IO.File]::WriteAllText(
    (Join-Path $iconDir "喜爱_appicon.svg"), $svg,
    (New-Object System.Text.UTF8Encoding($false)))

$css = 'html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#F1EBDD}svg{display:block;width:100%;height:100%}'

# ── 1. 主图标 1024 ──────────────────────────────────────────────────
$page = Join-Path $here "render-xiai-icon.html"
[System.IO.File]::WriteAllText($page,
    '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><style>' + $css +
    '</style></head><body>' + $svg + '</body></html>',
    (New-Object System.Text.UTF8Encoding($false)))

$icon1024 = Join-Path $iconDir "喜爱_appicon_1024.png"
Render -Page $page -W 1024 -H 1024 -Out $icon1024
Write-Host "[ok] 喜爱_appicon_1024.png"

# ── 2. 交给 flutter_launcher_icons 的源图 ───────────────────────────
Copy-Item -LiteralPath $icon1024 -Destination (Join-Path $repo "assets\branding\app_icon.png") -Force
Write-Host "[ok] assets/branding/app_icon.png"

# Android 自适应图标的前景层：透明底、内容缩进到安全区
$fgSvg = [System.IO.File]::ReadAllText(
    (Join-Path $src "icon-xiai-foreground.svg"), [System.Text.Encoding]::UTF8
).Replace("{{XI_PATH}}", $xi)
[System.IO.File]::WriteAllText((Join-Path $iconDir "喜爱_appicon_foreground.svg"),
    $fgSvg, (New-Object System.Text.UTF8Encoding($false)))

$fgCss = 'html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:transparent}svg{display:block;width:100%;height:100%}'
$fgPage = Join-Path $here "render-xiai-foreground.html"
[System.IO.File]::WriteAllText($fgPage,
    '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><style>' + $fgCss +
    '</style></head><body>' + $fgSvg + '</body></html>',
    (New-Object System.Text.UTF8Encoding($false)))
Render -Page $fgPage -W 1024 -H 1024 -Out (Join-Path $repo "assets\branding\app_icon_foreground.png")
Write-Host "[ok] assets/branding/app_icon_foreground.png"

# ── 3. 多尺寸对照：主屏尺寸下还读不读得出来 ─────────────────────────
$sizes = @(29, 44, 60, 76, 120)
$parts = foreach ($s in $sizes) {
    '<div class="sz"><div class="box" style="width:' + $s + 'px;height:' + $s +
    'px">' + $svg + '</div><span>' + $s + 'px</span></div>'
}
$board = @'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>喜爱 · 图标</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{width:1120px;background:#EFEAE0;color:#1F1C17;
       font-family:"PingFang SC","Microsoft YaHei","Noto Sans SC",sans-serif;
       padding:40px 44px}
  h1{font-size:24px;letter-spacing:2px}
  h1 em{font-style:normal;color:#9E6322}
  header p{margin-top:8px;font-size:13px;color:#5F5850;line-height:1.8}
  h2{margin:30px 0 14px;font-size:13px;letter-spacing:1.6px;color:#9E6322}
  .row{display:flex;gap:26px;align-items:flex-start}
  .big{width:340px;height:340px;border-radius:76px;overflow:hidden;
       box-shadow:0 10px 30px rgba(42,33,24,.18)}
  .big svg{width:100%;height:100%;display:block}
  .strip{display:flex;align-items:flex-end;gap:22px;background:#fff;
         border-radius:14px;padding:22px 26px}
  .sz{display:flex;flex-direction:column;align-items:center;gap:8px}
  .box{border-radius:22%;overflow:hidden;box-shadow:0 2px 6px rgba(42,33,24,.16)}
  .box svg{width:100%;height:100%;display:block}
  .sz span{font-size:10px;color:#7C746A}
  .wall{display:flex;gap:22px;margin-top:6px}
  .phone{width:250px;height:250px;border-radius:30px;display:grid;
         grid-template-columns:repeat(3,1fr);gap:18px;padding:34px 26px}
  .phone.light{background:linear-gradient(160deg,#FBF7F0 0%,#E3DCCB 100%)}
  .phone.dark{background:linear-gradient(160deg,#2A2620 0%,#14120F 100%)}
  .app{width:52px;height:52px;border-radius:13px;overflow:hidden;
       box-shadow:0 3px 8px rgba(0,0,0,.22)}
  .app svg{width:100%;height:100%;display:block}
  .app.ph{background:rgba(0,0,0,.07)}
  .phone.dark .app.ph{background:rgba(255,255,255,.10)}
</style>
</head>
<body>
  <header>
    <h1>喜爱 · <em>纸上墨金</em></h1>
    <p>纸底 + 墨字「喜」+ 墨金四角星。四角星是从「喜宽」带过来的品牌记号，
       换掉的是它所在的世界：从深黑底上的亮金黄，落到暖纸上的墨与金。</p>
  </header>
  <h2>主图标</h2>
  <div class="row">
    <div class="big">{{SVG}}</div>
    <div>
      <div class="strip">{{SIZES}}</div>
    </div>
  </div>
  <h2>主屏实际观感</h2>
  <div class="wall">
    <div class="phone light"><div class="app">{{SVG}}</div><div class="app ph"></div><div class="app ph"></div><div class="app ph"></div><div class="app ph"></div><div class="app ph"></div></div>
    <div class="phone dark"><div class="app">{{SVG}}</div><div class="app ph"></div><div class="app ph"></div><div class="app ph"></div><div class="app ph"></div><div class="app ph"></div></div>
  </div>
</body>
</html>
'@

$board = $board.Replace("{{SVG}}", $svg).Replace("{{SIZES}}", ($parts -join ""))
$boardPage = Join-Path $here "xiai-board.html"
[System.IO.File]::WriteAllText($boardPage, $board,
    (New-Object System.Text.UTF8Encoding($false)))
Render -Page $boardPage -W 1120 -H 1000 -Out (Join-Path $here "喜爱_图标总览.png") -Scale 1
Write-Host "[ok] 喜爱_图标总览.png"
Write-Host ""
Write-Host "下一步：flutter pub run flutter_launcher_icons"
