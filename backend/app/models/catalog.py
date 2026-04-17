import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, Numeric, String, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


def utcnow():
    return datetime.now(timezone.utc)


class ItemCategory(Base):
    __tablename__ = "item_categories"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    name: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    items = relationship("CatalogItem", back_populates="category", cascade="all, delete-orphan")
    category_types = relationship(
        "CategoryType", back_populates="category", cascade="all, delete-orphan"
    )


class CategoryType(Base):
    """Middle layer: Category (e.g. Rice) → Type (e.g. Biriyani rice) → catalog items / variants."""

    __tablename__ = "category_types"
    __table_args__ = (UniqueConstraint("category_id", "name", name="uq_category_types_name"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    category_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("item_categories.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    category = relationship("ItemCategory", back_populates="category_types")
    catalog_items = relationship("CatalogItem", back_populates="catalog_type")


class CatalogItem(Base):
    __tablename__ = "catalog_items"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    category_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("item_categories.id"), index=True)
    type_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("category_types.id", ondelete="SET NULL"), nullable=True, index=True
    )
    name: Mapped[str] = mapped_column(String(512))
    default_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    default_kg_per_bag: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    hsn_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    tax_percent: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    default_landing_cost: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    default_selling_cost: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    category = relationship("ItemCategory", back_populates="items")
    catalog_type = relationship("CategoryType", back_populates="catalog_items")
    variants = relationship("CatalogVariant", back_populates="item", cascade="all, delete-orphan")


class CatalogVariant(Base):
    """Granular product under a catalog item (e.g. Grains → Rice → Basmati)."""

    __tablename__ = "catalog_variants"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    catalog_item_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id"), index=True
    )
    name: Mapped[str] = mapped_column(String(512))
    default_kg_per_bag: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    item = relationship("CatalogItem", back_populates="variants")
