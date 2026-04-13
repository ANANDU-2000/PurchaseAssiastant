import logging
from contextlib import asynccontextmanager

from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.middleware.trustedhost import TrustedHostMiddleware

from app.config import get_settings
from sqlalchemy import inspect

from app.database import engine
from app.models import Base
from app.routers import admin, ai_chat, analytics, auth, billing, catalog, contacts, entries, health, me, media, price_intelligence, razorpay_webhook, realtime, whatsapp

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
        await conn.run_sync(Base.metadata.create_all)

        def _ensure_entries_place(sync_conn):
            insp = inspect(sync_conn)
            if not insp.has_table("entries"):
                return
            cols = {c["name"] for c in insp.get_columns("entries")}
            if "place" in cols:
                return
            sync_conn.exec_driver_sql("ALTER TABLE entries ADD COLUMN place VARCHAR(512)")

        await conn.run_sync(_ensure_entries_place)

        def _ensure_suppliers_whatsapp_number(sync_conn):
            insp = inspect(sync_conn)
            if not insp.has_table("suppliers"):
                return
            cols = {c["name"] for c in insp.get_columns("suppliers")}
            if "whatsapp_number" in cols:
                return
            sync_conn.exec_driver_sql("ALTER TABLE suppliers ADD COLUMN whatsapp_number VARCHAR(32)")

        await conn.run_sync(_ensure_suppliers_whatsapp_number)

        def _ensure_entry_line_items_stock_note(sync_conn):
            insp = inspect(sync_conn)
            if not insp.has_table("entry_line_items"):
                return
            cols = {c["name"] for c in insp.get_columns("entry_line_items")}
            if "stock_note" in cols:
                return
            sync_conn.exec_driver_sql("ALTER TABLE entry_line_items ADD COLUMN stock_note VARCHAR(512)")

        await conn.run_sync(_ensure_entry_line_items_stock_note)

        def _ensure_platform_integration_razorpay(sync_conn):
            insp = inspect(sync_conn)
            if not insp.has_table("platform_integration"):
                return
            cols = {c["name"] for c in insp.get_columns("platform_integration")}
            alters = []
            if "razorpay_key_id" not in cols:
                alters.append("ALTER TABLE platform_integration ADD COLUMN razorpay_key_id VARCHAR(64)")
            if "razorpay_key_secret" not in cols:
                alters.append("ALTER TABLE platform_integration ADD COLUMN razorpay_key_secret TEXT")
            if "razorpay_webhook_secret" not in cols:
                alters.append("ALTER TABLE platform_integration ADD COLUMN razorpay_webhook_secret TEXT")
            for sql in alters:
                sync_conn.exec_driver_sql(sql)

        await conn.run_sync(_ensure_platform_integration_razorpay)

        def _ensure_businesses_branding(sync_conn):
            insp = inspect(sync_conn)
            if not insp.has_table("businesses"):
                return
            cols = {c["name"] for c in insp.get_columns("businesses")}
            if "branding_title" not in cols:
                sync_conn.exec_driver_sql("ALTER TABLE businesses ADD COLUMN branding_title VARCHAR(128)")
            if "branding_logo_url" not in cols:
                sync_conn.exec_driver_sql("ALTER TABLE businesses ADD COLUMN branding_logo_url VARCHAR(512)")

        await conn.run_sync(_ensure_businesses_branding)

        def _ensure_users_ai_budget_columns(sync_conn):
            """Older SQLite DBs may lack columns added after first deploy; create_all does not ALTER."""
            insp = inspect(sync_conn)
            if not insp.has_table("users"):
                return
            cols = {c["name"] for c in insp.get_columns("users")}
            if "ai_monthly_token_budget" not in cols:
                sync_conn.exec_driver_sql(
                    "ALTER TABLE users ADD COLUMN ai_monthly_token_budget INTEGER DEFAULT 100000"
                )
            if "ai_tokens_used_month" not in cols:
                sync_conn.exec_driver_sql(
                    "ALTER TABLE users ADD COLUMN ai_tokens_used_month INTEGER DEFAULT 0 NOT NULL"
                )

        await conn.run_sync(_ensure_users_ai_budget_columns)
    yield
    await engine.dispose()


app = FastAPI(title="My Purchases API", lifespan=lifespan)

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
    _cors_kwargs["allow_origin_regex"] = r"https?://(localhost|127\.0\.0\.1)(:\d+)?$"
app.add_middleware(CORSMiddleware, **_cors_kwargs)

if settings.trusted_hosts:
    hosts = [h.strip() for h in settings.trusted_hosts.split(",") if h.strip()]
    if hosts:
        app.add_middleware(TrustedHostMiddleware, allowed_hosts=hosts)

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(me.router)
app.include_router(entries.router)
app.include_router(ai_chat.router)
app.include_router(analytics.router)
app.include_router(price_intelligence.router)
app.include_router(catalog.router)
app.include_router(contacts.router)
app.include_router(media.router)
app.include_router(realtime.router)
app.include_router(admin.router)
app.include_router(billing.router)
app.include_router(razorpay_webhook.router)
app.include_router(whatsapp.router)
