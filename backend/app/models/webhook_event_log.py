"""Deduplicate provider webhook deliveries (Razorpay event id)."""

from datetime import datetime, timezone

from sqlalchemy import DateTime, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class WebhookEventLog(Base):
    __tablename__ = "webhook_event_logs"

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    provider: Mapped[str] = mapped_column(String(32), default="razorpay")
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    payload_preview: Mapped[str | None] = mapped_column(Text, nullable=True)
