"""Manual infra / cloud cost lines for super-admin P&L."""

import uuid
from datetime import date, datetime, timezone

from sqlalchemy import Date, DateTime, Integer, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class PlatformMonthlyExpense(Base):
    __tablename__ = "platform_monthly_expenses"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    month: Mapped[date] = mapped_column(Date, index=True)
    label: Mapped[str] = mapped_column(String(255))
    amount_inr_paise: Mapped[int] = mapped_column(Integer)
    category: Mapped[str] = mapped_column(String(64), default="infra")
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
