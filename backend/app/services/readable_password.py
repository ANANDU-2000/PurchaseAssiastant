import re
import secrets
import string

# Readable passwords (no 0/O, 1/l/I confusion).
_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz"
_DIGITS = "23456789"
# Must satisfy app.services.passwords.validate_password_strength (>= 8 chars, at least one digit).
_MIN_LENGTH = 8


def generate_readable_password(full_name: str | None = None, length: int = 8) -> str:
    """Generate password like krishna@123 when name is provided.

    The result always passes the password policy: at least 8 characters and at least
    one digit (short names get a longer numeric suffix, random fallbacks get a digit).
    """
    length = max(length, _MIN_LENGTH)
    words = (full_name or "").strip().lower().split()
    if words:
        token = re.sub(r"[^a-z0-9]", "", words[0])[:12]
        if len(token) >= 2:
            suffix_len = max(3, _MIN_LENGTH - len(token) - 1)
            suffix = "".join(secrets.choice(string.digits) for _ in range(suffix_len))
            return f"{token}@{suffix}"
    chars = [secrets.choice(_ALPHABET) for _ in range(length)]
    if not any(c.isdigit() for c in chars):
        chars[secrets.randbelow(length)] = secrets.choice(_DIGITS)
    return "".join(chars)
