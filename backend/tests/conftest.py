import sys
from pathlib import Path

# Ensure `app` package resolves when running pytest from repo root or backend/
_root = Path(__file__).resolve().parents[1]
if str(_root) not in sys.path:
    sys.path.insert(0, str(_root))
