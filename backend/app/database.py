import logging
import os
import ssl
import time
from collections.abc import AsyncGenerator


# Use OS trust store (Ubuntu on Render) + certifi; fixes SSLCertVerificationError to Supabase/ AWS
# when certifi alone sees "self-signed certificate in the certificate chain".
try:
    import truststore

    truststore.inject_into_ssl()
except ImportError:
    pass

from sqlalchemy import event
from sqlalchemy.engine.url import make_url
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


# Bypass .env pooler/postgres when Supabase is unreachable (e.g. SSL hang). Set HEXA_USE_SQLITE=1.
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
    _pooler = ""
    _effective_url = _sqlite_url
    logger.info("HEXA_USE_SQLITE: using local SQLite (%s)", _sqlite_url)
else:
    _sqlite = settings.database_url.startswith("sqlite")
    _pooler = (settings.database_pooler_url or "").strip()
    if _pooler:
        _pl = _pooler.lower()
        if "[your-password]" in _pl or "your-password" in _pl:
            logger.error(
                "DATABASE_POOLER_URL still contains the Supabase placeholder [YOUR-PASSWORD]. "
                "Set DATABASE_POOLER_PASSWORD to your real DB password and use a URI with no password in the string "
                "(postgresql+asyncpg://postgres.PROJECT_REF@HOST:6543/postgres)."
            )
        if "postgres.[" in _pooler or "postgres:[" in _pooler:
            logger.error(
                "Invalid URI: do not wrap the password in square brackets. "
                "Use postgres.PROJECT_REF@host (see DATABASE_POOLER_PASSWORD)."
            )
    _effective_url = _pooler if _pooler else settings.database_url
    if not _sqlite:
        _effective_url = _normalize_postgres_async_url(_effective_url)

    # Optional: password only in DATABASE_POOLER_PASSWORD — keeps @/#/ etc. out of the URI string.
    if _pooler and settings.database_pooler_password and settings.database_pooler_password.strip():
        try:
            _u = make_url(_effective_url)
            _effective_url = _u.set(
                password=settings.database_pooler_password.strip(),
            ).render_as_string(hide_password=False)
            logger.info("Applied DATABASE_POOLER_PASSWORD (URI should omit password; userinfo user@host only).")
        except Exception as e:  # noqa: BLE001
            logger.warning("Could not merge DATABASE_POOLER_PASSWORD into pooler URL: %s", e)

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
# asyncpg caches prepared statements per connection. PgBouncer (transaction mode) and
# Supabase pooler reuse connections across clients — stale stmt names →
# InvalidSQLStatementNameError. Disabling the cache is the standard fix.
if not _sqlite:
    _connect_args["statement_cache_size"] = 0

if not _sqlite and settings.database_command_timeout_seconds and settings.database_command_timeout_seconds > 0:
    _connect_args["command_timeout"] = float(settings.database_command_timeout_seconds)

if not _sqlite and (
    "supabase.co" in _effective_url or "pooler.supabase.com" in _effective_url
):
    if settings.database_ssl_skip_verify:
        logger.warning(
            "DATABASE_SSL_SKIP_VERIFY=true: using TLS to Postgres without verifying the server certificate. "
            "Traffic is still encrypted; only chain validation is skipped (workaround for some Render+Supabase SSL issues)."
        )
        _ctx = ssl.create_default_context()
        _ctx.check_hostname = False
        _ctx.verify_mode = ssl.CERT_NONE
        _connect_args["ssl"] = _ctx
    elif settings.database_ssl_insecure:
        _ctx = ssl.create_default_context()
        _ctx.check_hostname = False
        _ctx.verify_mode = ssl.CERT_NONE
        _connect_args["ssl"] = _ctx
    else:
        try:
            import certifi

            _ctx = ssl.create_default_context(purpose=ssl.Purpose.SERVER_AUTH)
            _ctx.load_verify_locations(cafile=certifi.where())
            if hasattr(ssl, "VERIFY_X509_PARTIAL_CHAIN"):
                _ctx.verify_flags |= ssl.VERIFY_X509_PARTIAL_CHAIN  # type: ignore[attr-defined]
            _connect_args["ssl"] = _ctx
        except Exception:  # noqa: BLE001
            _connect_args["ssl"] = True
_connect_args.setdefault("timeout", float(settings.database_connect_timeout_seconds))

try:
    _diag = make_url(_effective_url)
    if not _sqlite and _diag.host and "@" in _diag.host:
        logger.error(
            "Database URL is misparsed (hostname contains '@'). Put the password in "
            "DATABASE_POOLER_PASSWORD and set DATABASE_POOLER_URL to "
            "postgresql+asyncpg://USER@HOST:PORT/DB with no password in the string."
        )
    elif not _sqlite and _pooler and _diag.host:
        logger.info("Pooler DB host=%s port=%s database=%s", _diag.host, _diag.port, _diag.database)
except Exception:  # noqa: BLE001
    pass


def is_sqlite_runtime() -> bool:
    """True when the API uses local SQLite (HEXA_USE_SQLITE or sqlite DATABASE_URL)."""
    return _sqlite


if not _sqlite:
    try:
        _eu = make_url(_effective_url)
        _h = (_eu.host or "").lower()
        if _h.startswith("db.") and "supabase.co" in _h and "pooler" not in _h:
            logger.error(
                "Effective DB host is Supabase DIRECT (db.*.supabase.co). From Render this often fails with "
                "OSError: [Errno 101] Network is unreachable (IPv4 vs IPv6). Fix: Supabase → Connect → "
                "Transaction pooler → set DATABASE_POOLER_URL to "
                "postgresql+asyncpg://postgres.PROJECT_REF@aws-0-REGION.pooler.supabase.com:6543/postgres "
                "(no password in URL) and DATABASE_POOLER_PASSWORD; leave DATABASE_URL as fallback or any value."
            )
    except Exception:  # noqa: BLE001
        pass

_engine_kwargs: dict = {
    "echo": settings.app_env == "development",
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
