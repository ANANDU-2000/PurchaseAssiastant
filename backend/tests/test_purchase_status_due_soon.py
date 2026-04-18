"""Unit tests for purchase_status.compute_status (due_soon window)."""

from datetime import date, datetime, timezone

from app.services.purchase_status import compute_status


def _dt(d: date) -> datetime:
    return datetime(d.year, d.month, d.day, 12, 0, 0, tzinfo=timezone.utc)


def test_due_soon_when_due_in_two_days_unpaid():
    today = date(2026, 4, 10)
    due = date(2026, 4, 12)
    assert (
        compute_status(
            stored_status="confirmed",
            total_amount=100,
            paid_amount=0,
            due_date=due,
            now=_dt(today),
        )
        == "due_soon"
    )


def test_due_soon_when_due_today():
    today = date(2026, 4, 10)
    assert (
        compute_status(
            stored_status="confirmed",
            total_amount=50,
            paid_amount=0,
            due_date=today,
            now=_dt(today),
        )
        == "due_soon"
    )


def test_due_soon_partially_paid_still_due_soon():
    today = date(2026, 4, 10)
    due = date(2026, 4, 11)
    assert (
        compute_status(
            stored_status="confirmed",
            total_amount=100,
            paid_amount=40,
            due_date=due,
            now=_dt(today),
        )
        == "due_soon"
    )


def test_not_due_soon_when_due_in_four_days():
    today = date(2026, 4, 10)
    due = date(2026, 4, 14)
    assert (
        compute_status(
            stored_status="confirmed",
            total_amount=80,
            paid_amount=0,
            due_date=due,
            now=_dt(today),
        )
        == "confirmed"
    )


def test_overdue_beats_due_soon():
    today = date(2026, 4, 10)
    due = date(2026, 4, 1)
    assert (
        compute_status(
            stored_status="confirmed",
            total_amount=80,
            paid_amount=0,
            due_date=due,
            now=_dt(today),
        )
        == "overdue"
    )


def test_paid_skips_due_date_rules():
    today = date(2026, 4, 10)
    due = date(2026, 4, 10)
    assert (
        compute_status(
            stored_status="confirmed",
            total_amount=100,
            paid_amount=100,
            due_date=due,
            now=_dt(today),
        )
        == "paid"
    )
