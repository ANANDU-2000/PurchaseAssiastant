from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration. Environment variable names match [.env.example](../../.env.example)."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_env: str = "development"
    app_name: str = "hexa-purchase-assistant"
    app_url: str = "http://localhost:8000"
    admin_url: str = "http://localhost:5173"
    cors_origins: str = "http://localhost:5173,http://localhost:3000,http://localhost:8080"

    # Local dev without Postgres: sqlite+aiosqlite:///./hexa_dev.db (file created next to cwd when running uvicorn from backend/)
    database_url: str = "postgresql+asyncpg://user:password@localhost:5432/hexa"
    redis_url: str | None = "redis://localhost:6379/0"

    jwt_secret: str = "change-me-min-32-chars-dev-only"
    jwt_refresh_secret: str = "change-me-min-32-chars-refresh-dev"
    jwt_access_ttl_minutes: int = 15
    jwt_refresh_ttl_days: int = 30

    dev_return_otp: bool = True
    dev_otp_code: str = "000000"

    otp_provider: str = "twilio"
    otp_api_key: str | None = None
    otp_sender_id: str = "HEXA"
    otp_requests_per_minute_per_ip: int = 10

    superadmin_bootstrap_phone: str | None = None  # legacy; prefer SUPERADMIN_BOOTSTRAP_EMAIL
    superadmin_bootstrap_email: str | None = None

    # Comma-separated OAuth 2.0 client IDs whose ID tokens we accept (usually one Web client used as serverClientId in Flutter).
    google_oauth_client_ids: str = ""

    dialog360_api_key: str | None = None
    dialog360_base_url: str = "https://waba-v2.360dialog.io"
    dialog360_phone_number_id: str | None = None
    dialog360_webhook_secret: str | None = None
    dialog360_template_namespace: str | None = None

    openai_api_key: str | None = None
    openai_model_parse: str = "gpt-4.1-mini"
    openai_model_summary: str = "gpt-4.1-mini"
    ocr_provider: str = "google_vision"
    ocr_api_key: str | None = None
    stt_provider: str = "openai_whisper"
    stt_api_key: str | None = None

    s3_bucket: str | None = None
    s3_region: str = "ap-south-1"
    s3_access_key: str | None = None
    s3_secret_key: str | None = None
    s3_endpoint: str | None = None

    razorpay_key_id: str | None = None
    razorpay_key_secret: str | None = None
    razorpay_webhook_secret: str | None = None
    plan_basic_price_inr: int = 49900
    plan_pro_price_inr: int = 99900
    plan_premium_price_inr: int = 199900

    sentry_dsn: str | None = None
    log_level: str = "INFO"
    metrics_token: str | None = None
    # Optional static Bearer for admin API + admin_web (machine auth). Prefer long random values in production.
    admin_api_token: str | None = None
    # Internal admin SPA login (POST /v1/admin/login). Plaintext — use only on trusted networks.
    admin_email: str | None = None
    admin_password: str | None = None

    enable_ai: bool = True
    enable_ocr: bool = False
    enable_voice: bool = False
    enable_realtime: bool = True

    trusted_hosts: str | None = None

    def google_oauth_client_id_list(self) -> list[str]:
        return [x.strip() for x in self.google_oauth_client_ids.split(",") if x.strip()]

    def validate_production_safety(self) -> None:
        """Call on startup when app_env is production."""
        if self.app_env.lower() != "production":
            return
        if self.dev_return_otp:
            raise RuntimeError("DEV_RETURN_OTP must be false in production")
        if "change-me" in self.jwt_secret.lower() or "change-me" in self.jwt_refresh_secret.lower():
            raise RuntimeError("JWT secrets must be changed in production")
        if len(self.jwt_secret) < 32 or len(self.jwt_refresh_secret) < 32:
            raise RuntimeError("JWT secrets must be at least 32 characters in production")


@lru_cache
def get_settings() -> Settings:
    return Settings()
