"""Per-supplier purchase memory for catalog items (last price, discount, payment days)."""

import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, Integer, Numeric, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


def utcnow():
    return datetime.now(timezone.utc)


class SupplierItemDefault(Base):
    __tablename__ = "supplier_item_defaults"
    __table_args__ = (
        UniqueConstraint("business_id", "supplier_id", "catalog_item_id", name="uq_supplier_item_default"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    supplier_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("suppliers.id"), index=True)
    catalog_item_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("catalog_items.id"), index=True)
    last_price: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    last_discount: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    last_payment_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    purchase_count: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
