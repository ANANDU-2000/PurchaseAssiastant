from sqlalchemy import Boolean, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class FeatureFlag(Base):
    """Deployment feature toggles; missing keys fall back to Settings in code."""

    __tablename__ = "feature_flags"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
