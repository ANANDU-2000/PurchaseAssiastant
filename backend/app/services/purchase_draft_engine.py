"""Purchase draft pipeline — contracts and thresholds.

Full wizard + `scan_drafts` tables are specified in ``docs/AI_PURCHASE_DRAFT_ENGINE.md``.
Scan endpoints today return ``ScanResult`` + ``scan_token``; ``POST .../confirm`` creates
``TradePurchase``. This module centralizes shared constants for the future draft-first path.

Do not perform financial totals here until wired to validated ``TradePurchaseCreateRequest``
payloads — totals remain authoritative in ``trade_purchase_service``.
"""

from __future__ import annotations

# Confidence policy (align Flutter pills + server needs_review).
CONFIDENCE_SUGGEST_THRESHOLD = 0.75
CONFIDENCE_AUTO_OK_THRESHOLD = 0.92
