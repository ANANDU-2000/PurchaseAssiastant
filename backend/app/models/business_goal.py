"""Per-business goals for Reports progress (profit + volume)."""

import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, Numeric, String, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


def utcnow():
    return datetime.now(timezone.utc)


class BusinessGoal(Base):
    __tablename__ = "business_goals"
    __table_args__ = (UniqueConstraint("business_id", "period", name="uq_business_goals_biz_period"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    period: Mapped[str] = mapped_column(String(16), index=True)  # YYYY-MM
    profit_goal: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    volume_goal: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
