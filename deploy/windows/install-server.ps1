<#
.SYNOPSIS  One-time bootstrap of the HEXA backend host (Windows Server 2022). Run elevated.
.DESCRIPTION
  Creates C:\hexa layout, checks prerequisites, installs the HexaApi service (NSSM),
  and registers the backup + monitor scheduled tasks. It does NOT install PostgreSQL,
  Python, NSSM or cloudflared for you: it tells you exactly what is missing.
  Safe to re-run (idempotent). It never overwrites backend.env.
#>
[CmdletBinding()] param([switch]$SkipTasks)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
Assert-Admin

Write-Host '== 1. Folder layout'
foreach ($d in $HexaRoot,$ReleasesDir,$ConfigDir,$LogsDir,$BackupsDir,$ToolsDir) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null; Write-Log "created $d" }
}
# Lock down the WHOLE tree, not just config: release folders hold backend\.env (secrets) and backups hold all
# business data. A folder created under C:\ otherwise inherits read access for every local user.
icacls $HexaRoot /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' | Out-Null

# Scheduled tasks run as SYSTEM, so they must run scripts from an admin-only location (never from a git or
# runner checkout that a lower-privileged account can modify). Re-run this script to refresh the copies.
$OpsDir = Join-Path $HexaRoot 'ops'
if (-not (Test-Path $OpsDir)) { New-Item -ItemType Directory -Path $OpsDir | Out-Null }
Copy-Item "$PSScriptRoot\*.ps1" $OpsDir -Force
Copy-Item "$PSScriptRoot\backend.env.template" $OpsDir -Force
Get-ChildItem $OpsDir -Filter *.ps1 | Unblock-File
Write-Log "ops scripts copied to $OpsDir"

Write-Host '== 2. Prerequisites'
$missing = @()
if (-not (Get-Command py -ErrorAction SilentlyContinue) -or -not (& py -3.12 -c "import sys;print(sys.version)" 2>$null)) {
    $missing += 'Python 3.12 (python.org, with the py launcher)'
}
try { [void](Find-PgTool 'pg_dump.exe') } catch { $missing += 'PostgreSQL client tools (pg_dump, pg_restore, psql)' }
if (-not (Test-Path (Join-Path $ToolsDir 'nssm.exe'))) { $missing += "nssm.exe copied to $ToolsDir (nssm.cc)" }
if (-not (Test-Path (Join-Path $ToolsDir 'cloudflared.exe'))) { $missing += "cloudflared.exe copied to $ToolsDir (Cloudflare downloads)" }
if (-not (Test-Path (Join-Path $ConfigDir 'backend.env'))) {
    Copy-Item "$PSScriptRoot\backend.env.template" (Join-Path $ConfigDir 'backend.env.TEMPLATE')
    $missing += "Fill in $ConfigDir\backend.env (template copied as backend.env.TEMPLATE; rename it after editing)"
}
if ($missing.Count) {
    Write-Host 'Missing prerequisites:' -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    throw 'Fix the items above and run again.'
}

Write-Host '== 3. HexaApi Windows service (NSSM)'
$nssm = Join-Path $ToolsDir 'nssm.exe'
if (-not (& $nssm status $ApiService 2>$null)) {
    # Python/venv path is inside the active release; the service follows the "current" junction.
    $py = Join-Path $CurrentLink 'venv\Scripts\python.exe'
    $svcArgs = "-m uvicorn app.main:app --host $ApiHost --port $ApiPort --workers $UvicornWorkers --proxy-headers --forwarded-allow-ips=127.0.0.1"
    & $nssm install $ApiService $py $svcArgs | Out-Null
}
& $nssm set $ApiService AppDirectory (Join-Path $CurrentLink 'backend') | Out-Null
& $nssm set $ApiService Start SERVICE_AUTO_START | Out-Null
& $nssm set $ApiService AppExit Default Restart | Out-Null
& $nssm set $ApiService AppRestartDelay 5000 | Out-Null
& $nssm set $ApiService AppStdout (Join-Path $LogsDir 'api.out.log') | Out-Null
& $nssm set $ApiService AppStderr (Join-Path $LogsDir 'api.err.log') | Out-Null
& $nssm set $ApiService AppRotateFiles 1 | Out-Null
& $nssm set $ApiService AppRotateBytes 20971520 | Out-Null
Write-Log "service $ApiService configured (starts after the first deploy creates $CurrentLink)"

Write-Host '== 4. Firewall'
# API binds to 127.0.0.1 only, so nothing needs opening. Make sure no stray inbound rule exposes it.
Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction SilentlyContinue |
    Where-Object { ($_ | Get-NetFirewallPortFilter).LocalPort -contains "$ApiPort" -or ($_ | Get-NetFirewallPortFilter).LocalPort -contains '5432' } |
    ForEach-Object { Write-Host "  WARNING: inbound rule '$($_.DisplayName)' opens port 8000/5432. Review it." -ForegroundColor Yellow }

if (-not $SkipTasks) {
    Write-Host '== 5. Scheduled tasks'
    $ps = (Get-Command powershell.exe).Source
    $def = @(
        @{ Name='HexaBackupDaily'; Script='backup-postgres.ps1'; Trigger=(New-ScheduledTaskTrigger -Daily -At 02:30) },
        # Windows PowerShell 5.1 needs an explicit finite duration for a repeating trigger.
        @{ Name='HexaMonitor';     Script='health-monitor.ps1';  Trigger=(New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)) }
    )
    foreach ($t in $def) {
        $action = New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -ExecutionPolicy RemoteSigned -File `"$OpsDir\$($t.Script)`""
        Register-ScheduledTask -TaskName $t.Name -Action $action -Trigger $t.Trigger -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
        Write-Log "scheduled task $($t.Name) registered"
    }
}
Write-Host 'Bootstrap complete. Next: install-cloudflared.ps1, then the first deploy-release.ps1.' -ForegroundColor Green
