import uuid
from datetime import date, datetime, timezone
from decimal import Decimal

from sqlalchemy import Date, DateTime, ForeignKey, Numeric, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


def utcnow():
    return datetime.now(timezone.utc)


class StockPhysicalCount(Base):
    __tablename__ = "stock_physical_counts"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("businesses.id", ondelete="CASCADE"), index=True
    )
    item_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id", ondelete="CASCADE"), index=True
    )
    system_qty: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    counted_qty: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    difference_qty: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    purchased_qty: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    stock_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    period_start: Mapped[date | None] = mapped_column(Date, nullable=True)
    period_end: Mapped[date | None] = mapped_column(Date, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    counted_by: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    counted_by_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    counted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)
    idempotency_key: Mapped[str | None] = mapped_column(String(120), nullable=True)

