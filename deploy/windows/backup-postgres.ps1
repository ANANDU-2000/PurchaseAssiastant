<#
.SYNOPSIS  Daily PostgreSQL backup with verification, retention and optional offsite copy.
.DESCRIPTION
  - pg_dump custom format -> C:\hexa\backups\hexa-<timestamp>-<label>.dump (+ .sha256)
  - verifies the dump is readable (pg_restore --list) and refuses to continue on failure
  - refuses to start if free disk space is below -MinFreeGB
  - retention: keep everything for 14 days, Sunday dumps for 60 days, first-of-month dumps for 365 days
  - offsite: if rclone is installed and env HEXA_OFFSITE_REMOTE is set (e.g. "b2:hexa-backups"), copies the dump there
  Credentials: use a pgpass file (C:\hexa\config\pgpass.conf, line: host:port:db:user:password). No password on the command line.
  Settings (env or C:\hexa\config\backup.env style lines): PGHOST, PGPORT, PGUSER, PGDATABASE, HEXA_OFFSITE_REMOTE
#>
[CmdletBinding()]
param(
    [string]$Label = 'daily',
    [string]$DbHost = $(if ($env:PGHOST) { $env:PGHOST } else { '127.0.0.1' }),
    [int]$Port = $(if ($env:PGPORT) { [int]$env:PGPORT } else { 5432 }),
    [string]$User = $(if ($env:PGUSER) { $env:PGUSER } else { 'hexa_backup' }),
    [string]$Database = $(if ($env:PGDATABASE) { $env:PGDATABASE } else { 'hexa' }),
    [int]$MinFreeGB = 5
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"

$pgpass = Join-Path $ConfigDir 'pgpass.conf'
if (-not (Test-Path $pgpass)) { throw "Missing $pgpass (format host:port:database:user:password)" }
$env:PGPASSFILE = $pgpass

$free = [math]::Round((Get-PSDrive -Name ($BackupsDir.Substring(0,1))).Free / 1GB, 1)
if ($free -lt $MinFreeGB) { throw "Only $free GB free on the backup drive (< $MinFreeGB GB). Aborting." }

$pgDump    = Find-PgTool 'pg_dump.exe'
$pgRestore = Find-PgTool 'pg_restore.exe'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$file  = Join-Path $BackupsDir "hexa-$stamp-$Label.dump"
$tmp   = "$file.partial"

Write-Log "backup start -> $file"
& $pgDump -h $DbHost -p $Port -U $User -d $Database -Fc --no-owner --no-privileges -f $tmp
if ($LASTEXITCODE -ne 0) { Remove-Item $tmp -ErrorAction SilentlyContinue; throw "pg_dump failed ($LASTEXITCODE)" }

& $pgRestore --list $tmp | Out-Null
if ($LASTEXITCODE -ne 0) { Remove-Item $tmp -ErrorAction SilentlyContinue; throw 'dump failed verification (pg_restore --list)' }

Move-Item $tmp $file
$hash = (Get-FileHash $file -Algorithm SHA256).Hash
"$hash  $(Split-Path $file -Leaf)" | Set-Content "$file.sha256"
Write-Log ("backup ok: {0} MB, sha256 {1}" -f [math]::Round((Get-Item $file).Length/1MB,1), $hash.Substring(0,16))

# ---- offsite (optional)
if ($env:HEXA_OFFSITE_REMOTE -and (Get-Command rclone -ErrorAction SilentlyContinue)) {
    rclone copy $file $env:HEXA_OFFSITE_REMOTE --config (Join-Path $ConfigDir 'rclone.conf')
    rclone copy "$file.sha256" $env:HEXA_OFFSITE_REMOTE --config (Join-Path $ConfigDir 'rclone.conf')
    if ($LASTEXITCODE -ne 0) { Write-Log 'offsite copy FAILED' 'ERROR' } else { Write-Log "offsite copy ok -> $($env:HEXA_OFFSITE_REMOTE)" }
} else {
    Write-Log 'offsite copy skipped (set HEXA_OFFSITE_REMOTE and install rclone)' 'WARN'
}

# ---- retention (never touches pre-deploy dumps younger than 30 days)
$now = Get-Date
Get-ChildItem $BackupsDir -Filter 'hexa-*.dump' | ForEach-Object {
    $age = ($now - $_.LastWriteTime).TotalDays
    $keep = $age -le 14
    if (-not $keep -and $_.LastWriteTime.DayOfWeek -eq 'Sunday' -and $age -le 60) { $keep = $true }
    if (-not $keep -and $_.LastWriteTime.Day -eq 1 -and $age -le 365) { $keep = $true }
    if (-not $keep -and $_.Name -like '*-pre-deploy*' -and $age -le 30) { $keep = $true }
    if (-not $keep) {
        Remove-Item $_.FullName, "$($_.FullName).sha256" -ErrorAction SilentlyContinue
        Write-Log "retention: removed $($_.Name)"
    }
}
