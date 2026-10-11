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

  Legal pages (backend/deploy/legal/*.html -> /server/legal/, served by nginx at
  https://api.singzquant.com/legal/) are published on every deploy so the live
  privacy policy / terms never drift from main. The old folder is archived to
  /server/backup/legal/legal.<ts>.tgz first. No service restart is involved.

  The website (backend/deploy/www/** -> /server/www/, served by nginx at
  https://www.singzquant.com/: homepage, /d/ invite page, og.png, app-icon.svg)
  is published the same way: old folder archived to
  /server/backup/www/www.<ts>.tgz, files installed over it (files that exist
  only on the server are left alone) and each installed file's sha256 checked
  against the local copy (mismatch = failure). Then every page is fetched from
  $WwwUrl and compared too; a mismatch there is only a WARNING, because as of
  2026-10 www.singzquant.com is still served by a different host (DNS not yet
  moved here, see backend/deploy/nginx/singzquant.com.conf).

  Run:
    powershell -File .\.tools\deploy.ps1                     # legal + www + binary + restarts
    powershell -File .\.tools\deploy.ps1 -LegalOnly          # only republish legal pages
    powershell -File .\.tools\deploy.ps1 -WwwOnly            # only republish the website
    powershell -File .\.tools\deploy.ps1 -LegalOnly -WwwOnly # both, no binary / no restart
    powershell -File .\.tools\deploy.ps1 -SkipLegal -SkipWww # only the binary
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
  # The *api* unit is restarted first and must pass /healthz (it owns the DB
  # migrations) before the others are restarted.
  [string[]]$Units    = @('finme-api','finme-scheduler','finme-pusher'),
  [string]$Remote     = "/server/bin/finme-server",
  # Legal pages (privacy / terms / support) published to /server/legal/.
  # Defaults to <repo>\backend\deploy\legal (resolved below: $PSScriptRoot is
  # empty inside param() defaults on Windows PowerShell 5.1).
  [string]$LegalDir   = '',
  [string]$RemoteLegal = "/server/legal",
  [switch]$SkipLegal,
  [switch]$LegalOnly,
  # Website published to /server/www/. Defaults to <repo>\backend\deploy\www.
  [string]$WwwDir     = '',
  [string]$RemoteWww  = "/server/www",
  [string]$WwwUrl     = "https://www.singzquant.com",
  [switch]$SkipWww,
  [switch]$WwwOnly
)
if ($SkipLegal -and $LegalOnly) { throw "-SkipLegal and -LegalOnly are mutually exclusive" }
if ($SkipWww -and $WwwOnly) { throw "-SkipWww and -WwwOnly are mutually exclusive" }
# -LegalOnly / -WwwOnly: publish only the named content (both may be given); no binary, no restart.
$ContentOnly = $LegalOnly -or $WwwOnly
$DoLegal = (-not $SkipLegal) -and ((-not $ContentOnly) -or $LegalOnly)
$DoWww   = (-not $SkipWww)   -and ((-not $ContentOnly) -or $WwwOnly)
if (-not $LegalDir) { $LegalDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'backend\deploy\legal' }
if (-not $WwwDir)   { $WwwDir   = Join-Path (Split-Path $PSScriptRoot -Parent) 'backend\deploy\www' }

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
$need = @($plink, $pscp)
if (-not $ContentOnly) { $need += $BinPath }
if ($DoWww) {
  $need += $WwwDir
  if (-not (Test-Path (Join-Path $WwwDir 'index.html'))) { throw "no index.html in $WwwDir" }
}
if ($DoLegal) {
  $need += $LegalDir
  if (-not (Get-ChildItem -Path $LegalDir -Filter *.html -File)) { throw "no *.html in $LegalDir" }
}
foreach ($t in $need) {
  if (-not (Test-Path $t)) { throw "missing: $t" }
}

# Run a bash script on the host (LF endings, UTF-8 without BOM, via plink -m).
function Invoke-Remote([string]$script, [string[]]$auth) {
  $f = New-TemporaryFile
  try {
    [IO.File]::WriteAllText($f.FullName, $script.Replace("`r`n","`n"), (New-Object Text.UTF8Encoding $false))
    # Echo remote output to the host only; the function's sole pipeline output
    # must be the exit code, or callers comparing `$rc -ne 0` see an array.
    & $plink -ssh -batch -hostkey $Hostkey @auth -m $f.FullName ("{0}@{1}" -f $User, $TargetHost) | ForEach-Object { Write-Host $_ }
    return $LASTEXITCODE
  } finally { Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue }
}

# Publish backend/deploy/legal/*.html -> $RemoteLegal (archive the old folder first).
function Publish-Legal([string[]]$auth) {
  $files = Get-ChildItem -Path $LegalDir -Filter *.html -File
  $stage = "/tmp/finme-legal-" + (Get-Date -Format 'yyyyMMddHHmmss')
  Write-Host "==> legal: $($files.Count) page(s) -> ${TargetHost}:$RemoteLegal"
  $rc = Invoke-Remote "set -e; rm -rf $stage; mkdir -p $stage" $auth
  if ($rc -ne 0) { throw "legal: stage dir failed ($rc)" }
  foreach ($f in $files) {
    & $pscp -batch -hostkey $Hostkey @auth $f.FullName ("{0}@{1}:{2}/{3}" -f $User, $TargetHost, $stage, $f.Name)
    if ($LASTEXITCODE -ne 0) { throw "legal: pscp $($f.Name) failed ($LASTEXITCODE)" }
  }
  $names = ($files | ForEach-Object { $_.BaseName }) -join ' '
  $script = @"
set -euo pipefail
ts=`$(date +%Y%m%d-%H%M%S)
mkdir -p /server/backup/legal $RemoteLegal
if [ -n "`$(ls -A $RemoteLegal 2>/dev/null)" ]; then
  tar -C `$(dirname $RemoteLegal) -czf /server/backup/legal/legal.`$ts.tgz `$(basename $RemoteLegal)
  echo "legal backup: /server/backup/legal/legal.`$ts.tgz"
fi
install -m 0644 $stage/*.html $RemoteLegal/
rm -rf $stage
for n in $names; do
  code=`$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 https://api.singzquant.com/legal/`$n.html || echo 000)
  echo "legal `$n.html: `$code `$(sha256sum $RemoteLegal/`$n.html | cut -c1-12)"
done
"@
  $rc = Invoke-Remote $script $auth
  if ($rc -ne 0) { throw "legal: publish failed ($rc)" }
}

# Publish backend/deploy/www/** -> $RemoteWww (archive the old folder first).
function Publish-Www([string[]]$auth) {
  $root  = (Resolve-Path $WwwDir).Path.TrimEnd('\')
  $files = @(Get-ChildItem -Path $root -Recurse -File)
  $rel   = @($files | ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') })
  foreach ($r in $rel) { if ($r -notmatch '^[A-Za-z0-9._/-]+$') { throw "www: unsupported file name: $r" } }
  $dirs  = @($rel | ForEach-Object { if ($_.Contains('/')) { $_.Substring(0, $_.LastIndexOf('/')) } } | Sort-Object -Unique)
  $stage = "/tmp/finme-www-" + (Get-Date -Format 'yyyyMMddHHmmss')
  Write-Host "==> www: $($files.Count) file(s) -> ${TargetHost}:$RemoteWww"
  $mk = "set -e; rm -rf $stage; mkdir -p $stage"
  foreach ($d in $dirs) { $mk += "; mkdir -p $stage/$d" }
  $rc = Invoke-Remote $mk $auth
  if ($rc -ne 0) { throw "www: stage dir failed ($rc)" }
  for ($i = 0; $i -lt $files.Count; $i++) {
    & $pscp -q -batch -hostkey $Hostkey @auth $files[$i].FullName ("{0}@{1}:{2}/{3}" -f $User, $TargetHost, $stage, $rel[$i])
    if ($LASTEXITCODE -ne 0) { throw "www: pscp $($rel[$i]) failed ($LASTEXITCODE)" }
  }
  $pairs = @(for ($i = 0; $i -lt $files.Count; $i++) {
    $rel[$i] + ':' + (Get-FileHash $files[$i].FullName -Algorithm SHA256).Hash.Substring(0, 12).ToLower()
  }) -join ' '
  $script = @"
set -euo pipefail
ts=`$(date +%Y%m%d-%H%M%S)
mkdir -p /server/backup/www $RemoteWww
if [ -n "`$(ls -A $RemoteWww 2>/dev/null)" ]; then
  tar -C `$(dirname $RemoteWww) -czf /server/backup/www/www.`$ts.tgz `$(basename $RemoteWww)
  echo "www backup: /server/backup/www/www.`$ts.tgz"
fi
cd $stage
find . -type d -exec install -d -m 0755 $RemoteWww/{} \;
find . -type f -exec install -m 0644 {} $RemoteWww/{} \;
cd /
rm -rf $stage
bad=0; drift=0
for pair in $pairs; do
  p=`${pair%%:*}; want=`${pair##*:}
  have=`$(sha256sum "$RemoteWww/`$p" | cut -c1-12)
  if [ "`$have" != "`$want" ]; then echo "www `$p: INSTALL MISMATCH local=`$want server=`$have"; bad=1; continue; fi
  case "`$p" in
    index.html) url="$WwwUrl/" ;;
    */index.html) url="$WwwUrl/`${p%index.html}" ;;
    *) url="$WwwUrl/`$p" ;;
  esac
  body=`$(mktemp)
  code=`$(curl -s -o "`$body" -w '%{http_code}' --max-time 8 "`$url" || echo 000)
  got=`$(sha256sum "`$body" | cut -c1-12); rm -f "`$body"
  if [ "`$code" = 200 ] && [ "`$want" = "`$got" ]; then st=live; else st="NOT-LIVE(http `$code)"; drift=1; fi
  echo "www `$p: installed `$have, `$url -> `$st"
done
if [ "`$drift" = 1 ]; then
  echo "WARNING: $WwwUrl does not serve these files yet (site is hosted elsewhere; installed here only)."
fi
exit `$bad
"@
  $rc = Invoke-Remote $script $auth
  if ($rc -ne 0) { throw "www: publish/verify failed ($rc)" }
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
  if ($DoLegal) { Publish-Legal $authArgs }
  if ($DoWww)   { Publish-Www $authArgs }
  if ($ContentOnly) { Write-Host "==> DONE (content only: legal=$DoLegal www=$DoWww; binary untouched, no restart)."; return }

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

# All units share the same binary, so every one of them restarts -- api FIRST.
# Only the api process runs DB migrations; scheduler / pusher wait (read-only)
# until schema_migrations is current. So: restart api, wait until /healthz is
# up (migrations done), then restart the rest.
api_unit=""
others=""
for u in $unitsArg; do
  case "`$u" in
    *api*) api_unit="`$u" ;;
    *) others="`$others `$u" ;;
  esac
done
if [ -n "`$api_unit" ]; then
  echo "---restart `$api_unit (first: owns DB migrations)---"
  systemctl restart "`$api_unit"
  ok=""
  for i in `$(seq 1 60); do
    if curl -fsS --max-time 3 http://127.0.0.1:8080/healthz >/dev/null 2>&1; then ok=1; break; fi
    sleep 1
  done
  if [ -z "`$ok" ]; then
    echo "ERROR: `$api_unit not healthy after 60s; NOT restarting:`$others" >&2
    systemctl --no-pager --full status "`$api_unit" | head -20 >&2 || true
    journalctl -u "`$api_unit" -n 30 --no-pager >&2 || true
    exit 12
  fi
  echo "healthz: ok after ~`${i}s"
fi
for u in `$others; do
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
curl -fsS --max-time 5 http://127.0.0.1:8080/healthz 2>&1 || echo "WARNING: /healthz failed"
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
