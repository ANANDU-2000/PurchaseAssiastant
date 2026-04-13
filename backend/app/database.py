import logging
import ssl
from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import get_settings

logger = logging.getLogger(__name__)

settings = get_settings()


def _normalize_postgres_async_url(url: str) -> str:
    """Ensure async engine uses asyncpg. Plain postgresql:// selects psycopg2 and breaks startup."""
    if url.startswith("postgresql+asyncpg://") or url.startswith("postgres+asyncpg://"):
        return url
    if url.startswith("postgresql://"):
        return "postgresql+asyncpg://" + url.removeprefix("postgresql://")
    if url.startswith("postgres://"):
        return "postgresql+asyncpg://" + url.removeprefix("postgres://")
    return url


_sqlite = settings.database_url.startswith("sqlite")
_pooler = (settings.database_pooler_url or "").strip()
_effective_url = _pooler if _pooler else settings.database_url
if not _sqlite:
    _effective_url = _normalize_postgres_async_url(_effective_url)

if _pooler:
    logger.info("Using DATABASE_POOLER_URL for SQLAlchemy engine")
    if not _pooler.startswith(("postgresql+asyncpg://", "postgres+asyncpg://")) and (
        _pooler.startswith("postgresql://") or _pooler.startswith("postgres://")
    ):
        logger.info(
            "Normalized DATABASE_POOLER_URL to postgresql+asyncpg:// (Supabase often pastes postgresql://)."
        )
    elif not _pooler.startswith(("postgresql+asyncpg://", "postgres+asyncpg://")):
        logger.warning(
            "DATABASE_POOLER_URL should use postgresql+asyncpg:// (or plain postgresql://, which we normalize)."
        )
    # Direct host + 5432 is NOT the pooler — Render often gets Errno 101 to db.*.supabase.co.
    if (
        "db." in _pooler
        and ".supabase.co" in _pooler
        and ":5432" in _pooler
        and "pooler.supabase.com" not in _pooler
    ):
        logger.warning(
            "DATABASE_POOLER_URL looks like a direct Supabase URL (db.*.supabase.co:5432). "
            "Copy the pooler string from Supabase Dashboard → Connect → "
            "Transaction pooler (host aws-0-*.pooler.supabase.com, port 6543) or Session pooler."
        )

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
