"""Stock Engine Constants & Rules — Single Source of Truth.

SYSTEM STOCK FORMULA:
    System Stock = Opening Stock
                 + Verified Deliveries
                 + Quick Purchases
                 + Manual Adjustments (net)
                 - Sales
                 - Damages
                 - Usage (transfers, consumption)

RULES:
    1. Purchase Total NEVER equals System Stock
    2. Stock is NEVER updated before warehouse verification
    3. Opening Stock must be set once when company starts using app
    4. Without Opening Stock, show warning — never create fake stock values
    5. Physical Stock is always separate from System Stock
    6. Stock difference = System Stock - Physical Stock (for owner review only)
    7. Only `delivery_receive` movements from VERIFIED purchases add to stock

DELIVERY WORKFLOW:
    Draft → Pending → Dispatched → In Transit → Arrived → Staff Verified → Stock Committed

MOVEMENT KINDS (for stock_movements ledger):
    INBOUND (positive delta):
        - delivery_receive: Verified purchase delivery committed to stock
        - quick_purchase: Staff quick-add purchase
        - opening_stock: Initial opening stock set by owner
        - correction: Manual positive adjustment

    OUTBOUND (negative delta):
        - sale: Stock sold/dispatched to customer
        - damage: Stock damaged/wasted
        - usage: Stock consumed internally or transferred
        - delivery_revoke: Purchase delivery reversal
        - correction: Manual negative adjustment (undo)

STOCK STATUS RULES:
    - out: current_stock <= 0
    - critical: current_stock <= reorder_level * 0.5 (when reorder > 0)
    - low: current_stock < reorder_level (when reorder > 0)
              OR current_stock < 1 (when no reorder level set)
    - healthy: all other cases

COLOR CODES:
    - Green: Healthy
    - Orange: Low Stock
    - Red: Out Of Stock
    - Blue: Pending Verification
    - Purple: Pending Delivery
"""

from typing import Final

# --- Movement Kinds ---
MOVEMENT_DELIVERY_RECEIVE: Final = "delivery_receive"
MOVEMENT_DELIVERY_REVOKE: Final = "delivery_revoke"
MOVEMENT_QUICK_PURCHASE: Final = "quick_purchase"
MOVEMENT_OPENING_STOCK: Final = "opening_stock"
MOVEMENT_SALE: Final = "sale"
MOVEMENT_DAMAGE: Final = "damage"
MOVEMENT_USAGE: Final = "usage"
MOVEMENT_CORRECTION: Final = "correction"
MOVEMENT_UNDO: Final = "undo"
MOVEMENT_PHYSICAL_COUNT: Final = "physical_count"

INBOUND_MOVEMENT_KINDS: Final = frozenset({
    MOVEMENT_DELIVERY_RECEIVE,
    MOVEMENT_QUICK_PURCHASE,
    MOVEMENT_OPENING_STOCK,
})

OUTBOUND_MOVEMENT_KINDS: Final = frozenset({
    MOVEMENT_SALE,
    MOVEMENT_DAMAGE,
    MOVEMENT_USAGE,
    MOVEMENT_DELIVERY_REVOKE,
})

# Adjustments can be positive or negative
ADJUSTMENT_MOVEMENT_KINDS: Final = frozenset({
    MOVEMENT_CORRECTION,
    MOVEMENT_UNDO,
    MOVEMENT_PHYSICAL_COUNT,
})

ALL_MOVEMENT_KINDS: Final = INBOUND_MOVEMENT_KINDS | OUTBOUND_MOVEMENT_KINDS | ADJUSTMENT_MOVEMENT_KINDS

# --- Delivery Status Values ---
DELIVERY_PENDING: Final = "pending"
DELIVERY_DISPATCHED: Final = "dispatched"
DELIVERY_IN_TRANSIT: Final = "in_transit"
DELIVERY_ARRIVED: Final = "arrived"
DELIVERY_STAFF_VERIFYING: Final = "staff_verifying"
DELIVERY_STAFF_VERIFIED: Final = "staff_verified"
DELIVERY_PARTIAL: Final = "partial"
DELIVERY_STOCK_COMMITTED: Final = "stock_committed"
DELIVERY_CANCELLED: Final = "cancelled"

# Valid transitions for the delivery state machine
DELIVERY_TRANSITIONS: Final = {
    DELIVERY_PENDING: frozenset({DELIVERY_DISPATCHED, DELIVERY_IN_TRANSIT, DELIVERY_ARRIVED}),
    DELIVERY_DISPATCHED: frozenset({DELIVERY_IN_TRANSIT, DELIVERY_ARRIVED}),
    DELIVERY_IN_TRANSIT: frozenset({DELIVERY_ARRIVED}),
    DELIVERY_ARRIVED: frozenset({DELIVERY_STAFF_VERIFYING, DELIVERY_STAFF_VERIFIED, DELIVERY_PARTIAL}),
    DELIVERY_STAFF_VERIFYING: frozenset({DELIVERY_STAFF_VERIFIED, DELIVERY_PARTIAL}),
    DELIVERY_STAFF_VERIFIED: frozenset({DELIVERY_STOCK_COMMITTED}),
    DELIVERY_PARTIAL: frozenset({DELIVERY_STOCK_COMMITTED}),
    DELIVERY_STOCK_COMMITTED: frozenset(),  # Terminal
    DELIVERY_CANCELLED: frozenset(),  # Terminal
}

# Stock cannot be committed from these statuses (must go through verification)
STOCK_COMMIT_REQUIRES_VERIFICATION: Final = True

# --- Stock Status Values ---
STOCK_STATUS_HEALTHY: Final = "healthy"
STOCK_STATUS_LOW: Final = "low"
STOCK_STATUS_CRITICAL: Final = "critical"
STOCK_STATUS_OUT: Final = "out"

# --- UI Color Mapping ---
STOCK_STATUS_COLORS: Final = {
    STOCK_STATUS_HEALTHY: "#22C55E",    # Green
    STOCK_STATUS_LOW: "#F97316",         # Orange
    STOCK_STATUS_CRITICAL: "#EF4444",    # Red (same as out for urgency)
    STOCK_STATUS_OUT: "#EF4444",         # Red
    "pending_verification": "#3B82F6",   # Blue
    "pending_delivery": "#8B5CF6",       # Purple
}

# --- Reconciliation Thresholds ---
# Only flag out-of-sync when discrepancy exceeds this percentage of total delivered
SYNC_DISCREPANCY_THRESHOLD_PERCENT: Final = 0.05  # 5%
# Minimum absolute threshold (even at 5%, never flag less than 1 unit)
SYNC_DISCREPANCY_MIN_UNITS: Final = 1
