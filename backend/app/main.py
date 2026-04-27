import logging
import time
import traceback
from contextlib import asynccontextmanager

from pathlib import Path

from fastapi import FastAPI
from starlette.requests import Request
from starlette.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.middleware.trustedhost import TrustedHostMiddleware

from app.config import get_settings

from app.database import engine, is_sqlite_runtime
from app.sqlite_bootstrap import apply_sqlite_bootstrap
from app.routers import (
    admin,
    ai_chat,
    analytics,
    auth,
    billing,
    catalog,
    cloud_expense,
    contacts,
    dashboard,
    entries,
    health,
    me,
    media,
    price_intelligence,
    razorpay_webhook,
    realtime,
    reports_trade,
    search,
    trade_purchases,
)

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    settings.validate_production_safety()
    logging.basicConfig(level=getattr(logging, settings.log_level.upper(), logging.INFO))

    if settings.sentry_dsn:
        try:
            import sentry_sdk

            sentry_sdk.init(
                dsn=settings.sentry_dsn,
                environment=settings.app_env,
                traces_sample_rate=0.1 if settings.app_env == "production" else 0.0,
            )
            logger.info("Sentry initialized")
        except Exception as e:  # noqa: BLE001
            logger.warning("Sentry init failed: %s", e)

    async with engine.begin() as conn:
        if is_sqlite_runtime():
            await conn.run_sync(apply_sqlite_bootstrap)
        else:
            logger.info(
                "Postgres: schema is managed by Alembic only — run `alembic upgrade head` before deploy. "
                "Startup does not execute create_all or ad-hoc ALTERs."
            )

    scheduler = None
    try:
        from zoneinfo import ZoneInfo

        from apscheduler.schedulers.asyncio import AsyncIOScheduler

        scheduler = AsyncIOScheduler(timezone=ZoneInfo("Asia/Kolkata"))

        def _due_soon_tick() -> None:
            """Hook: scan due-soon trade purchases; extend with DB + push/WhatsApp if needed."""
            logger.info("due_soon_reminder: tick (use app.services.monthly_payment_reminder)")

        scheduler.add_job(
            _due_soon_tick, "cron", hour=8, minute=0, id="due_soon_scan", replace_existing=True
        )
        scheduler.start()
        logger.info("APScheduler: due_soon job registered (08:00 Asia/Kolkata)")
    except Exception as e:  # noqa: BLE001
        logger.warning("APScheduler not started: %s", e)

    yield
    if scheduler is not None:
        try:
            scheduler.shutdown(wait=False)
        except Exception:  # noqa: BLE001
            pass
    await engine.dispose()


app = FastAPI(title="Harisree Purchases API", lifespan=lifespan)


@app.middleware("http")
async def harisree_request_monitor_middleware(request: Request, call_next):
    start = time.perf_counter()
    try:
        response = await call_next(request)
        ms = int((time.perf_counter() - start) * 1000)
        if response.status_code >= 500:
            logger.error(
                "HTTP %s | %s %s | %sms",
                response.status_code,
                request.method,
                request.url.path,
                ms,
            )
        elif response.status_code >= 400:
            logger.warning(
                "HTTP %s | %s %s | %sms",
                response.status_code,
                request.method,
                request.url.path,
                ms,
            )
        elif ms > 3000:
            logger.warning("SLOW %sms | %s %s", ms, request.method, request.url.path)
        return response
    except Exception:  # noqa: BLE001
        logger.error(
            "CRASH | %s %s\n%s",
            request.method,
            request.url.path,
            traceback.format_exc(),
        )
        return JSONResponse(
            status_code=500,
            content={"detail": "Internal server error"},
        )


_backend_root = Path(__file__).resolve().parent.parent
_static_root = _backend_root / "static"
_static_root.mkdir(exist_ok=True)
(_static_root / "branding").mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(_static_root)), name="static")

settings = get_settings()
# Browsers reject Access-Control-Allow-Origin: * together with credentialed requests.
# Flutter web (localhost / 127.0.0.1) needs explicit origins when using Authorization headers.
# If CORS_ORIGINS is set but omits Flutter web (e.g. only :5173), the browser hides response bodies
# from JS — Dio looks like "network error" while DevTools may still show 4xx/5xx.
_DEFAULT_LOCAL_CORS_ORIGINS = [
    "http://localhost:8080",
    "http://127.0.0.1:8080",
    "http://localhost:8082",
    "http://127.0.0.1:8082",
    "http://localhost:5173",
    "http://127.0.0.1:5173",
    "http://localhost:5174",
    "http://127.0.0.1:5174",
    "http://localhost:5175",
    "http://127.0.0.1:5175",
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "http://localhost:8081",
    "http://127.0.0.1:8081",
    "http://localhost:8090",
    "http://127.0.0.1:8090",
    "http://localhost:8091",
    "http://127.0.0.1:8091",
    "http://localhost:8092",
    "http://127.0.0.1:8092",
]
_origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
if not _origins:
    _origins = list(_DEFAULT_LOCAL_CORS_ORIGINS)
elif settings.app_env.lower() == "development":
    _seen = set(_origins)
    for _o in _DEFAULT_LOCAL_CORS_ORIGINS:
        if _o not in _seen:
            _origins.append(_o)
            _seen.add(_o)
_cors_kwargs = dict(
    allow_origins=_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
# Flutter web `flutter run -d chrome` often picks a random port; listing every port in CORS_ORIGINS is impractical.
# In development only, allow any http(s) localhost / 127.0.0.1 origin. Production must set explicit CORS_ORIGINS.
if settings.app_env.lower() == "development":
    # Flutter web may be served as http://[::1]:PORT on some systems — include IPv6 loopback.
    _cors_kwargs["allow_origin_regex"] = (
        r"https?://(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$"
    )
app.add_middleware(CORSMiddleware, **_cors_kwargs)

if settings.trusted_hosts:
    hosts = [h.strip() for h in settings.trusted_hosts.split(",") if h.strip()]
    if hosts:
        app.add_middleware(TrustedHostMiddleware, allowed_hosts=hosts)

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(me.router)
app.include_router(entries.router)
app.include_router(trade_purchases.router)
app.include_router(reports_trade.router)
app.include_router(search.router)
app.include_router(ai_chat.router)
app.include_router(analytics.router)
app.include_router(dashboard.router)
app.include_router(price_intelligence.router)
app.include_router(catalog.router)
app.include_router(cloud_expense.router)
app.include_router(contacts.router)
app.include_router(media.router)
app.include_router(realtime.router)
app.include_router(admin.router)
app.include_router(billing.router)
app.include_router(razorpay_webhook.router)
