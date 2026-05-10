"""Wholesale unit / packaging intelligence tables (master data + learning)."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Integer, Numeric, String, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


def utcnow():
    return datetime.now(timezone.utc)


class MasterUnit(Base):
    """Canonical unit codes (BAG, KG, BOX, …) — global reference."""

    __tablename__ = "master_units"
    __table_args__ = (UniqueConstraint("unit_code", name="uq_master_units_unit_code"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    unit_code: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    display_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    category: Mapped[str | None] = mapped_column(String(64), nullable=True)
    conversion_supported: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class ItemPackagingProfile(Base):
    """Optional alternate packaging rows per catalog item (AI / learning)."""

    __tablename__ = "item_packaging_profiles"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    catalog_item_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id", ondelete="CASCADE"), index=True
    )
    package_type: Mapped[str | None] = mapped_column(String(32), nullable=True)
    package_size: Mapped[Decimal | None] = mapped_column(Numeric(14, 4), nullable=True)
    package_measurement: Mapped[str | None] = mapped_column(String(16), nullable=True)
    selling_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    stock_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    display_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    conversion_factor: Mapped[Decimal | None] = mapped_column(Numeric(14, 6), nullable=True)
    confidence_score: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    ai_generated: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    updated_by_learning: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    catalog_item = relationship("CatalogItem", back_populates="packaging_profiles")


class OcrItemAlias(Base):
    """OCR / fuzzy text → catalog item linkage with confidence."""

    __tablename__ = "ocr_item_aliases"
    __table_args__ = (
        UniqueConstraint("business_id", "normalized_alias", "catalog_item_id", name="uq_ocr_alias_item_norm"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    alias: Mapped[str] = mapped_column(String(512), nullable=False)
    normalized_alias: Mapped[str] = mapped_column(String(512), nullable=False, index=True)
    catalog_item_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id", ondelete="CASCADE"), index=True
    )
    confidence: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    source: Mapped[str | None] = mapped_column(String(32), nullable=True)
    usage_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)


class SmartUnitRule(Base):
    """Keyword / category → unit heuristics (tenant or global when business_id is null)."""

    __tablename__ = "smart_unit_rules"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("businesses.id", ondelete="CASCADE"), nullable=True, index=True
    )
    keyword_pattern: Mapped[str] = mapped_column(String(255), nullable=False)
    category: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
    resulting_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    package_type: Mapped[str | None] = mapped_column(String(32), nullable=True)
    confidence: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class ItemLearningHistory(Base):
    """User corrections for adaptive confidence (per business)."""

    __tablename__ = "item_learning_history"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    catalog_item_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id", ondelete="CASCADE"), index=True
    )
    detected_pattern: Mapped[str | None] = mapped_column(String(512), nullable=True)
    selected_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    corrected_by_user: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    learning_score: Mapped[Decimal | None] = mapped_column(Numeric(8, 3), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class UnitConfidenceLog(Base):
    """Append-only scoring trail for audits."""

    __tablename__ = "unit_confidence_logs"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    catalog_item_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id", ondelete="SET NULL"), nullable=True, index=True
    )
    source: Mapped[str | None] = mapped_column(String(64), nullable=True)
    score: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    payload_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class AiItemProfile(Base):
    """Structured AI / scanner snapshot per item (JSON SSOT extension)."""

    __tablename__ = "ai_item_profiles"
    __table_args__ = (UniqueConstraint("business_id", "catalog_item_id", name="uq_ai_item_profile_item"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    catalog_item_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id", ondelete="CASCADE"), index=True
    )
    profile_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)


class SmartPackageRule(Base):
    """High-level package keyword → package_type."""

    __tablename__ = "smart_package_rules"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("businesses.id", ondelete="CASCADE"), nullable=True, index=True
    )
    keyword_pattern: Mapped[str] = mapped_column(String(255), nullable=False)
    package_type: Mapped[str] = mapped_column(String(32), nullable=False)
    priority: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
