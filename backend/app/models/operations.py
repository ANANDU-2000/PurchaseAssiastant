import uuid
from datetime import date, datetime, timezone
from decimal import Decimal

from sqlalchemy import Date, DateTime, ForeignKey, Integer, Numeric, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


def utcnow():
    return datetime.now(timezone.utc)


class DailyUsageLog(Base):
    __tablename__ = "daily_usage_logs"
    __table_args__ = (
        UniqueConstraint("business_id", "item_id", "usage_date", name="uq_daily_usage_item_date"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("businesses.id", ondelete="CASCADE"), index=True
    )
    item_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id", ondelete="CASCADE"), index=True
    )
    usage_date: Mapped[date] = mapped_column(Date, index=True)
    opening_qty: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=Decimal("0"))
    purchased_qty: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=Decimal("0"))
    used_qty: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=Decimal("0"))
    closing_qty: Mapped[Decimal] = mapped_column(Numeric(12, 3), default=Decimal("0"))
    logged_by_user_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class StaffChecklistTemplate(Base):
    __tablename__ = "staff_checklist_templates"
    __table_args__ = (
        UniqueConstraint("business_id", "slot", "task_key", name="uq_checklist_template"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("businesses.id", ondelete="CASCADE"), nullable=True, index=True
    )
    slot: Mapped[str] = mapped_column(String(16))
    task_key: Mapped[str] = mapped_column(String(64))
    label: Mapped[str] = mapped_column(String(255))
    sort_order: Mapped[int] = mapped_column(Integer, default=0)


class StaffChecklistCompletion(Base):
    __tablename__ = "staff_checklist_completions"
    __table_args__ = (
        UniqueConstraint(
            "business_id",
            "user_id",
            "checklist_date",
            "slot",
            "task_key",
            name="uq_checklist_completion",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("businesses.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    checklist_date: Mapped[date] = mapped_column(Date, index=True)
    slot: Mapped[str] = mapped_column(String(16))
    task_key: Mapped[str] = mapped_column(String(64))
    completed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
