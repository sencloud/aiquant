# 生成「喜AI」行情首页同款 App 图标：
#   深蓝渐变 + 白色抽象 A + 金色行情轨迹。
#
# 产物：
#   1. marketing/logo/icons/喜AI_行情AppIcon_1024.png
#   2. assets/branding/app_icon.png
#   3. Android 自适应前景 / 背景 PNG
#   4. 多尺寸检查总览
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File marketing/logo/build-xiai.ps1
#   dart run flutter_launcher_icons

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

function Render {
    param([string]$Page, [int]$W, [int]$H, [string]$Out, [double]$Scale = 2)
    if (Test-Path $Out) { Remove-Item -LiteralPath $Out -Force }
    $uri = ([System.Uri]$Page).AbsoluteUri
    $chromeArgs = @(
        "--headless=new", "--disable-gpu", "--hide-scrollbars",
        "--default-background-color=00000000",
        "--force-device-scale-factor=$Scale",
        "--virtual-time-budget=2500",
        "--window-size=$([int]($W / $Scale)),$([int]($H / $Scale))",
        "--user-data-dir=$(Join-Path $env:TEMP 'xiai-logo-market-render')",
        "--screenshot=$Out", $uri
    )
    $proc = Start-Process -FilePath $chrome -ArgumentList $chromeArgs -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardError (Join-Path $env:TEMP "xiai_market_icon.err.log") `
        -RedirectStandardOutput (Join-Path $env:TEMP "xiai_market_icon.out.log")
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-Path $Out) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path $Out)) { throw "渲染失败：$Out" }
}

function Write-RenderPage {
    param([string]$SvgPath, [string]$Background, [string]$Page)
    $svg = [System.IO.File]::ReadAllText($SvgPath, [System.Text.Encoding]::UTF8)
    $css = "html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:$Background}svg{display:block;width:100%;height:100%}"
    $html = '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><style>' +
        $css + '</style></head><body>' + $svg + '</body></html>'
    [System.IO.File]::WriteAllText(
        $Page, $html, (New-Object System.Text.UTF8Encoding($false)))
}

$mainSvg = Join-Path $src "icon-xiai-market.svg"
$fgSvg = Join-Path $src "icon-xiai-market-foreground.svg"
$bgSvg = Join-Path $src "icon-xiai-market-background.svg"

Copy-Item -LiteralPath $mainSvg -Destination (
    Join-Path $iconDir "喜AI_行情AppIcon.svg") -Force
Copy-Item -LiteralPath $fgSvg -Destination (
    Join-Path $iconDir "喜AI_行情AppIcon_foreground.svg") -Force
Copy-Item -LiteralPath $bgSvg -Destination (
    Join-Path $iconDir "喜AI_行情AppIcon_background.svg") -Force

$mainPage = Join-Path $here "render-xiai-market-icon.html"
$fgPage = Join-Path $here "render-xiai-market-foreground.html"
$bgPage = Join-Path $here "render-xiai-market-background.html"
Write-RenderPage $mainSvg "#0A1938" $mainPage
Write-RenderPage $fgSvg "transparent" $fgPage
Write-RenderPage $bgSvg "#0A1938" $bgPage

$icon1024 = Join-Path $iconDir "喜AI_行情AppIcon_1024.png"
Render -Page $mainPage -W 1024 -H 1024 -Out $icon1024
Copy-Item -LiteralPath $icon1024 -Destination (
    Join-Path $repo "assets\branding\app_icon.png") -Force
Render -Page $fgPage -W 1024 -H 1024 -Out (
    Join-Path $repo "assets\branding\app_icon_foreground.png")
Render -Page $bgPage -W 1024 -H 1024 -Out (
    Join-Path $repo "assets\branding\app_icon_background.png")

Write-Host "[ok] 喜AI_行情AppIcon_1024.png"
Write-Host "[ok] assets/branding/app_icon.png"
Write-Host "[ok] assets/branding/app_icon_foreground.png"
Write-Host "[ok] assets/branding/app_icon_background.png"

$svg = [System.IO.File]::ReadAllText($mainSvg, [System.Text.Encoding]::UTF8)
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
<title>喜AI · 行情图标</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{width:1120px;background:#EFEAE0;color:#1F1C17;
       font-family:"PingFang SC","Microsoft YaHei","Noto Sans SC",sans-serif;
       padding:40px 44px}
  h1{font-size:24px;letter-spacing:2px}
  h1 em{font-style:normal;color:#1C49C9}
  header p{margin-top:8px;font-size:13px;color:#5F5850;line-height:1.8}
  h2{margin:30px 0 14px;font-size:13px;letter-spacing:1.6px;color:#1C49C9}
  .row{display:flex;gap:34px;align-items:flex-start}
  .big{width:340px;height:340px;border-radius:76px;overflow:hidden;
       box-shadow:0 10px 30px rgba(10,25,56,.24)}
  .big svg{width:100%;height:100%;display:block}
  .strip{display:flex;align-items:flex-end;gap:22px;background:#fff;
         border-radius:14px;padding:22px 26px}
  .sz{display:flex;flex-direction:column;align-items:center;gap:8px}
  .box{border-radius:22%;overflow:hidden;box-shadow:0 2px 6px rgba(10,25,56,.2)}
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
    <h1>喜AI · <em>行情终端</em></h1>
    <p>与 App 首页左上角使用同一个标志：深海军蓝渐变底、白色抽象 A、
       金色横梁和向上行情轨迹。没有文字，确保在 29px 的 App Store
       搜索结果与手机主屏上仍能识别。</p>
  </header>
  <h2>主图标</h2>
  <div class="row">
    <div class="big">{{SVG}}</div>
    <div class="strip">{{SIZES}}</div>
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
$boardPage = Join-Path $here "xiai-market-board.html"
[System.IO.File]::WriteAllText(
    $boardPage, $board, (New-Object System.Text.UTF8Encoding($false)))
Render -Page $boardPage -W 1120 -H 1000 -Out (
    Join-Path $here "喜AI_行情图标总览.png") -Scale 1
Write-Host "[ok] 喜AI_行情图标总览.png"
Write-Host ""
Write-Host "下一步：dart run flutter_launcher_icons"
