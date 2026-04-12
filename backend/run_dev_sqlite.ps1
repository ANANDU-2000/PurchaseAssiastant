# Local API with SQLite (no Postgres/Redis). Fixes common 500s when DATABASE_URL points at Postgres but Docker is off.
Set-Location $PSScriptRoot
$env:DATABASE_URL = "sqlite+aiosqlite:///./hexa_dev.db"
$env:REDIS_URL = ""
$env:APP_ENV = "development"
& .\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
