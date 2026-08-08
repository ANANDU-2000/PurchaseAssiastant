"""Owner-ops unit tests (no DB): backup dry-run + credential crypto."""

from __future__ import annotations

from app.services.backup_ops import SCHEMA_VERSION, dry_run_restore
from app.services.provider_credentials import encrypt_secret, decrypt_secret, mask_last4


def test_dry_run_rejects_bad_schema():
    out = dry_run_restore({"schema_version": "other", "business_id": "x"})
    assert out["ok"] is False
    assert "schema_version" in (out.get("error") or "")


def test_dry_run_ok_payload():
    out = dry_run_restore(
        {
            "schema_version": SCHEMA_VERSION,
            "business_id": "11111111-1111-1111-1111-111111111111",
            "catalog": [{}],
            "suppliers": [],
            "purchases": [{}, {}],
            "stock_audits": [],
        }
    )
    assert out["ok"] is True
    assert out["would_add"]["catalog"] == 1
    assert out["would_add"]["purchases"] == 2
    assert out["commit_supported"] is False
    assert out.get("confirm_token")


def test_credential_roundtrip_mask():
    token = encrypt_secret("sk-test-ABCDEFGH")
    assert decrypt_secret(token) == "sk-test-ABCDEFGH"
    assert mask_last4("sk-test-ABCDEFGH") == "EFGH"
