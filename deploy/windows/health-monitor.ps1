<#
.SYNOPSIS  5-minute health probe: API, tunnel, PostgreSQL, disk, backup age. Alerts via optional webhook.
.DESCRIPTION
  Writes a JSON line per run to C:\hexa\logs\health.jsonl. Exit code 1 when anything is unhealthy.
  Optional: env HEXA_ALERT_WEBHOOK = URL that receives {"text": "..."} (Slack-compatible / Make webhook).
  Alerts are rate-limited to once per hour per problem set so a long outage does not spam.
#>
[CmdletBinding()] param([int]$MinFreeDiskPercent = 15, [int]$MaxBackupAgeHours = 26)
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\config.ps1"
$problems = New-Object System.Collections.Generic.List[string]
$sw = [Diagnostics.Stopwatch]::StartNew()

# API liveness + readiness + latency
try { $r = Invoke-WebRequest $LiveUrl -UseBasicParsing -TimeoutSec 5; if ($r.StatusCode -ne 200) { $problems.Add("api live=$($r.StatusCode)") } }
catch { $problems.Add('api live unreachable') }
$apiMs = $sw.ElapsedMilliseconds
try { $r = Invoke-WebRequest $HealthUrl -UseBasicParsing -TimeoutSec 10; if ($r.StatusCode -ne 200) { $problems.Add("api ready=$($r.StatusCode)") } }
catch { $problems.Add('api ready failed (database or migrations?)') }

# services
foreach ($name in $ApiService, $TunnelService) {
    $s = Get-Service $name -ErrorAction SilentlyContinue
    if (-not $s) { $problems.Add("service $name not installed") } elseif ($s.Status -ne 'Running') { $problems.Add("service $name is $($s.Status)") }
}
$pg = Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $pg -or $pg.Status -ne 'Running') { $problems.Add('postgresql service not running') }

# disk
$drive = Get-PSDrive -Name ($HexaRoot.Substring(0,1))
$freePct = [math]::Round(100 * $drive.Free / ($drive.Free + $drive.Used), 1)
if ($freePct -lt $MinFreeDiskPercent) { $problems.Add("disk free $freePct% (< $MinFreeDiskPercent%)") }

# memory
$os = Get-CimInstance Win32_OperatingSystem
$memFreePct = [math]::Round(100 * $os.FreePhysicalMemory / $os.TotalVisibleMemorySize, 1)
if ($memFreePct -lt 8) { $problems.Add("memory free $memFreePct%") }

# backup age
$last = Get-ChildItem $BackupsDir -Filter 'hexa-*.dump' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$backupAgeH = if ($last) { [math]::Round(((Get-Date) - $last.LastWriteTime).TotalHours, 1) } else { $null }
if (-not $last) { $problems.Add('no backup found') } elseif ($backupAgeH -gt $MaxBackupAgeHours) { $problems.Add("last backup $backupAgeH h old") }

# postgres connections (needs psql + pgpass; skipped quietly if unavailable)
$conns = $null
try {
    $env:PGPASSFILE = Join-Path $ConfigDir 'pgpass.conf'
    $out = & (Find-PgTool 'psql.exe') -h 127.0.0.1 -U hexa_backup -d hexa -At -c 'select count(*) from pg_stat_activity' 2>$null
    if ($LASTEXITCODE -eq 0) { $conns = [int]$out }
} catch { }

$rec = [ordered]@{ ts = (Get-Date).ToString('o'); ok = ($problems.Count -eq 0); apiLiveMs = $apiMs; diskFreePct = $freePct; memFreePct = $memFreePct; backupAgeH = $backupAgeH; pgConnections = $conns; problems = @($problems) }
if (Test-Path $LogsDir) { ($rec | ConvertTo-Json -Compress) | Add-Content (Join-Path $LogsDir 'health.jsonl') }

if ($problems.Count -gt 0) {
    $msg = "HEXA server problem: " + ($problems -join '; ')
    Write-Log $msg 'ERROR'
    $stamp = Join-Path $LogsDir '.last-alert'
    $due = -not (Test-Path $stamp) -or ((Get-Date) - (Get-Item $stamp).LastWriteTime).TotalMinutes -gt 60
    if ($env:HEXA_ALERT_WEBHOOK -and $due) {
        try { Invoke-RestMethod -Uri $env:HEXA_ALERT_WEBHOOK -Method Post -ContentType 'application/json' -Body (@{ text = $msg } | ConvertTo-Json) | Out-Null; Set-Content $stamp (Get-Date) } catch { Write-Log 'alert webhook failed' 'WARN' }
    }
    exit 1
}
