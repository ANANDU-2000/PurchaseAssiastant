"""Wholesale purchase documents (PUR-YYYY-XXXX) separate from legacy `entries`."""

import uuid
from datetime import date, datetime, timezone

from sqlalchemy import Date, DateTime, ForeignKey, Integer, Numeric, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base
from app.models.contacts import Broker, Supplier


def utcnow():
    return datetime.now(timezone.utc)


class BrokerSupplierLink(Base):
    """M2M: broker can serve multiple suppliers (beyond legacy single broker_id on supplier)."""

    # Physical name avoids clashing with an existing pg_type named broker_supplier_links
    # (e.g. stray ENUM) on some managed Postgres instances.
    __tablename__ = "broker_supplier_m2m"
    __table_args__ = (UniqueConstraint("broker_id", "supplier_id", name="uq_broker_supplier_m2m_pair"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    broker_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("brokers.id"), index=True)
    supplier_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("suppliers.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class TradePurchase(Base):
    __tablename__ = "trade_purchases"
    __table_args__ = (UniqueConstraint("business_id", "human_id", name="uq_trade_purchases_business_human"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("users.id"), index=True)
    human_id: Mapped[str] = mapped_column(String(32), index=True)
    purchase_date: Mapped[date] = mapped_column(Date, index=True)
    supplier_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("suppliers.id"), nullable=True, index=True
    )
    broker_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("brokers.id"), nullable=True, index=True
    )
    payment_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    due_date: Mapped[date | None] = mapped_column(Date, nullable=True, index=True)
    paid_amount: Mapped[float] = mapped_column(Numeric(18, 4), default=0)
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    discount: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    commission_percent: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    delivered_rate: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    billty_rate: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    freight_amount: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    freight_type: Mapped[str | None] = mapped_column(String(16), nullable=True)
    total_qty: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    total_amount: Mapped[float] = mapped_column(Numeric(18, 4))
    status: Mapped[str] = mapped_column(String(24), default="confirmed")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    lines = relationship("TradePurchaseLine", back_populates="purchase", cascade="all, delete-orphan")
    supplier_row = relationship(Supplier, foreign_keys=[supplier_id], lazy="selectin")
    broker_row = relationship(Broker, foreign_keys=[broker_id], lazy="selectin")


class TradePurchaseLine(Base):
    __tablename__ = "trade_purchase_lines"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    trade_purchase_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("trade_purchases.id", ondelete="CASCADE"), index=True
    )
    catalog_item_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id"), nullable=True, index=True
    )
    item_name: Mapped[str] = mapped_column(String(512))
    qty: Mapped[float] = mapped_column(Numeric(18, 4))
    unit: Mapped[str] = mapped_column(String(32))
    landing_cost: Mapped[float] = mapped_column(Numeric(18, 4))
    selling_cost: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    discount: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    tax_percent: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)

    purchase = relationship("TradePurchase", back_populates="lines")
    catalog_item = relationship("CatalogItem", foreign_keys=[catalog_item_id], lazy="selectin")


class TradePurchaseDraft(Base):
    __tablename__ = "trade_purchase_drafts"
    __table_args__ = (UniqueConstraint("business_id", "user_id", name="uq_trade_purchase_drafts_biz_user"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("users.id"), index=True)
    step: Mapped[int] = mapped_column(default=0)
    payload_json: Mapped[str] = mapped_column(Text, default="{}")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
