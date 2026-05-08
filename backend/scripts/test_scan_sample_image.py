"""Run scanner v2 on a local image (OpenAI Vision + your .env keys).

Usage (from ``backend/``):

  python -m scripts.test_scan_sample_image "..\\samplsimages\\WhatsApp Image 2026-05-08 at 5.18.59 PM.jpeg"

Optional: ``--business-id <uuid>`` (defaults to first row in ``businesses``).

Does not print API keys. Requires network (OpenAI) and a working ``DATABASE_*`` in ``.env``.

If you see ``SSLCertVerificationError`` to Supabase pooler on Windows (corporate proxy /
MITM), run once with::

  set DATABASE_SSL_SKIP_VERIFY=true   # PowerShell: $env:DATABASE_SSL_SKIP_VERIFY='true'

(Prefer fixing system trust; this only skips certificate *verification*, traffic stays TLS.)
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path
from uuid import UUID

# Allow `python -m scripts.test_scan_sample_image` from backend/
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


async def _run(image_path: Path, business_id: UUID | None) -> int:
    from sqlalchemy import select

    from app.config import get_settings
    from app.database import async_session_factory
    from app.models import Business
    from app.services.scanner_v2.pipeline import scan_purchase_v2

    raw = image_path.read_bytes()
    if not raw:
        print("empty image", file=sys.stderr)
        return 2

    settings = get_settings()
    key_ok = bool((getattr(settings, "openai_api_key", None) or "").strip())
    if not key_ok:
        print("OPENAI_API_KEY is empty in settings (.env)", file=sys.stderr)
        return 4

    async with async_session_factory() as db:
        bid = business_id
        if bid is None:
            r = await db.execute(select(Business.id).limit(1))
            bid = r.scalar_one_or_none()
            if bid is None:
                print("No Business row; bootstrap workspace or pass --business-id", file=sys.stderr)
                return 3

        result = await scan_purchase_v2(
            db=db,
            business_id=bid,
            user_id=None,
            settings=settings,
            image_bytes=raw,
        )

    print(json.dumps(result.model_dump(mode="json"), indent=2, default=str))
    return 0


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("image", type=Path, help="Path to JPEG/PNG/WebP")
    p.add_argument("--business-id", type=UUID, default=None)
    args = p.parse_args()
    ip = args.image.resolve()
    if not ip.is_file():
        print(f"not a file: {ip}", file=sys.stderr)
        sys.exit(2)
    sys.exit(asyncio.run(_run(ip, args.business_id)))


if __name__ == "__main__":
    main()
