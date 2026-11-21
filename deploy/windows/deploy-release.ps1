<#
.SYNOPSIS  Deploy one approved release of the HEXA backend with backup, health check and automatic rollback.
.DESCRIPTION
  Called by the GitHub Actions self-hosted runner (or by hand). Steps:
    1. copy backend\ of the checked-out commit into C:\hexa\releases\<sha>\backend
    2. build an isolated venv for that release (rollback keeps the old venv intact)
    3. install backend.env from C:\hexa\config (secrets never come from git)
    4. pre-deploy database backup (aborts the deploy if it fails)
    5. alembic upgrade head
    6. switch the "current" junction, restart HexaApi
    7. wait for /health/ready == 200; otherwise switch back to the previous release and restart
  Database migrations are NOT auto-reverted. Write migrations to be backward compatible; if a release must be
  undone after a schema change, restore the pre-deploy dump manually (needs owner approval).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceDir,   # repo root of the commit to deploy
    [Parameter(Mandatory)][string]$Sha,
    [int]$HealthTimeoutSec = 90
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
Assert-Admin

if ($Sha -notmatch '^[0-9a-f]{7,40}$') { throw 'Sha must be a hex commit id.' }
$src = Join-Path $SourceDir 'backend'
if (-not (Test-Path (Join-Path $src 'app\main.py'))) { throw "backend\app\main.py not found under $SourceDir" }
$envFile = Join-Path $ConfigDir 'backend.env'
if (-not (Test-Path $envFile)) { throw "Missing $envFile (see backend.env.template)" }

$rel = Join-Path $ReleasesDir $Sha.Substring(0, [math]::Min(12, $Sha.Length))
$previous = $null
if (Test-Path $CurrentLink) { $previous = (Get-Item $CurrentLink).Target; if ($previous -is [array]) { $previous = $previous[0] } }
Write-Log "deploy start sha=$Sha previous=$previous"

function Test-Health {
    param([int]$TimeoutSec)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try { $r = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 5; if ($r.StatusCode -eq 200) { return $true } } catch { }
        Start-Sleep 3
    }
    return $false
}
function Switch-Current([string]$target) {
    if (Test-Path $CurrentLink) { cmd /c rmdir "`"$CurrentLink`"" | Out-Null }   # removes the junction only
    cmd /c mklink /J "`"$CurrentLink`"" "`"$target`"" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "mklink failed for $target" }
}

# 1-3: stage the release (service keeps running the old code meanwhile)
if (Test-Path $rel) { Remove-Item $rel -Recurse -Force }
New-Item -ItemType Directory -Path $rel | Out-Null
robocopy $src (Join-Path $rel 'backend') /E /XD __pycache__ .pytest_cache tests /XF *.pyc hexa_dev.db *.db /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
Copy-Item $envFile (Join-Path $rel 'backend\.env') -Force

& py -3.12 -m venv (Join-Path $rel 'venv')
if ($LASTEXITCODE -ne 0) { throw 'venv creation failed' }
$py = Join-Path $rel 'venv\Scripts\python.exe'
& $py -m pip install --disable-pip-version-check -q -r (Join-Path $rel 'backend\requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'pip install failed; service untouched' }

# 4: pre-deploy backup (abort if it fails)
try { & "$PSScriptRoot\backup-postgres.ps1" -Label 'pre-deploy' }
catch { throw "pre-deploy backup failed; service untouched. $($_.Exception.Message)" }

# 5: migrations (from the new release, against the live DB)
Push-Location (Join-Path $rel 'backend')
try {
    & $py -m alembic upgrade head
    if ($LASTEXITCODE -ne 0) { throw 'alembic upgrade failed; service untouched (restore the pre-deploy dump only with owner approval)' }
} finally { Pop-Location }

# 6: switch + restart
Switch-Current $rel
$nssm = Join-Path $ToolsDir 'nssm.exe'
& $nssm restart $ApiService | Out-Null

# 7: health or rollback
if (Test-Health -TimeoutSec $HealthTimeoutSec) {
    Write-Log "deploy OK: $rel is live"
} else {
    Write-Log 'health check FAILED, rolling back' 'ERROR'
    if ($previous -and (Test-Path $previous)) {
        Switch-Current $previous
        & $nssm restart $ApiService | Out-Null
        if (Test-Health -TimeoutSec $HealthTimeoutSec) { Write-Log "rolled back to $previous" 'WARN' }
        else { Write-Log 'ROLLBACK ALSO UNHEALTHY: manual intervention required' 'ERROR' }
    } else {
        Write-Log 'no previous release to roll back to' 'ERROR'
    }
    exit 1
}

# keep the newest N releases (never the live one)
$live = (Get-Item $CurrentLink).Target; if ($live -is [array]) { $live = $live[0] }
Get-ChildItem $ReleasesDir -Directory | Sort-Object LastWriteTime -Descending | Select-Object -Skip $KeepReleases |
    Where-Object { $_.FullName -ne $live } | ForEach-Object { Remove-Item $_.FullName -Recurse -Force; Write-Log "pruned release $($_.Name)" }
