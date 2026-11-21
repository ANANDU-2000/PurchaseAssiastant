<#
.SYNOPSIS  Prove a backup is restorable: restore the newest dump into a scratch database and compare row counts.
.DESCRIPTION
  Never touches the live database. Creates and drops "hexa_restore_test".
  Run monthly (and after any change to the backup process). Exit code 1 = restore or comparison problem.
  Needs a Postgres role allowed to CREATE DATABASE (set -AdminUser; password via pgpass.conf).
#>
[CmdletBinding()]
param(
    [string]$DumpFile,
    [string]$DbHost = '127.0.0.1',
    [int]$Port = 5432,
    [string]$AdminUser = 'postgres',
    [string]$LiveDatabase = 'hexa',
    [string]$ScratchDatabase = 'hexa_restore_test'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
$env:PGPASSFILE = Join-Path $ConfigDir 'pgpass.conf'
$psql = Find-PgTool 'psql.exe'; $pgRestore = Find-PgTool 'pg_restore.exe'

if (-not $DumpFile) {
    $DumpFile = (Get-ChildItem $BackupsDir -Filter 'hexa-*.dump' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
if (-not $DumpFile -or -not (Test-Path $DumpFile)) { throw 'No dump file found.' }
Write-Log "restore test using $DumpFile"

$sha = "$DumpFile.sha256"
if (Test-Path $sha) {
    $expected = ((Get-Content $sha -Raw) -split '\s+')[0]
    if ((Get-FileHash $DumpFile -Algorithm SHA256).Hash -ne $expected) { throw 'checksum mismatch: dump is corrupted' }
}

$countSql = "SELECT table_name || '=' || (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY 1;"

function Get-Counts([string]$db) {
    $out = & $psql -h $DbHost -p $Port -U $AdminUser -d $db -At -c $countSql
    if ($LASTEXITCODE -ne 0) { throw "count query failed on $db" }
    $h = @{}; $out | Where-Object { $_ } | ForEach-Object { $k,$v = $_ -split '=',2; $h[$k] = [int64]$v }; return $h
}

$failed = $false
try {
    & $psql -h $DbHost -p $Port -U $AdminUser -d postgres -c "DROP DATABASE IF EXISTS $ScratchDatabase;" | Out-Null
    & $psql -h $DbHost -p $Port -U $AdminUser -d postgres -c "CREATE DATABASE $ScratchDatabase;" | Out-Null
    & $pgRestore -h $DbHost -p $Port -U $AdminUser -d $ScratchDatabase --no-owner --no-privileges $DumpFile
    if ($LASTEXITCODE -gt 1) { throw "pg_restore failed ($LASTEXITCODE)" }   # 1 = warnings only

    $live = Get-Counts $LiveDatabase; $rest = Get-Counts $ScratchDatabase
    foreach ($t in ($live.Keys | Sort-Object)) {
        if (-not $rest.ContainsKey($t)) { Write-Log "MISSING table in restore: $t" 'ERROR'; $failed = $true; continue }
        $delta = $live[$t] - $rest[$t]
        # live may have grown since the dump; fewer rows live than restored is also fine (deletes). Flag big losses in the dump.
        if ($rest[$t] -eq 0 -and $live[$t] -gt 0) { Write-Log "EMPTY in restore but $($live[$t]) rows live: $t" 'ERROR'; $failed = $true }
        Write-Log ("{0,-40} live={1,10} restored={2,10} diff={3}" -f $t, $live[$t], $rest[$t], $delta)
    }
} finally {
    & $psql -h $DbHost -p $Port -U $AdminUser -d postgres -c "DROP DATABASE IF EXISTS $ScratchDatabase;" | Out-Null
}
if ($failed) { Write-Log 'RESTORE TEST FAILED' 'ERROR'; exit 1 }
Write-Log 'RESTORE TEST PASSED'
