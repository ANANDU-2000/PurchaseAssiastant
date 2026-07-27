# Start the Purchase Assistant FastAPI backend for local Flutter/web dev.
# Default: SQLite (no Postgres). Default port: 8000 (matches Flutter API_BASE_URL default).
#
# Usage (from repo root):
#   .\scripts\start-api-local.ps1
#   .\scripts\start-api-local.ps1 -Port 8010
#
# If port 8000 fails with WinError 10013, use -Port 8010 and run Flutter with:
#   --dart-define=API_BASE_URL=http://127.0.0.1:8010
#
# Then in another terminal (flutter_app):
#   .\run_web_dev.ps1
#
# To use Postgres instead: set HEXA_USE_SQLITE= (empty) and DATABASE_URL before running.

param(
  [int] $Port = 8000
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $RepoRoot 'backend')

if (-not $env:HEXA_USE_SQLITE) {
  $env:HEXA_USE_SQLITE = '1'
}

$py = if (Test-Path '.\.venv\Scripts\python.exe') {
  (Resolve-Path '.\.venv\Scripts\python.exe').Path
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
  'python'
} else {
  Write-Error 'No Python found. Create a venv: python -m venv .venv; .\.venv\Scripts\pip install -r requirements.txt'
}

Write-Host ""
Write-Host "Starting API on http://127.0.0.1:$Port  (HEXA_USE_SQLITE=$($env:HEXA_USE_SQLITE))"
Write-Host "Open http://127.0.0.1:$Port/docs  (Ctrl+C to stop)"
Write-Host ""

& $py -m uvicorn app.main:app --reload --host 127.0.0.1 --port $Port
