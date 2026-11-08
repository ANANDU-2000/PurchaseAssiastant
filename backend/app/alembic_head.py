"""Alembic head derived from the migration files (no hardcoded revision, no DB needed)."""

from functools import lru_cache
from pathlib import Path

from alembic.script import ScriptDirectory

_ALEMBIC_DIR = Path(__file__).resolve().parent.parent / "alembic"


@lru_cache(maxsize=1)
def _script() -> ScriptDirectory:
    return ScriptDirectory(str(_ALEMBIC_DIR))


def latest_head() -> str | None:
    """Single head revision, or None if missing/ambiguous (multiple heads)."""
    try:
        heads = _script().get_heads()
    except Exception:  # noqa: BLE001
        return None
    return heads[0] if len(heads) == 1 else None


def behind_by(current: str | None) -> int | None:
    """Migrations the DB still needs; None when the version or head is unknown."""
    head = latest_head()
    if not head or not current:
        return None
    try:
        if _script().get_revision(current) is None:
            return None
        return len(list(_script().iterate_revisions(head, current)))
    except Exception:  # noqa: BLE001
        return None
