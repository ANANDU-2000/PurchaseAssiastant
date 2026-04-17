import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, Integer, Numeric, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


def utcnow():
    return datetime.now(timezone.utc)


class Broker(Base):
    __tablename__ = "brokers"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    name: Mapped[str] = mapped_column(String(255))
    phone: Mapped[str | None] = mapped_column(String(15), nullable=True)
    commission_type: Mapped[str] = mapped_column(String(32), default="percent")
    commission_value: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    suppliers = relationship("Supplier", back_populates="broker")


class Supplier(Base):
    __tablename__ = "suppliers"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    name: Mapped[str] = mapped_column(String(255))
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    gst_number: Mapped[str | None] = mapped_column(String(20), nullable=True)
    default_payment_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    default_discount: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    default_delivered_rate: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    default_billty_rate: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    whatsapp_number: Mapped[str | None] = mapped_column(String(32), nullable=True)
    location: Mapped[str | None] = mapped_column(Text, nullable=True)
    broker_id: Mapped[uuid.UUID | None] = mapped_column(Uuid(as_uuid=True), ForeignKey("brokers.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    broker = relationship("Broker", back_populates="suppliers")
