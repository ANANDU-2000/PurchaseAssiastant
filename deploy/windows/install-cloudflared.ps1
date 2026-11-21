<#
.SYNOPSIS  Install the Cloudflare Tunnel connector as an auto-start Windows service (token kept in a file).
.DESCRIPTION
  Uses a remote-managed tunnel: create the tunnel in the Cloudflare dashboard (Zero Trust > Networks > Tunnels),
  add the public hostname  api.harisreeagency.online  ->  http://localhost:8000,
  then save the tunnel token (one line) to C:\hexa\config\cloudflared.token .

  Why not `cloudflared service install <token>`: that writes the token into the service's registry ImagePath,
  which any local user can read (e.g. `sc qc cloudflared`). Here the service is registered with NSSM and runs
  `cloudflared tunnel run --token-file <path>` (needs cloudflared 2025.4.0 or later), so the secret stays in the
  ACL-protected C:\hexa\config folder.
  Requires the zone to be active on Cloudflare (domain delegation must be fixed first).
#>
[CmdletBinding()] param([string]$TokenFile)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
Assert-Admin
if (-not $TokenFile) { $TokenFile = Join-Path $ConfigDir 'cloudflared.token' }
if (-not (Test-Path $TokenFile)) { throw "Token file not found: $TokenFile" }
$exe  = Join-Path $ToolsDir 'cloudflared.exe'
$nssm = Join-Path $ToolsDir 'nssm.exe'
if (-not (Test-Path $exe))  { throw "cloudflared.exe not found in $ToolsDir" }
if (-not (Test-Path $nssm)) { throw "nssm.exe not found in $ToolsDir" }
if ((Get-Content $TokenFile -Raw).Trim().Length -lt 40) { throw 'Token file looks empty or wrong.' }

# The token file must not be readable by ordinary users.
icacls $TokenFile /inheritance:r /grant:r 'SYSTEM:F' 'Administrators:F' | Out-Null

# cloudflared must be new enough for --token-file.
$ver = (& $exe --version) -join ' '
if ($ver -match '(\d{4})\.(\d+)\.(\d+)') {
    if ([int]$Matches[1] -lt 2025 -or ([int]$Matches[1] -eq 2025 -and [int]$Matches[2] -lt 4)) {
        throw "cloudflared $($Matches[0]) is too old for --token-file (need 2025.4.0+). Download a newer cloudflared.exe."
    }
}

# Remove the legacy cloudflared-managed service if an earlier install created one (it embeds the token).
$legacy = Get-CimInstance Win32_Service -Filter "Name='$TunnelService'" -ErrorAction SilentlyContinue
if ($legacy -and $legacy.PathName -notmatch 'nssm') {
    Write-Log "removing legacy $TunnelService service that stores the token in the registry" 'WARN'
    Stop-Service $TunnelService -ErrorAction SilentlyContinue
    & $exe service uninstall | Out-Null
}

$svcArgs = "tunnel --no-autoupdate --logfile `"$(Join-Path $LogsDir 'cloudflared.log')`" run --token-file `"$TokenFile`""
if (-not (& $nssm status $TunnelService 2>$null)) {
    & $nssm install $TunnelService $exe $svcArgs | Out-Null
} else {
    & $nssm set $TunnelService Application $exe | Out-Null
    & $nssm set $TunnelService AppParameters $svcArgs | Out-Null
}
& $nssm set $TunnelService Start SERVICE_AUTO_START | Out-Null
& $nssm set $TunnelService AppExit Default Restart | Out-Null
& $nssm set $TunnelService AppRestartDelay 5000 | Out-Null
& $nssm set $TunnelService AppStdout (Join-Path $LogsDir 'cloudflared.out.log') | Out-Null
& $nssm set $TunnelService AppStderr (Join-Path $LogsDir 'cloudflared.err.log') | Out-Null
& $nssm set $TunnelService AppRotateFiles 1 | Out-Null
& $nssm set $TunnelService AppRotateBytes 10485760 | Out-Null
& $nssm start $TunnelService | Out-Null
Start-Sleep 5
Write-Log ("tunnel service status: " + (Get-Service $TunnelService).Status)
Write-Host 'cloudflared is not auto-updated (--no-autoupdate): update cloudflared.exe deliberately, then restart the service.' -ForegroundColor Yellow
Write-Host 'Verify from outside the server:  curl https://api.harisreeagency.online/health/live' -ForegroundColor Green
