"""Generated temporary passwords must always satisfy the password policy."""

import pytest

from app.services.passwords import validate_password_strength
from app.services.readable_password import generate_readable_password


@pytest.mark.parametrize(
    "name",
    [None, "", "   ", "Q", "Jo", "Anu", "Ravi Kumar", "krishna", "അനു", "A B", "x" * 40],
)
def test_generated_password_always_meets_policy(name):
    # The random fallback used to omit digits ~28% of the time and "anu@123" was only 7 chars.
    for _ in range(500):
        pwd = generate_readable_password(name)
        validate_password_strength(pwd)
        assert len(pwd) >= 8


def test_named_password_keeps_readable_format():
    pwd = generate_readable_password("Krishna Kumar")
    assert pwd.startswith("krishna@")
    assert pwd.split("@", 1)[1].isdigit()
