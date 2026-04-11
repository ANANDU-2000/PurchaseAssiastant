import re

from pydantic import BaseModel, Field, field_validator


class RegisterRequest(BaseModel):
    email: str = Field(..., min_length=5, max_length=320)
    username: str = Field(..., min_length=3, max_length=64)
    password: str = Field(..., min_length=8, max_length=128)

    @field_validator("email")
    @classmethod
    def email_lower(cls, v: str) -> str:
        return v.strip().lower()

    @field_validator("username")
    @classmethod
    def username_normalize(cls, v: str) -> str:
        s = v.strip().lower()
        if not re.match(r"^[a-z0-9_]{3,64}$", s):
            raise ValueError("Username: 3–64 chars, letters, numbers, underscore only")
        return s


class LoginRequest(BaseModel):
    """Log in with email or username plus password."""

    email_or_username: str = Field(..., min_length=1, max_length=320)
    password: str = Field(..., min_length=1, max_length=128)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    expires_in: int


class GoogleAuthRequest(BaseModel):
    """ID token from Google Sign-In (Flutter `GoogleSignInAuthentication.idToken`)."""

    id_token: str = Field(..., min_length=20, max_length=12000)


class RefreshRequest(BaseModel):
    refresh_token: str
