import uuid
from datetime import date, datetime, timezone

from sqlalchemy import Date, DateTime, ForeignKey, Numeric, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


def utcnow():
    return datetime.now(timezone.utc)


class Entry(Base):
    __tablename__ = "entries"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("users.id"), index=True)
    supplier_id: Mapped[uuid.UUID | None] = mapped_column(Uuid(as_uuid=True), ForeignKey("suppliers.id"), nullable=True)
    broker_id: Mapped[uuid.UUID | None] = mapped_column(Uuid(as_uuid=True), ForeignKey("brokers.id"), nullable=True)
    entry_date: Mapped[date] = mapped_column(Date, index=True)
    invoice_no: Mapped[str | None] = mapped_column(String(128), nullable=True)
    transport_cost: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    commission_amount: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    source: Mapped[str] = mapped_column(String(32), default="app")
    status: Mapped[str] = mapped_column(String(32), default="confirmed")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    business = relationship("Business", back_populates="entries")
    lines = relationship("EntryLineItem", back_populates="entry", cascade="all, delete-orphan")


class EntryLineItem(Base):
    __tablename__ = "entry_line_items"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    entry_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("entries.id"), index=True)
    catalog_item_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id"), nullable=True, index=True
    )
    item_name: Mapped[str] = mapped_column(String(512))
    category: Mapped[str | None] = mapped_column(String(255), nullable=True)
    qty: Mapped[float] = mapped_column(Numeric(18, 4))
    unit: Mapped[str] = mapped_column(String(32))
    qty_base: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    base_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    buy_price: Mapped[float] = mapped_column(Numeric(18, 4))
    landing_cost: Mapped[float] = mapped_column(Numeric(18, 4))
    selling_price: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    currency: Mapped[str] = mapped_column(String(3), default="INR")
    profit: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)

    entry = relationship("Entry", back_populates="lines")
