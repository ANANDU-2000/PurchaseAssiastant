import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.trustedhost import TrustedHostMiddleware

from app.config import get_settings
from app.database import engine
from app.models import Base
from app.routers import admin, ai_chat, analytics, auth, catalog, contacts, entries, health, me, media, price_intelligence, realtime, whatsapp

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    settings.validate_production_safety()
    logging.basicConfig(level=getattr(logging, settings.log_level.upper(), logging.INFO))

    if settings.sentry_dsn:
        try:
            import sentry_sdk

            sentry_sdk.init(dsn=settings.sentry_dsn, environment=settings.app_env)
            logger.info("Sentry initialized")
        except Exception as e:  # noqa: BLE001
            logger.warning("Sentry init failed: %s", e)

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    await engine.dispose()


app = FastAPI(title="HEXA Purchase Assistant", lifespan=lifespan)

settings = get_settings()
origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins or ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
app.include_router(whatsapp.router)
