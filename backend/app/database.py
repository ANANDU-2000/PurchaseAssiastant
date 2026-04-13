import logging
import ssl
from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import get_settings

logger = logging.getLogger(__name__)

settings = get_settings()

_sqlite = settings.database_url.startswith("sqlite")
_pooler = (settings.database_pooler_url or "").strip()
_effective_url = _pooler if _pooler else settings.database_url

if _pooler:
    logger.info("Using DATABASE_POOLER_URL for SQLAlchemy engine (Supabase pooler)")

_connect_args: dict = {"check_same_thread": False} if _sqlite else {}
if not _sqlite and (
    "supabase.co" in _effective_url or "pooler.supabase.com" in _effective_url
):
    if settings.database_ssl_insecure:
        _ctx = ssl.create_default_context()
        _ctx.check_hostname = False
        _ctx.verify_mode = ssl.CERT_NONE
        _connect_args["ssl"] = _ctx
    else:
        _connect_args["ssl"] = True
    _connect_args.setdefault("timeout", 120)

engine = create_async_engine(
    _effective_url,
    echo=settings.app_env == "development",
    connect_args=_connect_args,
)
async_session_factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_factory() as session:
        yield session
