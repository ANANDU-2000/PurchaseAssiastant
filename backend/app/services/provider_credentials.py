"""Encrypted provider credentials (owner-editable) with env fallback."""

from __future__ import annotations

import base64
import hashlib
import logging
import uuid
from datetime import datetime, timezone

from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.owner_ops import ProviderCredential

logger = logging.getLogger(__name__)

ALLOWED_TYPES = frozenset(
    {
        "openrouter_key",
        "gemini_key",
        "groq_key",
        "openai_key",
        "whatsapp_api_key",
        "whatsapp_staff_number",
    }
)


def _fernet() -> Fernet:
    settings = get_settings()
    raw = (getattr(settings, "credential_encryption_key", None) or "").strip()
    material = raw.encode("utf-8") if raw else settings.jwt_secret.encode("utf-8")
    key = base64.urlsafe_b64encode(hashlib.sha256(material).digest())
    return Fernet(key)


def encrypt_secret(value: str) -> str:
    return _fernet().encrypt(value.encode("utf-8")).decode("ascii")


def decrypt_secret(token: str) -> str:
    return _fernet().decrypt(token.encode("ascii")).decode("utf-8")


def mask_last4(value: str) -> str:
    v = (value or "").strip()
    if len(v) <= 4:
        return v
    return v[-4:]


async def list_credentials(
    db: AsyncSession, business_id: uuid.UUID
) -> list[dict]:
    rows = (
        await db.execute(
            select(ProviderCredential).where(
                ProviderCredential.business_id == business_id
            )
        )
    ).scalars().all()
    return [
        {
            "credential_type": r.credential_type,
            "last_4_chars": r.last_4_chars,
            "updated_at": r.updated_at.isoformat() if r.updated_at else None,
            "updated_by": str(r.updated_by) if r.updated_by else None,
            "configured": True,
        }
        for r in rows
    ]


async def upsert_credential(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    credential_type: str,
    value: str,
    updated_by: uuid.UUID | None,
) -> ProviderCredential:
    if credential_type not in ALLOWED_TYPES:
        raise ValueError(f"unsupported credential_type: {credential_type}")
    value = value.strip()
    if not value:
        raise ValueError("value required")
    row = (
        await db.execute(
            select(ProviderCredential).where(
                ProviderCredential.business_id == business_id,
                ProviderCredential.credential_type == credential_type,
            )
        )
    ).scalar_one_or_none()
    if row is None:
        row = ProviderCredential(
            business_id=business_id,
            credential_type=credential_type,
            encrypted_value=encrypt_secret(value),
            last_4_chars=mask_last4(value),
            updated_by=updated_by,
        )
        db.add(row)
    else:
        row.encrypted_value = encrypt_secret(value)
        row.last_4_chars = mask_last4(value)
        row.updated_by = updated_by
        row.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(row)
    return row


async def resolve_key(
    db: AsyncSession | None,
    business_id: uuid.UUID | None,
    credential_type: str,
    env_fallback: str | None,
) -> str | None:
    """DB value first (if session provided), else env."""
    if db is not None and business_id is not None:
        try:
            row = (
                await db.execute(
                    select(ProviderCredential).where(
                        ProviderCredential.business_id == business_id,
                        ProviderCredential.credential_type == credential_type,
                    )
                )
            ).scalar_one_or_none()
            if row is not None:
                return decrypt_secret(row.encrypted_value)
        except InvalidToken:
            logger.warning("credential decrypt failed for %s", credential_type)
        except Exception as e:  # noqa: BLE001
            logger.warning("credential resolve failed: %s", e)
    fb = (env_fallback or "").strip()
    return fb or None
