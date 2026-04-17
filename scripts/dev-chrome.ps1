# One-shot local dev: FastAPI on 127.0.0.1:8000 + Flutter web on Chrome :8080 (API_BASE_URL aligned).
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$backend = Join-Path $root "backend"
$flutterApp = Join-Path $root "flutter_app"
$venvPy = Join-Path $backend ".venv\Scripts\python.exe"
$py = if (Test-Path $venvPy) { $venvPy } else { "python" }

Write-Host "Starting API: $py -m uvicorn ... (new window)" -ForegroundColor Cyan
Start-Process powershell -WorkingDirectory $backend -ArgumentList @(
    "-NoExit", "-Command",
    "& '$py' -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000"
)

Start-Sleep -Seconds 3

Push-Location $flutterApp
try {
    Write-Host "Flutter web on http://127.0.0.1:8080 (API http://127.0.0.1:8000)" -ForegroundColor Cyan
    flutter run -d chrome `
        --web-port=8080 `
        --no-web-resources-cdn `
        --dart-define=API_BASE_URL=http://127.0.0.1:8000
}
finally {
    Pop-Location
}
