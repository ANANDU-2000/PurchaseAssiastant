import re
import secrets
import string

# Readable passwords (no 0/O, 1/l/I confusion).
_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz"


def generate_readable_password(full_name: str | None = None, length: int = 8) -> str:
    """Generate password like krishna@123 when name is provided."""
    if full_name:
        token = re.sub(r"[^a-z0-9]", "", full_name.strip().lower().split()[0])
        if len(token) >= 2:
            suffix = "".join(secrets.choice(string.digits) for _ in range(3))
            return f"{token[:12]}@{suffix}"
    return "".join(secrets.choice(_ALPHABET) for _ in range(length))
