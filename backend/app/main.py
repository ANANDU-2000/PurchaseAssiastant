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
from sqlalchemy import inspect

from app.database import engine
from app.models import Base
from app.routers import (
    admin,
    ai_chat,
    analytics,
    auth,
    billing,
    catalog,
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
            if "gst_number" not in cols:
                sync_conn.exec_driver_sql("ALTER TABLE businesses ADD COLUMN gst_number VARCHAR(20)")
            if "address" not in cols:
                sync_conn.exec_driver_sql("ALTER TABLE businesses ADD COLUMN address TEXT")
            if "phone" not in cols:
                sync_conn.exec_driver_sql("ALTER TABLE businesses ADD COLUMN phone VARCHAR(32)")

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

        def _ensure_catalog_items_type_id(sync_conn):
            """Prod DBs created before CategoryType layer may lack catalog_items.type_id; create_all does not ALTER."""
            insp = inspect(sync_conn)
            if not insp.has_table("catalog_items"):
                return
            cols = {c["name"] for c in insp.get_columns("catalog_items")}
            if "type_id" in cols:
                return
            dialect = sync_conn.dialect.name
            if dialect == "postgresql":
                sync_conn.exec_driver_sql(
                    "ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS type_id UUID NULL"
                )
                if insp.has_table("category_types"):
                    sync_conn.exec_driver_sql(
                        "CREATE INDEX IF NOT EXISTS ix_catalog_items_type_id ON catalog_items (type_id)"
                    )
                    sync_conn.exec_driver_sql(
                        """
                        DO $do$
                        BEGIN
                          IF NOT EXISTS (
                            SELECT 1 FROM pg_constraint
                            WHERE conname = 'catalog_items_type_id_fkey'
                          ) THEN
                            ALTER TABLE catalog_items
                              ADD CONSTRAINT catalog_items_type_id_fkey
                              FOREIGN KEY (type_id) REFERENCES category_types(id) ON DELETE SET NULL;
                          END IF;
                        END
                        $do$;
                        """
                    )
            else:
                # SQLite and others: store UUID as string; FK optional
                try:
                    sync_conn.exec_driver_sql(
                        "ALTER TABLE catalog_items ADD COLUMN type_id VARCHAR(36) NULL"
                    )
                except Exception:  # noqa: BLE001
                    pass

        await conn.run_sync(_ensure_catalog_items_type_id)

        def _ensure_catalog_items_item_code(sync_conn):
            insp = inspect(sync_conn)
            if not insp.has_table("catalog_items"):
                return
            cols = {c["name"] for c in insp.get_columns("catalog_items")}
            if "item_code" in cols:
                return
            try:
                sync_conn.exec_driver_sql(
                    "ALTER TABLE catalog_items ADD COLUMN item_code VARCHAR(64) NULL"
                )
            except Exception:  # noqa: BLE001
                pass

        await conn.run_sync(_ensure_catalog_items_item_code)

        def _ensure_supplier_wholesale_columns(sync_conn):
            insp = inspect(sync_conn)
            if not insp.has_table("suppliers"):
                return
            cols = {c["name"] for c in insp.get_columns("suppliers")}
            alters: list[str] = []
            if "gst_number" not in cols:
                alters.append("ALTER TABLE suppliers ADD COLUMN gst_number VARCHAR(20)")
            if "default_payment_days" not in cols:
                alters.append("ALTER TABLE suppliers ADD COLUMN default_payment_days INTEGER")
            if "default_discount" not in cols:
                alters.append("ALTER TABLE suppliers ADD COLUMN default_discount NUMERIC(18, 4)")
            if "default_delivered_rate" not in cols:
                alters.append("ALTER TABLE suppliers ADD COLUMN default_delivered_rate NUMERIC(18, 4)")
            if "default_billty_rate" not in cols:
                alters.append("ALTER TABLE suppliers ADD COLUMN default_billty_rate NUMERIC(18, 4)")
            for sql in alters:
                try:
                    sync_conn.exec_driver_sql(sql)
                except Exception:  # noqa: BLE001
                    pass

        await conn.run_sync(_ensure_supplier_wholesale_columns)

        def _ensure_supplier_profile_columns(sync_conn):
            insp = inspect(sync_conn)
            if not insp.has_table("suppliers"):
                return
            cols = {c["name"] for c in insp.get_columns("suppliers")}
            alters: list[str] = []
            if "address" not in cols:
                alters.append("ALTER TABLE suppliers ADD COLUMN address TEXT")
            if "notes" not in cols:
                alters.append("ALTER TABLE suppliers ADD COLUMN notes TEXT")
            if "freight_type" not in cols:
                alters.append("ALTER TABLE suppliers ADD COLUMN freight_type VARCHAR(16)")
            if "ai_memory_enabled" not in cols:
                dialect = sync_conn.dialect.name
                if dialect == "postgresql":
                    alters.append(
                        "ALTER TABLE suppliers ADD COLUMN ai_memory_enabled BOOLEAN NOT NULL DEFAULT false"
                    )
                else:
                    alters.append(
                        "ALTER TABLE suppliers ADD COLUMN ai_memory_enabled INTEGER NOT NULL DEFAULT 0"
                    )
            if "preferences_json" not in cols:
                alters.append("ALTER TABLE suppliers ADD COLUMN preferences_json TEXT")
            for sql in alters:
                try:
                    sync_conn.exec_driver_sql(sql)
                except Exception:  # noqa: BLE001
                    pass

        await conn.run_sync(_ensure_supplier_profile_columns)

        def _ensure_broker_phone_column(sync_conn):
            insp = inspect(sync_conn)
            if not insp.has_table("brokers"):
                return
            cols = {c["name"] for c in insp.get_columns("brokers")}
            alters: list[str] = []
            if "phone" not in cols:
                alters.append("ALTER TABLE brokers ADD COLUMN phone VARCHAR(15)")
            if "whatsapp_number" not in cols:
                alters.append("ALTER TABLE brokers ADD COLUMN whatsapp_number VARCHAR(32)")
            if "location" not in cols:
                alters.append("ALTER TABLE brokers ADD COLUMN location TEXT")
            if "notes" not in cols:
                alters.append("ALTER TABLE brokers ADD COLUMN notes TEXT")
            if "preferences_json" not in cols:
                alters.append("ALTER TABLE brokers ADD COLUMN preferences_json TEXT")
            for sql in alters:
                try:
                    sync_conn.exec_driver_sql(sql)
                except Exception:  # noqa: BLE001
                    pass

        await conn.run_sync(_ensure_broker_phone_column)

        def _ensure_catalog_item_trade_columns(sync_conn):
            insp = inspect(sync_conn)
            if not insp.has_table("catalog_items"):
                return
            cols = {c["name"] for c in insp.get_columns("catalog_items")}
            alters: list[str] = []
            if "hsn_code" not in cols:
                alters.append("ALTER TABLE catalog_items ADD COLUMN hsn_code VARCHAR(32)")
            if "tax_percent" not in cols:
                alters.append("ALTER TABLE catalog_items ADD COLUMN tax_percent NUMERIC(18, 4)")
            if "default_landing_cost" not in cols:
                alters.append("ALTER TABLE catalog_items ADD COLUMN default_landing_cost NUMERIC(18, 4)")
            if "default_selling_cost" not in cols:
                alters.append("ALTER TABLE catalog_items ADD COLUMN default_selling_cost NUMERIC(18, 4)")
            if "default_purchase_unit" not in cols:
                alters.append("ALTER TABLE catalog_items ADD COLUMN default_purchase_unit VARCHAR(32)")
            if "default_sale_unit" not in cols:
                alters.append("ALTER TABLE catalog_items ADD COLUMN default_sale_unit VARCHAR(32)")
            if "last_purchase_price" not in cols:
                alters.append("ALTER TABLE catalog_items ADD COLUMN last_purchase_price NUMERIC(18, 4)")
            if "default_items_per_box" not in cols:
                alters.append("ALTER TABLE catalog_items ADD COLUMN default_items_per_box NUMERIC(18, 4)")
            if "default_weight_per_tin" not in cols:
                alters.append("ALTER TABLE catalog_items ADD COLUMN default_weight_per_tin NUMERIC(18, 4)")
            for sql in alters:
                try:
                    sync_conn.exec_driver_sql(sql)
                except Exception:  # noqa: BLE001
                    pass

        await conn.run_sync(_ensure_catalog_item_trade_columns)

        def _ensure_trade_purchases_freight_type(sync_conn):
            insp = inspect(sync_conn)
            if not insp.has_table("trade_purchases"):
                return
            cols = {c["name"] for c in insp.get_columns("trade_purchases")}
            if "freight_type" not in cols:
                try:
                    sync_conn.exec_driver_sql(
                        "ALTER TABLE trade_purchases ADD COLUMN freight_type VARCHAR(16)"
                    )
                except Exception:  # noqa: BLE001
                    pass

        await conn.run_sync(_ensure_trade_purchases_freight_type)

        def _ensure_trade_purchases_lifecycle_columns(sync_conn):
            insp = inspect(sync_conn)
            if not insp.has_table("trade_purchases"):
                return
            cols = {c["name"] for c in insp.get_columns("trade_purchases")}
            dialect = sync_conn.dialect.name
            alters: list[str] = []
            if "due_date" not in cols:
                if dialect == "postgresql":
                    alters.append("ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS due_date DATE NULL")
                else:
                    alters.append("ALTER TABLE trade_purchases ADD COLUMN due_date DATE")
            if "paid_amount" not in cols:
                if dialect == "postgresql":
                    alters.append(
                        "ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(18,4) NOT NULL DEFAULT 0"
                    )
                else:
                    alters.append(
                        "ALTER TABLE trade_purchases ADD COLUMN paid_amount NUMERIC(18,4) NOT NULL DEFAULT 0"
                    )
            if "paid_at" not in cols:
                if dialect == "postgresql":
                    alters.append(
                        "ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ NULL"
                    )
                else:
                    alters.append("ALTER TABLE trade_purchases ADD COLUMN paid_at DATETIME")
            if "payment_days" not in cols:
                if dialect == "postgresql":
                    alters.append(
                        "ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS payment_days INTEGER NULL"
                    )
                else:
                    alters.append("ALTER TABLE trade_purchases ADD COLUMN payment_days INTEGER")
            if "invoice_number" not in cols:
                if dialect == "postgresql":
                    alters.append(
                        "ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS invoice_number VARCHAR(64) NULL"
                    )
                else:
                    alters.append(
                        "ALTER TABLE trade_purchases ADD COLUMN invoice_number VARCHAR(64) NULL"
                    )
            for sql in alters:
                try:
                    sync_conn.exec_driver_sql(sql)
                except Exception:  # noqa: BLE001
                    pass

        await conn.run_sync(_ensure_trade_purchases_lifecycle_columns)

        def _ensure_trade_purchase_line_columns(sync_conn):
            insp = inspect(sync_conn)
            if not insp.has_table("trade_purchase_lines"):
                return
            cols = {c["name"] for c in insp.get_columns("trade_purchase_lines")}
            dialect = sync_conn.dialect.name
            alters: list[str] = []
            if "payment_days" not in cols:
                alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN payment_days INTEGER NULL")
            if "hsn_code" not in cols:
                alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN hsn_code VARCHAR(32) NULL")
            if "description" not in cols:
                if dialect == "postgresql":
                    alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS description VARCHAR(512) NULL")
                else:
                    alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN description VARCHAR(512) NULL")
            if "kg_per_unit" not in cols:
                if dialect == "postgresql":
                    alters.append(
                        "ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS kg_per_unit NUMERIC(18,4) NULL"
                    )
                else:
                    alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN kg_per_unit NUMERIC(18,4) NULL")
            if "landing_cost_per_kg" not in cols:
                if dialect == "postgresql":
                    alters.append(
                        "ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS landing_cost_per_kg NUMERIC(18,4) NULL"
                    )
                else:
                    alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN landing_cost_per_kg NUMERIC(18,4) NULL")
            for sql in alters:
                try:
                    sync_conn.exec_driver_sql(sql)
                except Exception:  # noqa: BLE001
                    pass

        await conn.run_sync(_ensure_trade_purchase_line_columns)

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
app.include_router(contacts.router)
app.include_router(media.router)
app.include_router(realtime.router)
app.include_router(admin.router)
app.include_router(billing.router)
app.include_router(razorpay_webhook.router)
