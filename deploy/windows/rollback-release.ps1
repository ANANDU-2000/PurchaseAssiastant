<#
.SYNOPSIS  Point the service at an earlier release (code only) and verify health.
.DESCRIPTION
  -Release  folder name under C:\hexa\releases (default: the newest release that is not currently live).
  This does NOT undo database migrations. If the schema changed, decide with the owner whether to restore
  the matching pre-deploy dump (C:\hexa\backups\hexa-*-pre-deploy.dump) using restore steps in README.md.
#>
[CmdletBinding()] param([string]$Release, [int]$HealthTimeoutSec = 90)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
Assert-Admin

$live = (Get-Item $CurrentLink).Target; if ($live -is [array]) { $live = $live[0] }
if ($Release) {
    if ($Release -notmatch '^[0-9a-f]{7,40}$') { throw 'Release must be a hex folder name.' }
    $target = Join-Path $ReleasesDir $Release
} else {
    $target = (Get-ChildItem $ReleasesDir -Directory | Where-Object { $_.FullName -ne $live } |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
if (-not $target -or -not (Test-Path $target)) { throw 'No release found to roll back to.' }
Write-Log "rollback $live -> $target"

cmd /c rmdir "`"$CurrentLink`"" | Out-Null
cmd /c mklink /J "`"$CurrentLink`"" "`"$target`"" | Out-Null
& (Join-Path $ToolsDir 'nssm.exe') restart $ApiService | Out-Null

$deadline = (Get-Date).AddSeconds($HealthTimeoutSec); $ok = $false
while ((Get-Date) -lt $deadline) {
    try { if ((Invoke-WebRequest $HealthUrl -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200) { $ok = $true; break } } catch { }
    Start-Sleep 3
}
if (-not $ok) { Write-Log 'rolled-back release is NOT healthy' 'ERROR'; exit 1 }
Write-Log "rollback OK: $target is live"
