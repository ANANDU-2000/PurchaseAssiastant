"""Production safety checks on Settings."""

import pytest

from app.config import Settings


def test_validate_production_rejects_dev_return_otp(monkeypatch):
    monkeypatch.delenv("HEXA_USE_SQLITE", raising=False)
    s = Settings(
        app_env="production",
        dev_return_otp=True,
        jwt_secret="x" * 64,
        jwt_refresh_secret="y" * 64,
    )
    with pytest.raises(RuntimeError, match="DEV_RETURN_OTP must be false in production"):
        s.validate_production_safety()


def test_validate_production_ok(monkeypatch):
    monkeypatch.delenv("HEXA_USE_SQLITE", raising=False)
    s = Settings(
        app_env="production",
        dev_return_otp=False,
        jwt_secret="x" * 64,
        jwt_refresh_secret="y" * 64,
    )
    s.validate_production_safety()


def test_validate_production_rejects_short_jwt_secret(monkeypatch):
    monkeypatch.delenv("HEXA_USE_SQLITE", raising=False)
    s = Settings(
        app_env="production",
        dev_return_otp=False,
        jwt_secret="x" * 31,
        jwt_refresh_secret="y" * 64,
    )
    with pytest.raises(RuntimeError, match="at least 32 characters"):
        s.validate_production_safety()


def test_validate_production_rejects_change_me_jwt(monkeypatch):
    monkeypatch.delenv("HEXA_USE_SQLITE", raising=False)
    s = Settings(
        app_env="production",
        dev_return_otp=False,
        jwt_secret="change-me-in-production",
        jwt_refresh_secret="y" * 64,
    )
    with pytest.raises(RuntimeError, match="must be changed"):
        s.validate_production_safety()
