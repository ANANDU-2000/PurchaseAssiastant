import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class Business(Base):
    __tablename__ = "businesses"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(255))
    # Optional white-label strings for mobile/web UI (per workspace). OS app name still from store listing.
    branding_title: Mapped[str | None] = mapped_column(String(128), nullable=True)
    branding_logo_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    default_currency: Mapped[str] = mapped_column(String(3), default="INR")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    memberships = relationship("Membership", back_populates="business")
    entries = relationship("Entry", back_populates="business")
    subscription = relationship(
        "BusinessSubscription", back_populates="business", uselist=False
    )
