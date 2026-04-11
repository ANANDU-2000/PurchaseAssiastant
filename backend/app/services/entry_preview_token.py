"""Short-lived tokens proving the client ran preview (confirm=false) before confirm=true."""

from __future__ import annotations

import hashlib
import json
import time
import uuid
from threading import Lock

from app.schemas.entries import EntryCreateRequest

_LOCK = Lock()
# token -> (payload_sha256, expiry_monotonic, user_id, business_id)
_STORE: dict[str, tuple[str, float, str, str]] = {}
_TTL_SECONDS = 600.0


def _payload_hash(body: EntryCreateRequest) -> str:
    d = body.model_dump(mode="json")
    d.pop("confirm", None)
    d.pop("preview_token", None)
    d.pop("force_duplicate", None)
    canonical = json.dumps(d, sort_keys=True, default=str)
    return hashlib.sha256(canonical.encode()).hexdigest()


def issue_preview_token(
    body: EntryCreateRequest,
    *,
    user_id: uuid.UUID,
    business_id: uuid.UUID,
) -> str:
    h = _payload_hash(body)
    token = str(uuid.uuid4())
    exp = time.monotonic() + _TTL_SECONDS
    with _LOCK:
        _STORE[token] = (h, exp, str(user_id), str(business_id))
    return token


def verify_preview_token(
    token: str | None,
    body: EntryCreateRequest,
    *,
    user_id: uuid.UUID,
    business_id: uuid.UUID,
) -> tuple[bool, str]:
    """Validate token and payload hash without removing the token (allows 409 retry)."""
    if not token or not token.strip():
        return False, "Preview required: call with confirm=false first, then save with preview_token."
    with _LOCK:
        row = _STORE.get(token.strip())
    if row is None:
        return False, "Invalid or expired preview_token. Run Preview again."
    h_stored, exp, uid, bid = row
    if time.monotonic() > exp:
        return False, "preview_token expired. Run Preview again."
    if uid != str(user_id) or bid != str(business_id):
        return False, "preview_token does not match this user or business."
    if h_stored != _payload_hash(body):
        return False, "Entry changed since preview. Run Preview again."
    return True, ""


def consume_preview_token(token: str | None) -> None:
    """Remove token after a successful persist."""
    if not token or not token.strip():
        return
    with _LOCK:
        _STORE.pop(token.strip(), None)
