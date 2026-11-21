<#
.SYNOPSIS  Install the Cloudflare Tunnel connector as an auto-start Windows service.
.DESCRIPTION
  Uses a remote-managed tunnel: create the tunnel in the Cloudflare dashboard (Zero Trust > Networks > Tunnels),
  add the public hostname  api.harisreeagency.online  ->  http://localhost:8000,
  then save the tunnel token (one line) to C:\hexa\config\cloudflared.token .
  The token is read from that file, never from the command line history or from git.
  Requires the zone to be active on Cloudflare (domain delegation must be fixed first).
#>
[CmdletBinding()] param([string]$TokenFile)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
Assert-Admin
if (-not $TokenFile) { $TokenFile = Join-Path $ConfigDir 'cloudflared.token' }
if (-not (Test-Path $TokenFile)) { throw "Token file not found: $TokenFile" }
$exe = Join-Path $ToolsDir 'cloudflared.exe'
if (-not (Test-Path $exe)) { throw "cloudflared.exe not found in $ToolsDir" }
$token = (Get-Content $TokenFile -Raw).Trim()
if ($token.Length -lt 40) { throw 'Token file looks empty or wrong.' }

if (Get-Service $TunnelService -ErrorAction SilentlyContinue) {
    Write-Log "$TunnelService already installed; leaving it as is. (To rotate: cloudflared service uninstall, then rerun.)" 'WARN'
} else {
    & $exe service install $token
    if ($LASTEXITCODE -ne 0) { throw "cloudflared service install failed ($LASTEXITCODE)" }
}
Set-Service $TunnelService -StartupType Automatic
sc.exe failure $TunnelService reset= 86400 actions= restart/5000/restart/5000/restart/30000 | Out-Null
Start-Service $TunnelService -ErrorAction SilentlyContinue
Start-Sleep 5
Write-Log ("tunnel service status: " + (Get-Service $TunnelService).Status)
Write-Host 'Verify from outside the server:  curl https://api.harisreeagency.online/health/live' -ForegroundColor Green
