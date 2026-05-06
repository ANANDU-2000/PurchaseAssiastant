# SPEC 11 — BROKER IMAGES & SUPABASE MCP DATA

> Reference: `@.cursor/00_AGENT_RULES.md` first

---

## STATUS


| Task                                     | Status     |
| ---------------------------------------- | ---------- |
| Find user ID from email                  | ❌ Not done |
| Find business ID                         | ❌ Not done |
| Add image_url column to brokers table    | ❌ Not done |
| Upload broker images to Supabase Storage | ❌ Not done |
| Link images to broker records            | ❌ Not done |
| Display broker image in detail page      | ❌ Not done |
| Display broker image in purchase detail  | ❌ Not done |


---

## INSTRUCTIONS FOR CURSOR (Supabase MCP)

Use Supabase MCP in Cursor. Connect to project before running queries.

### STEP 1: Find user and business ID

```sql
-- Run in Supabase SQL editor:

-- 1. Get user ID
SELECT id, email, created_at 
FROM auth.users 
WHERE email = 'pbsunil73@gmail.com';
-- Copy the UUID from result → call it USER_ID

-- 2. Get business ID
SELECT id, name, user_id 
FROM businesses 
WHERE user_id = 'USER_ID';
-- Copy the UUID → call it BUSINESS_ID
```

**Ask user to confirm:** "Found business: [name]. Is this correct? (yes/no)"

---

### STEP 2: Add image_url column if missing

```sql
-- Check if column exists:
SELECT column_name FROM information_schema.columns 
WHERE table_name = 'brokers' AND column_name = 'image_url';

-- If NOT exists, add it:
ALTER TABLE brokers ADD COLUMN IF NOT EXISTS image_url TEXT;
```

---

### STEP 3: List current brokers

```sql
SELECT id, name, phone 
FROM brokers 
WHERE business_id = 'BUSINESS_ID'
ORDER BY name;
```

Show this list to the user and ask which broker each image file belongs to.

---

### STEP 4: Create storage bucket for broker images

```sql
-- In Supabase Storage (via dashboard or MCP):
-- Bucket name: broker-images
-- Public: NO (authenticated only)
-- Allowed MIME types: image/jpeg, image/png, image/webp
```

Storage policy:

```sql
-- Allow authenticated users to read broker images:
CREATE POLICY "Authenticated read broker images"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'broker-images');

-- Allow service role to insert:
CREATE POLICY "Service insert broker images"
ON storage.objects FOR INSERT
TO service_role
WITH CHECK (bucket_id = 'broker-images');
```

---

### STEP 5: Upload images (via Supabase MCP or dashboard)

For each image file in the `data/` folder:

1. Upload to `broker-images/{BUSINESS_ID}/{broker_name}.jpg`
2. Get the public URL from Supabase Storage
3. Update the broker record:

```sql
UPDATE brokers 
SET image_url = 'https://YOUR_SUPABASE_URL/storage/v1/object/authenticated/broker-images/BUSINESS_ID/broker_name.jpg'
WHERE name = 'BROKER_NAME' 
AND business_id = 'BUSINESS_ID';
```

---

### STEP 6: Flutter — display broker image

**File:** `broker_detail_page.dart`

```dart
// In broker detail header:
Widget _buildBrokerAvatar(String? imageUrl, String name) {
  if (imageUrl != null && imageUrl.isNotEmpty) {
    return CircleAvatar(
      radius: 32,
      backgroundImage: NetworkImage(imageUrl),
      onBackgroundImageError: (_, __) {},
      child: null,
    );
  }
  // Fallback: initials
  final initials = name.split(' ').take(2).map((w) => w[0].toUpperCase()).join();
  return CircleAvatar(
    radius: 32,
    backgroundColor: const Color(0xFF1B6B5A),
    child: Text(
      initials,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
    ),
  );
}
```

**Also show broker avatar in purchase detail page next to broker name:**

```dart
Row(children: [
  _buildBrokerAvatar(brokerImageUrl, brokerName, radius: 16),
  const SizedBox(width: 8),
  Text('Broker: $brokerName'),
]),
```

---

### STEP 7: Include image_url in broker API response

**File:** `backend/app/routers/contacts.py` (or wherever brokers endpoint is)

Ensure the broker list/detail endpoints return `image_url` field:

```python
class BrokerOut(BaseModel):
    id: UUID
    name: str
    phone: str | None = None
    image_url: str | None = None   # ← Add this
    # ... other fields
```

In the query:

```python
select(Broker.id, Broker.name, Broker.phone, Broker.image_url, ...)
```

---

## VALIDATION

- `brokers` table has `image_url` column
- Broker images uploaded to Storage bucket
- Broker detail page shows photo (not just initials)
- Purchase detail shows broker avatar next to broker name
- API returns `image_url` in broker list response

