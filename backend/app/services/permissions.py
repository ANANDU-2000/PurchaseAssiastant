"""Role templates and per-membership permission overrides."""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Membership

PERMISSION_KEYS = (
    "stock_edit",
    "purchase_create",
    "purchase_edit",
    "barcode_print",
    "reports_access",
    "export_access",
    "user_manage",
    "delete_access",
    "analytics_access",
)

_OWNER_ADMIN = {k: True for k in PERMISSION_KEYS}

ROLE_DEFAULTS: dict[str, dict[str, bool]] = {
    "owner": dict(_OWNER_ADMIN),
    "admin": dict(_OWNER_ADMIN),
    "manager": {
        "stock_edit": True,
        "purchase_create": True,
        "purchase_edit": True,
        "reports_access": True,
        "barcode_print": True,
        "export_access": True,
        "user_manage": False,
        "delete_access": False,
        "analytics_access": True,
    },
    "staff": {
        "stock_edit": True,
        "purchase_create": True,
        "purchase_edit": False,
        "reports_access": False,
        "barcode_print": True,
        "export_access": False,
        "user_manage": False,
        "delete_access": False,
        "analytics_access": False,
    },
}


def effective_permissions(role: str, overrides: dict[str, Any] | None) -> dict[str, bool]:
    base = dict(ROLE_DEFAULTS.get(role, ROLE_DEFAULTS["staff"]))
    if overrides:
        merged = dict(overrides)
        if "delete_items" in merged and "delete_access" not in merged:
            merged["delete_access"] = merged["delete_items"]
        for k in PERMISSION_KEYS:
            if k in merged and isinstance(merged[k], bool):
                base[k] = merged[k]
    return base


async def membership_permissions(
    membership: Membership,
) -> dict[str, bool]:
    raw = getattr(membership, "permissions_json", None) or {}
    return effective_permissions(membership.role, raw if isinstance(raw, dict) else None)


def require_permission_key(key: str, perms: dict[str, bool]) -> None:
    from fastapi import HTTPException, status

    if not perms.get(key, False):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail=f"Permission denied: {key}",
        )


def actor_can_manage_target(actor_role: str, target_role: str) -> bool:
    """Admin cannot modify owner memberships."""
    if target_role == "owner" and actor_role == "admin":
        return False
    return True
