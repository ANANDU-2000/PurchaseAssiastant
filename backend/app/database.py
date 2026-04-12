import ssl
from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import get_settings

settings = get_settings()

_sqlite = settings.database_url.startswith("sqlite")
_connect_args: dict = {"check_same_thread": False} if _sqlite else {}
if not _sqlite and "supabase.co" in settings.database_url:
    if settings.database_ssl_insecure:
        _ctx = ssl.create_default_context()
        _ctx.check_hostname = False
        _ctx.verify_mode = ssl.CERT_NONE
        _connect_args["ssl"] = _ctx
    else:
        _connect_args["ssl"] = True
    # asyncpg default connect timeout is 60s; slow TLS or cold pool can need more headroom.
    _connect_args.setdefault("timeout", 120)
engine = create_async_engine(
    settings.database_url,
    echo=settings.app_env == "development",
    connect_args=_connect_args,
)
async_session_factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_factory() as session:
        yield session
