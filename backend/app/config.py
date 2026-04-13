import os
from functools import lru_cache

from pydantic_settings import (
    BaseSettings,
    PydanticBaseSettingsSource,
    SettingsConfigDict,
)


class Settings(BaseSettings):
    """Runtime configuration. Environment variable names match [.env.example](../../.env.example)."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        """Prefer `backend/.env` over machine-level env for local dev; under pytest (`APP_ENV=test`) env overrides .env."""
        if os.environ.get("APP_ENV", "").lower() == "test":
            return (
                init_settings,
                env_settings,
                dotenv_settings,
                file_secret_settings,
            )
        return (
            init_settings,
            dotenv_settings,
            env_settings,
            file_secret_settings,
        )

    app_env: str = "development"
    app_name: str = "hexa-purchase-assistant"
    app_url: str = "http://localhost:8000"
    admin_url: str = "http://localhost:5173"
    cors_origins: str = (
        "http://localhost:5173,http://127.0.0.1:5173,"
        "http://localhost:5174,http://127.0.0.1:5174,"
        "http://localhost:5175,http://127.0.0.1:5175,"
        "http://localhost:3000,http://127.0.0.1:3000,"
        "http://localhost:8080,http://127.0.0.1:8080,"
        "http://localhost:8081,http://127.0.0.1:8081,"
        "http://localhost:8082,http://127.0.0.1:8082,"
        "http://localhost:8090,http://127.0.0.1:8090,"
        "http://localhost:8091,http://127.0.0.1:8091,"
        "http://localhost:8092,http://127.0.0.1:8092"
    )

    # Local dev without Postgres: sqlite+aiosqlite:///./hexa_dev.db (file created next to cwd when running uvicorn from backend/)
    database_url: str = "postgresql+asyncpg://user:password@localhost:5432/hexa"
    # Optional: Supabase pooler (Session or Transaction) from Dashboard → Connect → pooler URI, port 6543.
    # On some hosts (e.g. Render) direct db.<ref>.supabase.co:5432 can fail with "Network is unreachable";
    # set this to the pooler URL and keep DATABASE_URL as fallback or duplicate — engine uses this when set.
    database_pooler_url: str | None = None
    # When set, overrides any password embedded in DATABASE_POOLER_URL. Use with a URI that has no
    # password in the userinfo (postgresql+asyncpg://USER@HOST:PORT/DB) so special chars like @ in the
    # password do not break parsing (avoids gaierror / "Name or service not known" on Render).
    database_pooler_password: str | None = None
    # Dev-only: if TLS fails with CERTIFICATE_VERIFY_FAILED (AV/corporate proxy MITM), set true. Forbidden in production.
    database_ssl_insecure: bool = False
    # Encrypted TLS to Postgres, but skip verifying the server certificate chain. Some PaaS (e.g. Render) + Supabase
    # pooler combinations fail SSL verify despite valid AWS certs; opt-in only. Prefer false once CA trust works.
    database_ssl_skip_verify: bool = False
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

    # Optional: Authkey.io WhatsApp (outbound). If set, outbound text may route here instead of 360dialog.
    authkey_api_key: str | None = None
    authkey_base_url: str = "https://manage.authkey.io"
    authkey_sender_label: str = "HARISREE"

    openai_api_key: str | None = None
    openai_model_parse: str = "gpt-4.1-mini"
    openai_model_summary: str = "gpt-4.1-mini"
    # stub | openai | groq | gemini — intent extraction uses matching key (env or platform_integration DB).
    ai_provider: str = "stub"
    groq_model: str = "llama-3.3-70b-versatile"
    gemini_model: str = "gemini-2.0-flash"
    groq_api_key: str | None = None
    google_ai_api_key: str | None = None
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
    # When true, WhatsApp/AI routes check BusinessSubscription (grandfather: no row = allowed).
    billing_enforce: bool = False
    # Default bundle pricing hints (paise): base cloud + optional WhatsApp+AI add-on (admin can override per business).
    billing_cloud_infra_paise: int = 230_000  # ₹2,300 (paise)
    billing_whatsapp_ai_addon_paise: int = 250_000  # ₹2,500 (paise)

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
        if self.database_ssl_insecure:
            raise RuntimeError("DATABASE_SSL_INSECURE must be false in production")


@lru_cache
def get_settings() -> Settings:
    return Settings()
