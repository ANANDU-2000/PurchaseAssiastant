"""Strict decimal precision helpers for financial purchase math."""

from __future__ import annotations

from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from typing import Any


ZERO = Decimal("0")
ONE = Decimal("1")
HUNDRED = Decimal("100")

MONEY_Q = Decimal("0.01")
RATE_Q = Decimal("0.01")
QTY_Q = Decimal("0.001")
WEIGHT_Q = Decimal("0.001")
PERCENT_Q = Decimal("0.01")
TOTAL_Q = Decimal("0.01")
TOTAL_WEIGHT_Q = Decimal("0.001")


def dec(value: Any, *, default: Decimal | None = ZERO) -> Decimal:
    if value is None:
        if default is None:
            raise ValueError("number is required")
        return default
    if isinstance(value, Decimal):
        out = value
    elif isinstance(value, int):
        out = Decimal(value)
    elif isinstance(value, float):
        # JSON numbers may arrive as float from external callers. Use str(value)
        # so Decimal never receives a binary float directly.
        out = Decimal(str(value))
    elif isinstance(value, str):
        raw = value.strip()
        if raw == "":
            if default is None:
                raise ValueError("number is required")
            return default
        try:
            out = Decimal(raw)
        except InvalidOperation as exc:
            raise ValueError("invalid number") from exc
    else:
        try:
            out = Decimal(str(value))
        except InvalidOperation as exc:
            raise ValueError("invalid number") from exc
    if not out.is_finite():
        raise ValueError("number must be finite")
    return out


def q(value: Any, quantum: Decimal) -> Decimal:
    return dec(value).quantize(quantum, rounding=ROUND_HALF_UP)


def money(value: Any) -> Decimal:
    return q(value, MONEY_Q)


def rate(value: Any) -> Decimal:
    return q(value, RATE_Q)


def qty(value: Any) -> Decimal:
    return q(value, QTY_Q)


def weight(value: Any) -> Decimal:
    return q(value, WEIGHT_Q)


def percent(value: Any) -> Decimal:
    return q(value, PERCENT_Q)


def total(value: Any) -> Decimal:
    return q(value, TOTAL_Q)


def total_weight(value: Any) -> Decimal:
    return q(value, TOTAL_WEIGHT_Q)


def clamp_percent(value: Decimal, upper: Decimal = HUNDRED) -> Decimal:
    if value < ZERO:
        return ZERO
    if value > upper:
        return upper
    return value


def decimal_json(value: Decimal | None, places: int = 2) -> str | None:
    if value is None:
        return None
    return f"{value:.{places}f}"
