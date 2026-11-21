# Shared settings for the HEXA Windows Server scripts. Dot-source this file: . "$PSScriptRoot\config.ps1"
# Nothing secret lives here. Secrets are in C:\hexa\config (restricted ACL, never in git).

$Script:HexaRoot      = $env:HEXA_ROOT;      if (-not $HexaRoot)      { $Script:HexaRoot = 'C:\hexa' }
$Script:ReleasesDir   = Join-Path $HexaRoot 'releases'
$Script:CurrentLink   = Join-Path $HexaRoot 'current'      # junction -> releases\<sha>
$Script:ConfigDir     = Join-Path $HexaRoot 'config'
$Script:LogsDir       = Join-Path $HexaRoot 'logs'
$Script:BackupsDir    = Join-Path $HexaRoot 'backups'
$Script:ToolsDir      = Join-Path $HexaRoot 'tools'        # nssm.exe, cloudflared.exe
$Script:ApiService    = 'HexaApi'
$Script:TunnelService = 'Cloudflared'                      # name used by `cloudflared service install`
$Script:ApiPort       = 8000
$Script:ApiHost       = '127.0.0.1'                        # never 0.0.0.0: only the tunnel talks to the API
$Script:HealthUrl     = "http://127.0.0.1:$($Script:ApiPort)/health/ready"
$Script:LiveUrl       = "http://127.0.0.1:$($Script:ApiPort)/health/live"
$Script:KeepReleases  = 3
# 1 worker on purpose: rate limits and SSE realtime are per-process unless REDIS is configured
# (RATE_LIMIT_BACKEND=redis / REALTIME_BACKEND=redis). ~20 users is well within one async worker.
$Script:UvicornWorkers = 1

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    Write-Host $line
    if (Test-Path $Script:LogsDir) { Add-Content -Path (Join-Path $Script:LogsDir 'ops.log') -Value $line }
}

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated (Administrator) PowerShell.'
    }
}

function Find-PgTool {
    param([string]$Name)   # e.g. pg_dump.exe
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $hit = Get-ChildItem 'C:\Program Files\PostgreSQL' -Recurse -Filter $Name -ErrorAction SilentlyContinue |
           Sort-Object FullName -Descending | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    throw "$Name not found. Install PostgreSQL client tools or add the bin folder to PATH."
}
