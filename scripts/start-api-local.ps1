# Start the Purchase Assistant FastAPI backend for local Flutter/web dev.
# Default: SQLite (no Postgres). API: http://127.0.0.1:8000/docs
#
# Usage (from repo root):
#   .\scripts\start-api-local.ps1
#
# Then in another terminal (flutter_app):
#   .\run_web_dev.ps1
#
# To use Postgres instead: set HEXA_USE_SQLITE= (empty) and DATABASE_URL before running.

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $RepoRoot 'backend')

if (-not $env:HEXA_USE_SQLITE) {
  $env:HEXA_USE_SQLITE = '1'
}

$py = if (Test-Path '.\.venv\Scripts\python.exe') {
  Resolve-Path '.\.venv\Scripts\python.exe'
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
  'python'
} else {
  Write-Error 'No Python found. Create a venv: python -m venv .venv; .\.venv\Scripts\pip install -r requirements.txt'
}

Write-Host ""
Write-Host "Starting API on http://127.0.0.1:8000  (HEXA_USE_SQLITE=$($env:HEXA_USE_SQLITE))"
Write-Host "Open http://127.0.0.1:8000/docs  — Ctrl+C to stop"
Write-Host ""

& $py -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
