<#
  把本机行情采集端装成计划任务：登录即启动、常驻、每 15 秒推一次。

  为什么需要常驻：内盘期货实时价只有本机能取到（服务器出口被挡），采集端不跑，
  App 里的期货行情就退回"最近收盘"口径。

  用法：
    powershell -File tools\quote-agent\install.ps1 -Key <服务端 ingest.key>
    powershell -File tools\quote-agent\install.ps1 -Status
    powershell -File tools\quote-agent\install.ps1 -Remove
#>
[CmdletBinding()]
param(
  [string]$Key = '',
  [string]$Url = 'https://api.singzquant.com',
  [string]$TaskName = 'Xikuan-QuoteAgent',
  [switch]$Status,
  [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$agent = Join-Path $here 'quote_agent.py'
$runner = Join-Path $here 'agent.cmd'   # 含密钥，已在 .gitignore 中排除

# 用「启动文件夹」而不是计划任务：注册 -AtLogOn 计划任务需要管理员权限，
# 而启动文件夹对当前用户即可生效，效果一样（登录即跑）。
$startupDir = [Environment]::GetFolderPath('Startup')
$startupLnk = Join-Path $startupDir 'XikuanQuoteAgent.cmd'

if ($Status) {
  if (Test-Path $startupLnk) { Write-Host "已安装：$startupLnk" }
  else { Write-Host "未安装（用 -Key 安装）" }
  $proc = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*quote_agent.py*' }
  if ($proc) { Write-Host "采集端正在运行 (pid $($proc.ProcessId -join ','))" }
  else { Write-Host "采集端当前未运行" }
  exit 0
}

if ($Remove) {
  if (Test-Path $startupLnk) { Remove-Item -LiteralPath $startupLnk -Force; Write-Host "已移除启动项" }
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*quote_agent.py*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Write-Host "已停止采集端"
  exit 0
}

if (-not $Key) { throw "缺少 -Key（服务端 config.toml 的 ingest.key）" }

# 密钥写进本地 runner 而不是任务命令行：任务列表是明文的，但 runner 文件能加 gitignore。
$runnerBody = @"
@echo off
set QUOTE_AGENT_URL=$Url
set QUOTE_AGENT_KEY=$Key
"$((Get-Command python).Source)" "$agent" >> "$here\agent.log" 2>&1
"@
[IO.File]::WriteAllText($runner, $runnerBody, (New-Object Text.UTF8Encoding $false))

Copy-Item -LiteralPath $runner -Destination $startupLnk -Force
Write-Host "已安装启动项：$startupLnk（登录即启动，每 15 秒推送一次）"
Write-Host "日志：$(Join-Path $here 'agent.log')"
Write-Host "现在启动一次…"
Start-Process -FilePath $runner -WindowStyle Hidden
Start-Sleep -Seconds 10
if (Test-Path (Join-Path $here 'agent.log')) {
  Get-Content (Join-Path $here 'agent.log') -Tail 4
}
