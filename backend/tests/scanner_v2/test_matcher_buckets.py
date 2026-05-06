"""Matcher tests covering ``docs/AI_SCANNER_TEST_CASES.md`` §B (T-B.01..T-B.10).

Uses a SQLite test DB seeded with suppliers / brokers / catalog items, runs
``match_one`` and asserts the right confidence bucket per the rules in
``docs/AI_SCANNER_MATCHING_ENGINE.md``.
"""

from __future__ import annotations

import uuid

import pytest

from app.database import async_session_factory
from app.models import Business, CatalogItem, ItemCategory, User
from app.models.ai_engine import CatalogAlias
from app.models.contacts import Broker, Supplier
from app.services.scanner_v2 import matcher
from app.services.scanner_v2.matcher import classify


@pytest.fixture(scope="module")
def event_loop():
    """Compatibility shim for pytest on Python 3.13.

    Some environments expect an event_loop fixture even for sync tests.
    We do not rely on it; async work uses `asyncio.run(...)` explicitly.
    """
    yield None


@pytest.fixture(scope="module")
def seeded():
    """Seed a workspace with a few suppliers, brokers, items, and one alias."""

    async def _seed():
        async with async_session_factory() as db:
            uniq = uuid.uuid4().hex[:8]
            user = User(
                id=uuid.uuid4(),
                email=f"matcher{uniq}@test.local",
                username=f"matcher{uniq}",
                password_hash=None,
                name="Test",
            )
            biz = Business(
                id=uuid.uuid4(),
                name=f"Biz {uniq}",
                phone="9999999999",
            )
            db.add_all([user, biz])
            await db.flush()

            sup1 = Supplier(id=uuid.uuid4(), business_id=biz.id, name="SURAJ TRADERS", phone="1")
            sup2 = Supplier(id=uuid.uuid4(), business_id=biz.id, name="ANNAPURNA AGENCIES", phone="2")
            br1 = Broker(id=uuid.uuid4(), business_id=biz.id, name="RIYAS")
            br2 = Broker(id=uuid.uuid4(), business_id=biz.id, name="SALEEM")

            cat = ItemCategory(id=uuid.uuid4(), business_id=biz.id, name="Rice")
            db.add(cat)
            await db.flush()

            it_barli = CatalogItem(
                id=uuid.uuid4(),
                business_id=biz.id,
                category_id=cat.id,
                name="BARLI RICE 50KG",
                default_unit="BAG",
            )
            it_sugar = CatalogItem(
                id=uuid.uuid4(),
                business_id=biz.id,
                category_id=cat.id,
                name="SUGAR 50KG",
                default_unit="BAG",
            )
            it_sona = CatalogItem(
                id=uuid.uuid4(),
                business_id=biz.id,
                category_id=cat.id,
                name="SONA MASURI 25KG",
                default_unit="BAG",
            )

            db.add_all([sup1, sup2, br1, br2, it_barli, it_sugar, it_sona])

            # Seed one alias: "burly" → BARLI RICE 50KG (T-B.10)
            db.add(
                CatalogAlias(
                    id=uuid.uuid4(),
                    business_id=biz.id,
                    alias_type="item",
                    ref_id=it_barli.id,
                    name="burly",
                    normalized_name="burly",
                )
            )
            await db.commit()
            return {
                "biz_id": biz.id,
                "sup1": sup1.id,
                "sup2": sup2.id,
                "br1": br1.id,
                "br2": br2.id,
                "it_barli": it_barli.id,
                "it_sugar": it_sugar.id,
                "it_sona": it_sona.id,
            }

    import asyncio

    return asyncio.run(_seed())


# --------------------------------------------------------------------------- #
# classify                                                                    #
# --------------------------------------------------------------------------- #

def test_classify_buckets():
    assert classify(100) == "auto"
    assert classify(92) == "auto"
    assert classify(91) == "needs_confirmation"
    assert classify(70) == "needs_confirmation"
    assert classify(69) == "unresolved"
    assert classify(0) == "unresolved"


# --------------------------------------------------------------------------- #
# match_one                                                                   #
# --------------------------------------------------------------------------- #

def test_t_b_01_suraj_auto_match(seeded):
    import asyncio

    async def _run_test():
        async with async_session_factory() as db:
            m = await matcher.match_one(db, seeded["biz_id"], "suraj", "supplier")
        return m

    m = asyncio.run(_run_test())
    assert m.match_state == "auto"
    assert m.matched_id == seeded["sup1"]
    assert m.matched_name == "SURAJ TRADERS"
    assert m.confidence >= 0.92


def test_t_b_05_riyas_broker_auto(seeded):
    import asyncio

    async def _run_test():
        async with async_session_factory() as db:
            return await matcher.match_one(db, seeded["biz_id"], "riyas", "broker")

    m = asyncio.run(_run_test())
    assert m.match_state == "auto"
    assert m.matched_id == seeded["br1"]


def test_t_b_06_kkkk_unresolved(seeded):
    import asyncio

    async def _run_test():
        async with async_session_factory() as db:
            return await matcher.match_one(db, seeded["biz_id"], "kkkk", "broker")

    m = asyncio.run(_run_test())
    assert m.match_state == "unresolved"
    assert m.matched_id is None


def test_t_b_03_barly_via_alias_or_fuzzy(seeded):
    import asyncio

    async def _run_test():
        async with async_session_factory() as db:
            return await matcher.match_one(db, seeded["biz_id"], "barly", "item")

    m = asyncio.run(_run_test())
    # barly → BARLI RICE 50KG; either auto via fuzzy/manglish or fuzzy confirm
    assert m.match_state in {"auto", "needs_confirmation"}
    assert m.matched_name == "BARLI RICE 50KG" or any(
        c.name == "BARLI RICE 50KG" for c in m.candidates
    )


def test_t_b_10_alias_burly_auto(seeded):
    """Alias 'burly' explicitly maps to BARLI RICE 50KG → auto."""
    import asyncio

    async def _run_test():
        async with async_session_factory() as db:
            return await matcher.match_one(db, seeded["biz_id"], "burly", "item")

    m = asyncio.run(_run_test())
    assert m.match_state == "auto"
    assert m.matched_name == "BARLI RICE 50KG"
    assert m.confidence == 1.0


def test_t_b_08_random_gibberish_unresolved(seeded):
    import asyncio

    async def _run_test():
        async with async_session_factory() as db:
            return await matcher.match_one(db, seeded["biz_id"], "xyzqwerty", "item")

    m = asyncio.run(_run_test())
    assert m.match_state == "unresolved"


def test_t_b_09_soona_masoori_matches_sona(seeded):
    """Manglish: 'soona masoori' → SONA MASURI 25KG."""
    import asyncio

    async def _run_test():
        async with async_session_factory() as db:
            return await matcher.match_one(db, seeded["biz_id"], "soona masoori", "item")

    m = asyncio.run(_run_test())
    assert m.match_state in {"auto", "needs_confirmation"}
    names = {c.name for c in m.candidates}
    assert "SONA MASURI 25KG" in names


def test_workspace_isolation(seeded):
    """A different business_id sees nothing."""
    import asyncio

    async def _run_test():
        other_biz = uuid.uuid4()
        async with async_session_factory() as db:
            return await matcher.match_one(db, other_biz, "suraj", "supplier")

    m = asyncio.run(_run_test())
    assert m.match_state == "unresolved"
    assert m.matched_id is None


def test_empty_query_unresolved(seeded):
    import asyncio

    async def _run_test():
        async with async_session_factory() as db:
            return await matcher.match_one(db, seeded["biz_id"], "   ", "supplier")

    m = asyncio.run(_run_test())
    assert m.match_state == "unresolved"


def test_top_candidates_for_pure_helper():
    rows = [
        (uuid.uuid4(), "SUGAR 50KG"),
        (uuid.uuid4(), "BARLI RICE 50KG"),
        (uuid.uuid4(), "WHEAT 30KG"),
    ]
    cands = matcher.top_candidates_for("suger", rows)
    assert cands
    assert cands[0].name == "SUGAR 50KG"
