"""Singleton row (id=1): optional overrides for API keys — merges with process env (Settings)."""

from datetime import datetime

from sqlalchemy import DateTime, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class PlatformIntegration(Base):
    """
    Non-technical operators can update keys via POST /v1/admin/platform-integration
    without redeploying. When a column is NULL, Settings (env) is used.
    """

    __tablename__ = "platform_integration"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, default=1)

    openai_api_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    google_ai_api_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    groq_api_key: Mapped[str | None] = mapped_column(Text, nullable=True)

    dialog360_api_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    dialog360_phone_number_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    dialog360_base_url: Mapped[str | None] = mapped_column(String(256), nullable=True)
    dialog360_webhook_secret: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Razorpay (optional DB override; env RAZORPAY_* used when NULL)
    razorpay_key_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    razorpay_key_secret: Mapped[str | None] = mapped_column(Text, nullable=True)
    razorpay_webhook_secret: Mapped[str | None] = mapped_column(Text, nullable=True)

    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
