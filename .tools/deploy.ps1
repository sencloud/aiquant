#requires -Version 5.1
<#
  Push a freshly built finme-server (linux/amd64) to the production host
  and bounce the systemd units.

  Prerequisites:
    - .tools\_build\finme-server  (produced by .tools\build_linux.sh in WSL)
    - D:\Tools\plink\plink.exe + pscp.exe (PuTTY 0.83 single-file binaries)

  Credentials are NEVER stored in this file. They are resolved in this order
  (first non-empty value wins, per field):
    1. Script parameters (-TargetHost / -User / -KeyFile / -Hostkey)
    2. Environment variables:
         AIQUANT_DEPLOY_HOST, AIQUANT_DEPLOY_USER, AIQUANT_DEPLOY_PASSWORD,
         AIQUANT_DEPLOY_KEYFILE, AIQUANT_DEPLOY_HOSTKEY
    3. .tools\deploy.local.ps1   (gitignored, dot-sourced; sets $DeployHost,
       $DeployUser, $DeployPassword, $DeployKeyFile, $DeployHostkey)
    4. .tools\deploy.local.json  (gitignored; keys host/user/password/keyFile/hostkey)
    5. Built-in non-secret defaults (host, user, host-key fingerprint)

  Authentication preference: SSH key (KeyFile, a PuTTY .ppk) > Pageant agent
  (-UseAgent) > password. The password is passed to plink/pscp via -pwfile
  (a temp file deleted right after), never on the command line.
  Copy .tools\deploy.local.example.ps1 to .tools\deploy.local.ps1 to start.

  Run:
    powershell -File .\.tools\deploy.ps1
#>

[CmdletBinding()]
param(
  [string]$BinPath    = "D:\GitHub\aiquant\.tools\_build\finme-server",
  [string]$TargetHost = "",
  [string]$User       = "",
  [string]$KeyFile    = "",
  [string]$Hostkey    = "",
  # Use keys already loaded in Pageant instead of a key file / password.
  [switch]$UseAgent,
  # All three systemd units share one binary (/server/bin/finme-server);
  # after the swap every one of them must restart, or a process keeps old code.
  [string[]]$Units    = @('finme-api','finme-scheduler','finme-pusher'),
  [string]$Remote     = "/server/bin/finme-server"
)

$ErrorActionPreference = 'Stop'

# ---- credential resolution -------------------------------------------------
$DefaultHost    = "47.110.227.73"
$DefaultUser    = "root"
$DefaultHostkey = "SHA256:L67TyBUEmjxVjtsCdYWOkp50zJPcyoSU8rhNeDL+Ric"   # public SSH host-key fingerprint, not a secret

$DeployHost = $null; $DeployUser = $null; $DeployPassword = $null
$DeployKeyFile = $null; $DeployHostkey = $null

$localJson = Join-Path $PSScriptRoot 'deploy.local.json'
if (Test-Path $localJson) {
  $j = Get-Content $localJson -Raw -Encoding UTF8 | ConvertFrom-Json
  $DeployHost = $j.host; $DeployUser = $j.user; $DeployPassword = $j.password
  $DeployKeyFile = $j.keyFile; $DeployHostkey = $j.hostkey
}
$localPs1 = Join-Path $PSScriptRoot 'deploy.local.ps1'
if (Test-Path $localPs1) { . $localPs1 }   # overrides the json file

function Pick { foreach ($v in $args) { if ($v -and "$v".Trim()) { return "$v".Trim() } }; return $null }

$TargetHost = Pick $TargetHost $env:AIQUANT_DEPLOY_HOST    $DeployHost    $DefaultHost
$User       = Pick $User       $env:AIQUANT_DEPLOY_USER    $DeployUser    $DefaultUser
$KeyFile    = Pick $KeyFile    $env:AIQUANT_DEPLOY_KEYFILE $DeployKeyFile
$Hostkey    = Pick $Hostkey    $env:AIQUANT_DEPLOY_HOSTKEY $DeployHostkey $DefaultHostkey
$password   = Pick $env:AIQUANT_DEPLOY_PASSWORD $DeployPassword
Remove-Variable DeployPassword -ErrorAction SilentlyContinue

$plink = 'D:\Tools\plink\plink.exe'
$pscp  = 'D:\Tools\plink\pscp.exe'
foreach ($t in @($BinPath, $plink, $pscp)) {
  if (-not (Test-Path $t)) { throw "missing: $t" }
}

$pwFile = $null
if ($KeyFile) {
  if (-not (Test-Path $KeyFile)) { throw "SSH key file not found: $KeyFile (must be a PuTTY .ppk; convert OpenSSH keys with puttygen)" }
  $authArgs = @('-i', $KeyFile)
  $authDesc = "key file $KeyFile"
} elseif ($UseAgent) {
  $authArgs = @('-agent')
  $authDesc = 'Pageant agent'
} elseif ($password) {
  $pwFile = [IO.Path]::GetTempFileName()
  [IO.File]::WriteAllText($pwFile, $password, (New-Object Text.UTF8Encoding $false))
  $authArgs = @('-pwfile', $pwFile)
  $authDesc = 'password (from env/local config)'
} else {
  throw @"
No deploy credential configured. Set ONE of:
  - `$env:AIQUANT_DEPLOY_KEYFILE = 'C:\path\to\key.ppk'   (recommended: SSH key)
  - `$env:AIQUANT_DEPLOY_PASSWORD = '...'
  - .tools\deploy.local.ps1  (copy from .tools\deploy.local.example.ps1; gitignored)
  - .tools\deploy.local.json (gitignored)
  - -UseAgent with the key loaded in Pageant
"@
}
Remove-Variable password -ErrorAction SilentlyContinue

try {
  $size = (Get-Item $BinPath).Length
  $sha  = (Get-FileHash $BinPath -Algorithm SHA256).Hash.ToLower()
  Write-Host "==> local binary: $BinPath ($size bytes)"
  Write-Host "    sha256 = $sha"
  Write-Host "==> auth: $authDesc"

  $remoteTmp = "$Remote.new"
  Write-Host "==> scp -> ${User}@${TargetHost}:${remoteTmp}"
  & $pscp -batch -hostkey $Hostkey @authArgs $BinPath ("{0}@{1}:{2}" -f $User, $TargetHost, $remoteTmp)
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

# all units share the same binary, so restart every one of them
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
  & $plink -ssh -batch -hostkey $Hostkey @authArgs -m $tmp.FullName ("{0}@{1}" -f $User, $TargetHost)
  $rc = $LASTEXITCODE
  Remove-Item $tmp.FullName -Force -ErrorAction SilentlyContinue
  if ($rc -ne 0) { throw "remote script failed (exit $rc)" }

  Write-Host "==> DONE."
} finally {
  if ($pwFile) { Remove-Item $pwFile -Force -ErrorAction SilentlyContinue }
}
