"""Per-business SaaS billing state and add-ons."""

import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class BusinessSubscription(Base):
    __tablename__ = "business_subscriptions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("businesses.id"), unique=True, index=True
    )

    plan_code: Mapped[str] = mapped_column(String(32), default="basic")
    # active | trialing | past_due | suspended | exempt
    status: Mapped[str] = mapped_column(String(32), default="active")

    whatsapp_addon: Mapped[bool] = mapped_column(Boolean, default=False)
    ai_addon: Mapped[bool] = mapped_column(Boolean, default=False)
    voice_addon: Mapped[bool] = mapped_column(Boolean, default=False)

    admin_exempt: Mapped[bool] = mapped_column(Boolean, default=False)
    exempt_reason: Mapped[str | None] = mapped_column(Text, nullable=True)

    grace_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    current_period_start: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    current_period_end: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    monthly_base_paise: Mapped[int] = mapped_column(Integer, default=0)
    monthly_addons_paise: Mapped[int] = mapped_column(Integer, default=0)

    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    business = relationship("Business", back_populates="subscription")
