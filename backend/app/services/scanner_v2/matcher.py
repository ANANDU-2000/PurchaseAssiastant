"""Supplier / broker / catalog item resolution with confidence buckets.

Implements the matching pipeline from `docs/AI_SCANNER_MATCHING_ENGINE.md`:
``alias hit → normalize → manglish layer → rapidfuzz blend → bucket``.

Pure-ish: it takes an ``AsyncSession`` for DB lookups but never writes.
Workspace-scoped (every query filters by ``business_id``).

Public API:

- ``Match`` is the wire type from ``scanner_v2.types``.
- ``MatchType`` literal: ``"supplier" | "broker" | "item"``.
- ``async match_one(db, business_id, raw_text, type, *, category_id=None) -> Match``
- ``classify(score) -> MatchState`` (pure helper).
"""

from __future__ import annotations

import re
import unicodedata
import uuid
from typing import Iterable, Literal, Sequence

from rapidfuzz import fuzz, process
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogItem
from app.models.ai_engine import CatalogAlias
from app.models.contacts import Broker, Supplier
from app.services.scanner_v2.types import Candidate, Match, MatchState

MatchType = Literal["supplier", "broker", "item"]

AUTO_THRESHOLD = 92
CONFIRM_THRESHOLD = 70
SHORT_QUERY_PARTIAL_MIN = 95  # for queries < 4 chars
TOP_K_CANDIDATES = 3
LARGE_CATALOG_PREFILTER_AT = 500

# --------------------------------------------------------------------------- #
# Manglish normalization (Manglish = Malayalam written in Latin letters)      #
# --------------------------------------------------------------------------- #

# Trader-vocabulary aliases. Order matters: longer phrases first.
_MANGLISH_RULES: tuple[tuple[str, str], ...] = (
    ("pacha ari", "raw rice"),
    ("cheru payar", "green gram"),
    ("cheru pa-yar", "green gram"),
    ("soona masuri", "sona masuri"),
    ("sona masuri", "sona masuri"),
    ("ari", "rice"),
    ("pacha", "raw"),
    ("ponni", "ponni"),
    ("matta", "matta"),
    ("thuvarra", "tur"),
    ("thuvara", "tur"),
    ("uzhunnu", "urad"),
    ("kachiya", "boiled"),
    ("shakkara", "sugar"),
    ("suger", "sugar"),
    ("sugar", "sugar"),
    ("barly", "barley"),
    ("barli", "barley"),
)


def manglish_normalize(s: str) -> str:
    """Apply trader-vocabulary substitutions to a normalised string."""
    out = s
    for src, dst in _MANGLISH_RULES:
        if src in out:
            out = out.replace(src, dst)
    return out


# --------------------------------------------------------------------------- #
# normalize / classify                                                        #
# --------------------------------------------------------------------------- #


_ZW_RE = re.compile(r"[\u200b-\u200f\ufeff]")
_NON_WORD_RE = re.compile(r"[^\w\u0d00-\u0d7f\s]")
_WS_RE = re.compile(r"\s+")


def normalize(s: str) -> str:
    """Lowercase, NFKC, strip zero-widths and punctuation, collapse whitespace.

    Keeps Malayalam Unicode block (U+0D00..U+0D7F) untouched.
    """
    if not s:
        return ""
    out = unicodedata.normalize("NFKC", s).lower().strip()
    out = _ZW_RE.sub("", out)
    out = _NON_WORD_RE.sub(" ", out)
    out = _WS_RE.sub(" ", out).strip()
    return out


def classify(score: int) -> MatchState:
    """Score 0..100 → match_state bucket."""
    if score >= AUTO_THRESHOLD:
        return "auto"
    if score >= CONFIRM_THRESHOLD:
        return "needs_confirmation"
    return "unresolved"


def _blended_score(query: str, candidate: str) -> int:
    """Max of token_sort, partial, weighted ratio. Returns 0..100."""
    if not query or not candidate:
        return 0
    return int(
        max(
            fuzz.token_sort_ratio(query, candidate),
            fuzz.partial_ratio(query, candidate),
            fuzz.WRatio(query, candidate),
        )
    )


# --------------------------------------------------------------------------- #
# DB row fetch                                                                #
# --------------------------------------------------------------------------- #


async def _fetch_rows(
    db: AsyncSession,
    business_id: uuid.UUID,
    match_type: MatchType,
    *,
    first_token: str | None = None,
) -> list[tuple[uuid.UUID, str]]:
    """Return [(id, name), ...] filtered by business_id; optional ILIKE prefilter."""
    if match_type == "supplier":
        stmt = select(Supplier.id, Supplier.name).where(Supplier.business_id == business_id)
    elif match_type == "broker":
        stmt = select(Broker.id, Broker.name).where(Broker.business_id == business_id)
    else:
        stmt = select(CatalogItem.id, CatalogItem.name).where(CatalogItem.business_id == business_id)
        # large-catalog short-list optimisation
        if first_token:
            stmt = stmt.where(CatalogItem.name.ilike(f"%{first_token}%"))
    rows = (await db.execute(stmt)).all()
    return [(r[0], r[1]) for r in rows if r[1]]


async def _alias_hit(
    db: AsyncSession,
    business_id: uuid.UUID,
    match_type: MatchType,
    normalized: str,
) -> uuid.UUID | None:
    """Workspace-scoped exact alias match by normalized name. Most-recent wins."""
    if not normalized:
        return None
    alias_type = "item" if match_type == "item" else match_type  # supplier|broker|item
    stmt = (
        select(CatalogAlias.ref_id)
        .where(
            CatalogAlias.business_id == business_id,
            CatalogAlias.alias_type == alias_type,
            CatalogAlias.normalized_name == normalized,
        )
        .order_by(CatalogAlias.created_at.desc())
        .limit(1)
    )
    r = await db.execute(stmt)
    row = r.first()
    return row[0] if row else None


# --------------------------------------------------------------------------- #
# Public: match_one                                                           #
# --------------------------------------------------------------------------- #


async def match_one(
    db: AsyncSession,
    business_id: uuid.UUID,
    raw_text: str,
    match_type: MatchType,
) -> Match:
    """Resolve one entity. Returns a fully populated ``Match``.

    The function never raises for empty/whitespace input; it returns a Match
    with ``match_state='unresolved'`` so the caller can render the right UI.
    """

    raw = (raw_text or "").strip()
    if not raw:
        return Match(raw_text="", match_state="unresolved")

    norm = normalize(raw)
    norm_mng = manglish_normalize(norm)

    # 1) Alias precedence (exact match on normalized OR manglish-normalized text).
    for q in (norm, norm_mng):
        ref = await _alias_hit(db, business_id, match_type, q)
        if ref is not None:
            # Resolve the alias to a current name.
            name = await _resolve_id_to_name(db, match_type, ref)
            if name:
                return Match(
                    raw_text=raw,
                    matched_id=ref,
                    matched_name=name,
                    confidence=1.0,
                    match_state="auto",
                    candidates=[Candidate(id=ref, name=name, confidence=1.0)],
                )

    # 2) Fuzzy search.
    first_token = norm.split(" ")[0] if " " in norm else norm
    rows = await _fetch_rows(db, business_id, match_type, first_token=first_token)

    # If catalog/supplier list is large and prefilter excluded everything,
    # fall back to full list.
    if not rows and match_type == "item":
        rows = await _fetch_rows(db, business_id, match_type, first_token=None)

    if not rows:
        return Match(raw_text=raw, match_state="unresolved")

    # Score against both normalized and manglish-normalized variants of the query;
    # take the max per candidate.
    candidates_with_scores: list[tuple[uuid.UUID, str, int]] = []
    norm_candidates = [(uid, normalize(name)) for (uid, name) in rows if name]
    for (uid, name), (uid2, n) in zip(rows, norm_candidates):
        assert uid == uid2
        s = max(_blended_score(norm, n), _blended_score(norm_mng, n))
        # Short query guard: require partial_ratio≥95 to count.
        if len(norm) < 4:
            partial = max(
                fuzz.partial_ratio(norm, n),
                fuzz.partial_ratio(norm_mng, n),
            )
            if partial < SHORT_QUERY_PARTIAL_MIN:
                s = min(s, CONFIRM_THRESHOLD - 1)  # demote
        candidates_with_scores.append((uid, name, s))

    candidates_with_scores.sort(key=lambda t: (-t[2], t[1].lower()))
    top = candidates_with_scores[:TOP_K_CANDIDATES]
    if not top:
        return Match(raw_text=raw, match_state="unresolved")

    best_id, best_name, best_score = top[0]
    state = classify(best_score)
    confidence = best_score / 100.0
    matched_id = best_id if state in {"auto", "needs_confirmation"} else None
    matched_name = best_name if state in {"auto", "needs_confirmation"} else None

    return Match(
        raw_text=raw,
        matched_id=matched_id if state == "auto" else None,
        matched_name=matched_name if state == "auto" else None,
        confidence=confidence,
        match_state=state,
        candidates=[
            Candidate(id=uid, name=name, confidence=score / 100.0)
            for (uid, name, score) in top
        ],
    )


async def _resolve_id_to_name(
    db: AsyncSession, match_type: MatchType, ref_id: uuid.UUID
) -> str | None:
    if match_type == "supplier":
        r = await db.execute(select(Supplier.name).where(Supplier.id == ref_id))
    elif match_type == "broker":
        r = await db.execute(select(Broker.name).where(Broker.id == ref_id))
    else:
        r = await db.execute(select(CatalogItem.name).where(CatalogItem.id == ref_id))
    row = r.first()
    return row[0] if row else None


# --------------------------------------------------------------------------- #
# Top-3 helper for offline-style picker UIs                                   #
# --------------------------------------------------------------------------- #


def top_candidates_for(
    query: str, rows: Sequence[tuple[uuid.UUID, str]], limit: int = TOP_K_CANDIDATES
) -> list[Candidate]:
    """Pure helper: rank rows by blended score against the query."""
    if not query or not rows:
        return []
    q = normalize(query)
    qm = manglish_normalize(q)
    scored: list[tuple[uuid.UUID, str, int]] = []
    for uid, name in rows:
        n = normalize(name)
        s = max(_blended_score(q, n), _blended_score(qm, n))
        scored.append((uid, name, s))
    scored.sort(key=lambda t: (-t[2], t[1].lower()))
    return [
        Candidate(id=uid, name=name, confidence=score / 100.0)
        for uid, name, score in scored[:limit]
        if score >= 50  # below 50 is meaningless even as a hint
    ]


__all__ = [
    "AUTO_THRESHOLD",
    "CONFIRM_THRESHOLD",
    "Match",
    "MatchType",
    "classify",
    "manglish_normalize",
    "match_one",
    "normalize",
    "top_candidates_for",
]
