#requires -Version 5.1
<#
  Push a freshly built finme-server (linux/amd64) to the production host
  and bounce the systemd unit.

  Prerequisites:
    - .tools\_build\finme-server  (produced by .tools\build_linux.sh in WSL)
    - D:\Tools\plink\plink.exe + pscp.exe (PuTTY 0.83 single-file binaries)

  Run:
    powershell -File .\.tools\deploy.ps1
#>

[CmdletBinding()]
param(
  [string]$BinPath  = "D:\GitHub\aiquant\.tools\_build\finme-server",
  [string]$TargetHost = "47.110.227.73",
  [string]$User     = "root",
  [string]$Pass     = "sc1q2w#E4r",
  [string]$Hostkey  = "SHA256:L67TyBUEmjxVjtsCdYWOkp50zJPcyoSU8rhNeDL+Ric",
  # 三个 systemd unit 共用同一个二进制(/server/bin/finme-server),
  # 替换后必须一起重启,否则旧进程会继续跑旧代码。
  [string[]]$Units  = @('finme-api','finme-scheduler','finme-pusher'),
  [string]$Remote   = "/server/bin/finme-server"
)

$ErrorActionPreference = 'Stop'
$plink = 'D:\Tools\plink\plink.exe'
$pscp  = 'D:\Tools\plink\pscp.exe'
foreach ($t in @($BinPath, $plink, $pscp)) {
  if (-not (Test-Path $t)) { throw "missing: $t" }
}

$size = (Get-Item $BinPath).Length
$sha  = (Get-FileHash $BinPath -Algorithm SHA256).Hash.ToLower()
Write-Host "==> local binary: $BinPath ($size bytes)"
Write-Host "    sha256 = $sha"

$remoteTmp = "$Remote.new"
Write-Host "==> scp -> ${User}@${TargetHost}:${remoteTmp}"
& $pscp -batch -hostkey $Hostkey -pw $Pass $BinPath ("{0}@{1}:{2}" -f $User, $TargetHost, $remoteTmp)
if ($LASTEXITCODE -ne 0) { throw "pscp failed ($LASTEXITCODE)" }

$unitsArg = ($Units -join ' ')

# Write a remote-shell script to a temp file (LF endings) and run with `plink -m`.
$remoteScript = @"
set -euo pipefail
ts=`$(date +%Y%m%d-%H%M%S)
mkdir -p /server/backup/bin
if [ -f $Remote ]; then
  cp -a $Remote /server/backup/bin/finme-server.`$ts
  echo "backup: /server/backup/bin/finme-server.`$ts"
fi
chmod +x $remoteTmp
mv -f $remoteTmp $Remote
echo "swap: ok"
remote_sha=`$(sha256sum $Remote | awk '{print `$1}')
echo "remote sha256: `$remote_sha"
if [ "`$remote_sha" != "$sha" ]; then
  echo "ERROR: sha mismatch (local=$sha)" >&2
  exit 11
fi

# 三个 unit 共用同一个二进制,必须全部重启拿新版
for u in $unitsArg; do
  echo "---restart `$u---"
  systemctl restart "`$u"
done
sleep 3
for u in $unitsArg; do
  echo "---systemd: `$u---"
  systemctl --no-pager --full status "`$u" | head -8
done

echo
echo "---health probe---"
curl -fsS --max-time 5 http://127.0.0.1:8080/v1/health 2>&1 || \
  curl -fsS --max-time 5 http://127.0.0.1:8080/healthz 2>&1 || \
  echo "(no health endpoint; check listener instead)"
echo
echo "---listener---"
ss -tlnp 2>/dev/null | grep finme-server || echo "WARNING: finme-server not listening!"
echo
echo "---recent log---"
journalctl -u finme-api -n 10 --no-pager 2>/dev/null | tail -10 || true
echo "---scheduler log---"
journalctl -u finme-scheduler -n 10 --no-pager 2>/dev/null | tail -10 || true
"@

$tmp = New-TemporaryFile
# write with LF (Out-File defaults to CRLF; use [IO.File] with UTF8 no BOM)
[IO.File]::WriteAllText($tmp.FullName, $remoteScript.Replace("`r`n","`n"), (New-Object Text.UTF8Encoding $false))

Write-Host "==> remote: backup + swap + restart + health (cmd file: $($tmp.FullName))"
& $plink -ssh -batch -hostkey $Hostkey -pw $Pass -m $tmp.FullName ("{0}@{1}" -f $User, $TargetHost)
$rc = $LASTEXITCODE
Remove-Item $tmp.FullName -Force -ErrorAction SilentlyContinue
if ($rc -ne 0) { throw "remote script failed (exit $rc)" }

Write-Host "==> DONE."
