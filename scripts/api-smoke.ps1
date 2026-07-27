# Authenticated API smoke against production (or API_BASE_URL).
# Usage:
#   $env:SMOKE_EMAIL="owner@example.com"; $env:SMOKE_PASSWORD="secret"
#   powershell -File scripts/api-smoke.ps1
#
# Optional: SMOKE_API_BASE, SMOKE_BUSINESS_ID, SMOKE_CATALOG_ITEM_ID
$ErrorActionPreference = "Stop"

$base = if ($env:SMOKE_API_BASE) { $env:SMOKE_API_BASE.TrimEnd('/') } else { "https://my-purchases-api.onrender.com" }
$email = $env:SMOKE_EMAIL
$password = $env:SMOKE_PASSWORD

if (-not $email -or -not $password) {
  Write-Host "Set SMOKE_EMAIL and SMOKE_PASSWORD to run authenticated smoke." -ForegroundColor Yellow
  Write-Host "Skipping auth endpoints; running public health only."
  $token = $null
} else {
  $loginBody = @{ email = $email; password = $password } | ConvertTo-Json
  $login = Invoke-RestMethod -Uri "$base/v1/auth/login" -Method Post -Body $loginBody -ContentType "application/json" -TimeoutSec 90
  $token = $login.access_token
  if (-not $token) { throw "Login failed: no access_token" }
  Write-Host "OK login as $email"
}

$headers = @{}
if ($token) { $headers["Authorization"] = "Bearer $token" }

function Test-Get {
  param([string]$Path, [string]$Label, [int[]]$Allowed = @(200))
  $url = "$base$Path"
  try {
    $r = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 120
    $code = [int]$r.StatusCode
    if ($Allowed -notcontains $code) {
      Write-Host "FAIL $Label -> $code (expected $($Allowed -join ','))" -ForegroundColor Red
      return $false
    }
    Write-Host "OK $Label -> $code"
    return $true
  } catch {
    $code = $null
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    Write-Host "FAIL $Label -> $code $($_.Exception.Message)" -ForegroundColor Red
    return $false
  }
}

$ok = $true
$today = Get-Date -Format "yyyy-MM-dd"
$from = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")

if (-not (Test-Get "/health/ready" "health/ready")) { $ok = $false }

if (-not $token) {
  if (-not $ok) { exit 1 }
  Write-Host "Public smoke passed. Set credentials for full matrix." -ForegroundColor Green
  exit 0
}

$bizId = $env:SMOKE_BUSINESS_ID
if (-not $bizId) {
  $biz = Invoke-RestMethod -Uri "$base/v1/me/businesses" -Headers $headers -TimeoutSec 90
  if (-not $biz -or $biz.Count -lt 1) { throw "No businesses for smoke user" }
  $bizId = $biz[0].id
}
Write-Host "business_id=$bizId"
$prefix = "/v1/businesses/$bizId"

$checks = @(
  @{ Path = "$prefix/dashboard"; Label = "dashboard" },
  @{ Path = "$prefix/reports/home-overview"; Label = "reports/home-overview" },
  @{ Path = "$prefix/reports/trade-summary?from=$from&to=$today"; Label = "reports/trade-summary" },
  @{ Path = "$prefix/reports/trade-items?from=$from&to=$today&limit=5"; Label = "reports/trade-items" },
  @{ Path = "$prefix/stock/list?per_page=5"; Label = "stock/list" },
  @{ Path = "$prefix/stock/low-stock/summary"; Label = "low-stock/summary" },
  @{ Path = "$prefix/stock/low-stock/operations?per_page=5"; Label = "low-stock/operations" },
  @{ Path = "$prefix/catalog-items?limit=5"; Label = "catalog-items" },
  @{ Path = "$prefix/trade-purchases?limit=5"; Label = "trade-purchases" }
)

foreach ($c in $checks) {
  if (-not (Test-Get $c.Path $c.Label)) { $ok = $false }
}

$itemId = $env:SMOKE_CATALOG_ITEM_ID
if (-not $itemId) {
  try {
    $stock = Invoke-RestMethod -Uri "$base$prefix/stock/list?per_page=1" -Headers $headers -TimeoutSec 120
    if ($stock.items -and $stock.items.Count -gt 0) {
      $itemId = $stock.items[0].id
    }
  } catch { }
}
if ($itemId) {
  Write-Host "catalog_item_id=$itemId"
  if (-not (Test-Get "$prefix/stock/$itemId" "stock/detail")) { $ok = $false }
  if (-not (Test-Get "$prefix/catalog-items/$itemId" "catalog-item")) { $ok = $false }
  if (-not (Test-Get "$prefix/reports/item/$itemId`?from=$from&to=$today&limit=10" "reports/item")) { $ok = $false }
} else {
  Write-Host "WARN: no catalog item for detail smoke" -ForegroundColor Yellow
}

if (-not $ok) { exit 1 }
Write-Host ""
Write-Host "API smoke passed ($base)." -ForegroundColor Green
