# 渲染 App Store 创意素材。
#
# 用法（在仓库根目录或本目录下执行均可）：
#   powershell -ExecutionPolicy Bypass -File marketing/app-store-assets/build.ps1
#
# 设计稿按 CSS px 排版，用 --force-device-scale-factor=2 输出 2 倍图，
# 因此 --window-size 填目标尺寸的一半。

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $here "src\asset.html"
$chrome = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $chrome) { throw "找不到 Chrome/Edge，无法渲染。" }

# 渲染函数：page = html 文件，query = 附加查询串（用于切换第几张截屏）
function Render-Shot {
    param([string]$Name, [int]$W, [int]$H, [string]$Page, [string]$Query, [string]$Use)

    $out = Join-Path $here ("$Name.png")
    $vw = [int]($W / 2)
    $vh = [int]($H / 2)
    if (Test-Path $out) { Remove-Item -LiteralPath $out -Force }

    $logOut = Join-Path $env:TEMP "xikuan_asset_render.out.log"
    $logErr = Join-Path $env:TEMP "xikuan_asset_render.err.log"
    # 必须用 file:/// URI，Windows 路径直接拼 ?query 会被当成文件名的一部分而 404。
    $uri = ([System.Uri]$Page).AbsoluteUri + $Query
    $chromeArgs = @(
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        "--force-device-scale-factor=2",
        "--virtual-time-budget=2500",
        "--window-size=$vw,$vh",
        "--screenshot=$out",
        $uri
    )
    Start-Process -FilePath $chrome -ArgumentList $chromeArgs -Wait -WindowStyle Hidden `
        -RedirectStandardError $logErr -RedirectStandardOutput $logOut

    if (-not (Test-Path $out)) { throw "渲染失败：$Name" }
    Write-Host ("[ok] {0}  ({1}x{2})  {3}" -f $Name, $W, $H, $Use)
}

# ── 一、创意素材（产品页顶部横幅 / 搜索结果）────────────────────────
$creativeSrc = Join-Path $here "src\asset.html"
$targets = @(
    @{ name = "喜宽_通用素材_5244x2950"; w = 5244; h = 2950; use = "产品页顶部横幅 + 搜索结果（通用，Apple 推荐同一张）" },
    @{ name = "喜宽_顶部横幅_3840x1646"; w = 3840; h = 1646; use = "产品页顶部横幅（21:9 超宽版）" },
    @{ name = "喜宽_搜索结果_3840x2560"; w = 3840; h = 2560; use = "搜索结果素材（3:2）" },
    @{ name = "喜宽_搜索结果_1920x1280"; w = 1920; h = 1280; use = "搜索结果素材（3:2 小尺寸）" }
)
foreach ($t in $targets) {
    Render-Shot -Name $t.name -W $t.w -H $t.h -Page $creativeSrc -Query "" -Use $t.use
}

# ── 二、截屏（5 张 × 6.9" / 6.5" 两种尺寸）────────────────────────
$shotSrc = Join-Path $here "src\screens.html"
$shots = @(
    @{ id = 1; use = "AI 助理对话" },
    @{ id = 2; use = "看盘自选列表" },
    @{ id = 3; use = "品种详情 K 线" },
    @{ id = 4; use = "DING 收件箱" },
    @{ id = 5; use = "我的 / 喜点" }
)
$sizes = @(
    @{ tag = "6.9英寸_1320x2868"; w = 1320; h = 2868 },
    @{ tag = "6.5英寸_1242x2688"; w = 1242; h = 2688 }
)

foreach ($sz in $sizes) {
    foreach ($s in $shots) {
        Render-Shot -Name ("喜宽_截屏{0}_{1}" -f $s.id, $sz.tag) `
            -W $sz.w -H $sz.h -Page $shotSrc -Query ("?n={0}" -f $s.id) -Use $s.use
    }
}

# ── 三、iPad 截屏（5 张 × 12.9"/13" 两种尺寸）────────────────────
$ipadSizes = @(
    @{ tag = "12.9英寸_2048x2732"; w = 2048; h = 2732 },
    @{ tag = "13英寸_2064x2752"; w = 2064; h = 2752 }
)

foreach ($sz in $ipadSizes) {
    foreach ($s in $shots) {
        Render-Shot -Name ("喜宽_iPad截屏{0}_{1}" -f $s.id, $sz.tag) `
            -W $sz.w -H $sz.h -Page $shotSrc -Query ("?n={0}" -f $s.id) -Use ("iPad · " + $s.use)
    }
}

Write-Host ""
Write-Host "输出目录：$here"
