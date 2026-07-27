import logging
import os
import ssl
import time
from collections.abc import AsyncGenerator

# Use OS trust store (Ubuntu on Render) — needed for SSL to Render Postgres
# when certifi alone does not include the necessary CA chain.
try:
    import truststore

    truststore.inject_into_ssl()
except ImportError:
    pass

from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine

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


# Set HEXA_USE_SQLITE=1 to use local SQLite for development/testing.
if os.environ.get("HEXA_USE_SQLITE", "").strip().lower() in ("1", "true", "yes"):
    _default_sqlite = "sqlite+aiosqlite:///./hexa_dev.db"
    raw = (os.environ.get("DATABASE_URL") or "").strip()
    if raw.startswith("sqlite"):
        _sqlite_url = raw
    else:
        if raw:
            logger.warning(
                "HEXA_USE_SQLITE is set but DATABASE_URL is not sqlite; using %s",
                _default_sqlite,
            )
        _sqlite_url = _default_sqlite
    _sqlite = True
    _effective_url = _sqlite_url
    logger.info("HEXA_USE_SQLITE: using local SQLite (%s)", _sqlite_url)
else:
    _sqlite = settings.database_url.startswith("sqlite")
    _effective_url = settings.database_url if _sqlite else _normalize_postgres_async_url(settings.database_url)

_connect_args: dict = {"check_same_thread": False} if _sqlite else {}
# asyncpg caches prepared statements per connection. Disable for PgBouncer/pooler
# compatibility; can be re-enabled for direct Postgres connections.
if not _sqlite:
    _connect_args["statement_cache_size"] = 0

if not _sqlite and settings.database_command_timeout_seconds and settings.database_command_timeout_seconds > 0:
    _connect_args["command_timeout"] = float(settings.database_command_timeout_seconds)

if not _sqlite and settings.database_ssl:
    _ctx = ssl.create_default_context()
    _connect_args["ssl"] = _ctx
_connect_args.setdefault("timeout", float(settings.database_connect_timeout_seconds))


def is_sqlite_runtime() -> bool:
    """True when the API uses local SQLite (HEXA_USE_SQLITE or sqlite DATABASE_URL)."""
    return _sqlite


def _sqlalchemy_echo() -> bool:
    """SQL echo doubles log volume; keep off in cloud unless explicitly enabled."""
    return settings.app_env == "development"


_engine_kwargs: dict = {
    "echo": _sqlalchemy_echo(),
    "connect_args": _connect_args,
}
if not _sqlite:
    # QueuePool (default for create_async_engine + asyncpg): reuse client connections across requests.
    # statement_cache_size=0 mitigates PgBouncer transaction pooling + async prepared statements.
    _engine_kwargs.update(
        pool_pre_ping=True,
        pool_recycle=max(90, settings.database_pool_recycle_seconds),
        pool_timeout=settings.database_pool_timeout_seconds,
        pool_size=settings.database_pool_size,
        max_overflow=settings.database_pool_max_overflow,
    )

    # Operational caveat: bounded pool_size + recycle + statement_cache_size=0 + pre_ping
    # mitigates transaction-pooler + async prepared statement quirks; Session pooler is an infra fallback.

engine = create_async_engine(_effective_url, **_engine_kwargs)
if not _sqlite:
    logger.info(
        "Database engine: pool_size=%s max_overflow=%s pool_timeout=%s recycle=%ss "
        "pre_ping=%r statement_cache=%r command_timeout=%r connect_timeout=%r",
        settings.database_pool_size,
        settings.database_pool_max_overflow,
        settings.database_pool_timeout_seconds,
        settings.database_pool_recycle_seconds,
        _engine_kwargs.get("pool_pre_ping"),
        _connect_args.get("statement_cache_size"),
        _connect_args.get("command_timeout"),
        _connect_args.get("timeout"),
    )


def _slow_sql_logging_enabled(threshold_ms: int) -> bool:
    """Avoid slow-SQL log spam locally unless DATABASE_SLOW_SQL_LOG=1/true."""
    if threshold_ms <= 0:
        return False
    if settings.app_env in ("development", "test"):
        return os.getenv("DATABASE_SLOW_SQL_LOG", "").strip().lower() in ("1", "true", "yes")
    return True


def _attach_slow_sql_listener(eng: AsyncEngine, threshold_ms: int) -> None:
    if threshold_ms <= 0 or is_sqlite_runtime():
        return
    sync = eng.sync_engine

    @event.listens_for(sync, "before_cursor_execute")
    def _before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
        setattr(context, "_hexa_stmt_start", time.perf_counter())

    @event.listens_for(sync, "after_cursor_execute")
    def _after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
        started = getattr(context, "_hexa_stmt_start", None)
        if started is None:
            return
        elapsed_ms = (time.perf_counter() - started) * 1000.0
        if elapsed_ms >= threshold_ms:
            preview = (statement or "").strip().replace("\n", " ")[:480]
            logger.warning("slow SQL %.0fms | %s", elapsed_ms, preview)


def _attach_engine_error_logging(eng: AsyncEngine) -> None:
    if is_sqlite_runtime():
        return
    sync = eng.sync_engine

    @event.listens_for(sync, "handle_error")
    def _on_handle_error(exception_context):  # type: ignore[no-untyped-def]
        raw = getattr(exception_context, "original_exception", None) or getattr(
            exception_context, "chained_exception", None
        )
        if raw is None:
            return
        msg = getattr(exception_context, "is_disconnect", None)
        logger.warning(
            "db operational failure | disconnect_hint=%s | %s | %s",
            msg,
            type(raw).__name__,
            raw,
        )


if _slow_sql_logging_enabled(settings.database_slow_query_log_ms):
    _attach_slow_sql_listener(engine, settings.database_slow_query_log_ms)

if not _sqlite:
    _attach_engine_error_logging(engine)

async_session_factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_factory() as session:
        yield session
