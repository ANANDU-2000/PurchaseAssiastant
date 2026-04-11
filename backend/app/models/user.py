import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)

    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    # Null when the user only uses Sign in with Google (or other OAuth).
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    # Stable Google "sub" claim; set when user has used Google Sign-In.
    google_sub: Mapped[str | None] = mapped_column(String(128), nullable=True, unique=True, index=True)

    # Optional legacy / WhatsApp link (E.164); not used for password auth
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True, unique=True, default=None)

    name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    is_super_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    memberships = relationship("Membership", back_populates="user")
