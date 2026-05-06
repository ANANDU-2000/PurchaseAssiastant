# 16 — SEED DATA (Brokers + Products + Suppliers)

> Use Supabase MCP in Cursor. `@.cursor/00_STATUS.md` first

---

## STATUS


| Task                                                                | Status     |
| ------------------------------------------------------------------- | ---------- |
| 32 brokers from `data/brokers_seed.json` (via seed script)            | ⚠️ Run `seed_catalog_and_suppliers` against target DB |
| Categories from `categories_seed.json` seeded                       | ⚠️ Same script (`data/files/`) |
| Products from `products_by_category_seed.json` seeded               | ⚠️ Same script |
| Suppliers from `suppliers_gst_seed.json` seeded                     | ⚠️ Same script |
| User ID found for [pbsunil73@gmail.com](mailto:pbsunil73@gmail.com) | ❌ Not done |
| Business ID found                                                   | ❌ Not done |


---

## STEP 1: Find user and business (run first, get IDs)

**In Cursor with Supabase MCP connected:**

```sql
-- Get user ID
SELECT id, email FROM auth.users 
WHERE email = 'pbsunil73@gmail.com';
-- Save result as: USER_ID = '<uuid>'

-- Get business ID
SELECT id, name FROM businesses 
WHERE user_id = 'USER_ID';
-- Save result as: BIZ_ID = '<uuid>'

-- Verify existing brokers (avoid duplicates)
SELECT id, name FROM brokers 
WHERE business_id = 'BIZ_ID' 
ORDER BY name;
```

---

## STEP 2: Seed 32 brokers

**Broker names** live in `data/brokers_seed.json` at the repo root. The Python seed (`run_catalog_suppliers_seed`) inserts any missing brokers for the business after catalog + suppliers (no duplicate names, case-insensitive).

**Option A: Supabase MCP SQL (direct):**

```sql
-- Insert brokers, skip if name already exists for this business
INSERT INTO brokers (id, business_id, name, created_at)
SELECT 
  gen_random_uuid(),
  'BIZ_ID',
  broker_name,
  NOW()
FROM (VALUES
  ('RICE & RICE'),
  ('EDISON'),
  ('NT TAJDEEN & ASSOCIATES'),
  ('RIYAS'),
  ('BABU THRISSUR'),
  ('SEBI'),
  ('N TEX'),
  ('GOODWILL ALAPPUZHA'),
  ('SWOSTHIK ALAPPUZHA'),
  ('VICTRA SUGAR AGENCY BANGALORE'),
  ('SUBRAHMANYAM SUGAR'),
  ('ERODE AGENCY'),
  ('C. C JOSEPH'),
  ('THANKACHAN'),
  ('PANKAJ'),
  ('RENJU'),
  ('RAPPAI'),
  ('P.D. JOSEPH'),
  ('KOCHIKKARAN'),
  ('COMMODITIES CANVASING'),
  ('NARAYANAN'),
  ('PASHA'),
  ('JOHNSON C.C'),
  ('THOMAS INDORE'),
  ('JOSHY'),
  ('NAVEEN KUMAR'),
  ('SWAMY'),
  ('NISHAD INDORE'),
  ('BABU PAUL'),
  ('TONY'),
  ('SHANMUGA CANVASERS'),
  ('ANAND')
) AS t(broker_name)
WHERE NOT EXISTS (
  SELECT 1 FROM brokers 
  WHERE business_id = 'BIZ_ID' 
  AND UPPER(name) = UPPER(broker_name)
);
```

**Option B: Backend seed script (catalog + types + items + GST suppliers + brokers):**

Uses `data/files/*.json` for catalog/suppliers. If present, also loads **`data/brokers_seed.json`** (or `brokers_seed.json` next to the seed dir) and inserts brokers missing for that business (name match, case-insensitive).

```bash
cd backend
set DATABASE_URL=postgresql://...
python -m scripts.seed_catalog_and_suppliers ^
  --seed-dir ../data/files/ ^
  --business-id BIZ_ID
```

Summary line includes `brokers +N skipped M`.

---

## STEP 3: Verify seed

```sql
-- Check brokers seeded:
SELECT COUNT(*) as broker_count FROM brokers WHERE business_id = 'BIZ_ID';
-- Expected: ≥32

-- Check catalog items:
SELECT COUNT(*) as item_count FROM catalog_items WHERE business_id = 'BIZ_ID';
-- Expected: ≥100

-- Check suppliers:
SELECT COUNT(*) as supplier_count FROM suppliers WHERE business_id = 'BIZ_ID';
-- Expected: ≥10
```

---

## STEP 4: Add `kkkk` broker (test broker from purchase history)

```sql
-- The broker "kkkk" appears in PUR-2026-0003,0004,0005
-- Check if exists:
SELECT id, name FROM brokers WHERE business_id = 'BIZ_ID' AND name = 'kkkk';
-- If not exists, it was auto-created — no action needed.
-- If it should be renamed, update:
UPDATE brokers SET name = 'KKKK' WHERE business_id = 'BIZ_ID' AND name = 'kkkk';
```

---

## STEP 5: Run bootstrap if needed

If the workspace is empty (no catalog), call the bootstrap endpoint:

```bash
curl -X POST https://YOUR_APP.onrender.com/v1/me/bootstrap-workspace \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"business_id": "BIZ_ID"}'
```

Or via the app: Settings → Workspace → Bootstrap / Re-seed catalog.

---

## STEP 6: Refresh Flutter providers after seed

After seeding, invalidate client-side caches:

```dart
// In Cursor terminal or via app Settings → Maintenance → Force refresh:
ref.invalidate(suppliersListProvider);
ref.invalidate(brokersListProvider);
ref.invalidate(catalogItemsProvider);
```

Or just pull-to-refresh on any list page.

---

## IMPORTANT: Duplicate prevention rules

Before inserting ANY broker/supplier/item, ALWAYS check:

```sql
-- Case-insensitive name match within same business:
SELECT id FROM brokers 
WHERE business_id = 'BIZ_ID' 
AND UPPER(TRIM(name)) = UPPER(TRIM('NEW_NAME'));
```

If result found → skip insert, return existing ID.

The backend `insert_broker_if_new` already does this — always use it instead of direct INSERT.

---

## VALIDATION

- `SELECT COUNT(*) FROM brokers WHERE business_id='BIZ_ID'` returns ≥32
- "RICE & RICE" appears in broker suggestion list in app
- "SUBRAHMANYAM SUGAR" appears in broker suggestions
- Typing "edi" in broker field shows "EDISON"
- No duplicate brokers (each name unique per business)
- Catalog items visible in item search during purchase entry

