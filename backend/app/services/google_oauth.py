"""Verify Google ID tokens (Sign in with Google) for the backend."""

from __future__ import annotations

import asyncio

from google.auth.transport import requests
from google.oauth2 import id_token


async def verify_google_id_token_async(token: str, audiences: list[str]) -> dict:
    """Validate `token` and return claims. Tries each audience (client ID) until one succeeds."""
    return await asyncio.to_thread(_verify_google_id_token, token, audiences)


def _verify_google_id_token(token: str, audiences: list[str]) -> dict:
    req = requests.Request()
    last: ValueError | None = None
    for aud in audiences:
        try:
            return id_token.verify_oauth2_token(token, req, aud)
        except ValueError as e:
            last = e
    if last:
        raise ValueError("Google ID token could not be verified for configured client IDs") from last
    raise ValueError("No GOOGLE_OAUTH_CLIENT_IDS configured")
