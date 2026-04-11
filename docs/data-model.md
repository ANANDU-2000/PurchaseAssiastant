# Data Model — HEXA Purchase Assistant

## Conventions

- Primary keys: UUID v4.
- Timestamps: `created_at`, `updated_at` (UTC).
- Soft delete optional for entries: `deleted_at`.
- Multi-tenant: all business data scoped by `business_id`.

---

## Core Entities

### `users`

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| phone | VARCHAR | E.164, unique |
| name | VARCHAR | Optional |
| created_at | TIMESTAMPTZ | |

### `businesses`

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| name | VARCHAR | |
| default_currency | CHAR(3) | INR default |
| created_at | TIMESTAMPTZ | |

### `memberships`

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| user_id | UUID | FK → users |
| business_id | UUID | FK → businesses |
| role | ENUM | owner, staff |
| created_at | TIMESTAMPTZ | |

### `suppliers`

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| business_id | UUID | FK |
| name | VARCHAR | |
| phone | VARCHAR | Optional |
| location | TEXT | Optional |
| broker_id | UUID | Nullable FK → brokers |
| created_at | TIMESTAMPTZ | |

### `brokers`

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| business_id | UUID | FK |
| name | VARCHAR | |
| commission_type | ENUM | percent, fixed, per_unit |
| commission_value | DECIMAL | |
| created_at | TIMESTAMPTZ | |

### `item_catalog` (optional normalization)

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| business_id | UUID | FK |
| name | VARCHAR | |
| category | VARCHAR | Optional |
| default_base_unit | ENUM | kg, piece |
| created_at | TIMESTAMPTZ | |

### `item_unit_conversions`

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| item_id | UUID | FK → item_catalog or inline name hash |
| from_unit | ENUM | kg, box, piece |
| to_base_unit | ENUM | kg, piece |
| factor | DECIMAL | e.g. 1 box = 10 kg → factor 10 to kg base |

---

## Entries

### `entries` (header per purchase line or batch)

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| business_id | UUID | FK |
| user_id | UUID | FK — who created |
| supplier_id | UUID | Nullable FK |
| broker_id | UUID | Nullable FK |
| entry_date | DATE | Purchase date |
| invoice_no | VARCHAR | Optional |
| transport_cost | DECIMAL | Optional |
| commission_amount | DECIMAL | Computed or stored |
| source | ENUM | app, whatsapp, import |
| status | ENUM | draft, confirmed |
| created_at | TIMESTAMPTZ | |

### `entry_line_items`

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| entry_id | UUID | FK |
| item_name | VARCHAR | Denormalized ok for speed |
| category | VARCHAR | Optional |
| qty | DECIMAL | |
| unit | ENUM | kg, box, piece |
| qty_base | DECIMAL | Normalized qty for analytics |
| base_unit | ENUM | kg or piece |
| buy_price | DECIMAL | Price per stated unit or per kg — **define rule in API** |
| landing_cost | DECIMAL | **Manual input** — total or per unit per API contract |
| selling_price | DECIMAL | Nullable until known |
| currency | CHAR(3) | |
| metadata | JSONB | OCR confidence, raw parse |

**Profit (computed):**  
`profit = (selling_price - effective_landing_per_base) * qty_base` (exact formula fixed in service layer).

### `price_history` (materialized from line items for PIP)

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| business_id | UUID | |
| item_key | VARCHAR | Normalized item name or catalog id |
| observed_at | TIMESTAMPTZ | |
| unit_price_normalized | DECIMAL | Price per base unit for comparison |
| supplier_id | UUID | Nullable |
| entry_line_id | UUID | FK |

### `analytics_snapshots` (optional, for speed)

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| business_id | UUID | |
| period_type | ENUM | day, week, month |
| period_start | DATE | |
| json | JSONB | Precomputed KPIs |

---

## Platform & Admin

### `super_admins` (global)

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| user_id | UUID | FK → users |
| created_at | TIMESTAMPTZ | |

### `feature_flags`

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| business_id | UUID | FK nullable — null = global default |
| key | VARCHAR | ai_enabled, voice_enabled, ocr_enabled |
| value | BOOLEAN | |

### `audit_logs`

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| business_id | UUID | Nullable for admin actions |
| actor_user_id | UUID | |
| action | VARCHAR | |
| entity_type | VARCHAR | |
| entity_id | UUID | Nullable |
| payload | JSONB | Diff or snapshot |
| created_at | TIMESTAMPTZ | |

### `api_usage_logs`

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| business_id | UUID | Nullable |
| provider | VARCHAR | openai, dialog360, ocr, stt |
| units | DECIMAL | Tokens, messages, pages |
| cost_estimate | DECIMAL | Optional |
| created_at | TIMESTAMPTZ | |

### `subscriptions` (billing)

| Column | Type | Notes |
|--------|------|--------|
| id | UUID | PK |
| business_id | UUID | FK |
| plan | ENUM | basic, pro, premium |
| provider_subscription_id | VARCHAR | Razorpay etc. |
| status | ENUM | active, past_due, canceled |
| current_period_end | TIMESTAMPTZ | |

---

## Duplicate Detection Key

Index or query: `(business_id, normalized_item, entry_date, qty, qty_base)` — tune to product: **item + qty + date** per PRD.

---

## Redis Keys (Examples)

- `pip:{business_id}:{item_key}` — cached PIP payload, TTL 5–15 min.
- `session:{refresh_jti}` — refresh token metadata.
- `wa:state:{phone}` — WhatsApp conversation draft (short TTL).
