# Start HEXA API + Flutter web (static build). Opens the app in your browser.
# Prereq: `cd flutter_app && flutter build web` once so `flutter_app\build\web` exists.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$backend = Join-Path $root "backend"
$web = Join-Path $root "flutter_app\build\web"

if (-not (Test-Path (Join-Path $web "index.html"))) {
    Write-Host "Missing flutter_app\build\web — run: cd flutter_app && flutter build web" -ForegroundColor Yellow
    exit 1
}

$venvPy = Join-Path $backend ".venv\Scripts\python.exe"
$py = if (Test-Path $venvPy) { $venvPy } else { "python" }

Write-Host "Starting API on http://127.0.0.1:8000 ..." -ForegroundColor Cyan
Start-Process powershell -WorkingDirectory $backend -ArgumentList @(
    "-NoExit", "-Command",
    "& '$py' -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000"
)

Start-Sleep -Seconds 2

Write-Host "Starting web on http://127.0.0.1:8095 ..." -ForegroundColor Cyan
Start-Process powershell -WorkingDirectory $web -ArgumentList @(
    "-NoExit", "-Command",
    "python -m http.server 8095 --bind 127.0.0.1"
)

Start-Sleep -Seconds 1
Write-Host "Opening browser..." -ForegroundColor Green
Start-Process "http://127.0.0.1:8095/"
Write-Host "API docs: http://127.0.0.1:8000/docs" -ForegroundColor Green
