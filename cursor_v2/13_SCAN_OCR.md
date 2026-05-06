# 13 — SCAN PURCHASE BILL (OCR + AI PARSER)

> `@.cursor/00_STATUS.md` first

---

## STATUS


| Task                                                      | Status                                                          |
| --------------------------------------------------------- | --------------------------------------------------------------- |
| Camera + Gallery image picker                             | ✅ Done                                                          |
| Upload image to backend `/scan-purchase`                  | ✅ Done                                                          |
| OCR via Google Vision (when key set)                      | ✅ Done (configure server key to enable)                         |
| **OCR fallback reads raw JPEG bytes → shows JFIF binary** | ✅ Fixed                                                         |
| AI structured parse (supplier, broker, items, charges)    | ✅ Done (LLM + regex/heuristic fallback)                         |
| Supplier match against DB (no duplicates)                 | ✅ Done (server id match + UI linking + duplicate-risk warnings) |
| Broker field extraction + match                           | ✅ Done (server id match + UI linking + duplicate-risk warnings) |
| Delivery rate / billty / freight extraction               | ✅ Done (LLM + regex keywords incl. delhead/billty)              |
| Malayalam + Manglish word normalisation                   | ✅ Done (server-side normalization map)                          |
| Preview table (one viewport, no scroll)                   | ✅ Done (single-viewport layout, no horizontal scroll)           |
| Duplicate prevention before creating new entity           | ✅ Done (warnings + confirm gates)                               |
| Unit type detection from scan                             | ✅ Done (bag/sack/box/tin/piece + kg)                            |


---

## BUG C2: Raw JPEG bytes shown as "supplier name"

**File:** `backend/app/services/purchase_scan_service.py`

**Root cause:** `ocr_parser.normalize_scan_text(raw)` is called as fallback when Vision OCR is off.
`normalize_scan_text` receives raw JPEG bytes and does not know these are binary — it decodes them
as UTF-8 and returns garbage like `≡≡JFIF≡≡≡≡≡≡...`.

**Fix in `purchase_scan_service.py`:**

```python
# In scan_purchase_bill endpoint (me.py ~line 276):
text, conf = await pss.image_bytes_to_text(settings, raw)
if not text.strip():
    # BUGFIX: Do NOT pass raw bytes to normalize_scan_text — that's for text, not images
    # When OCR is off, return empty text with a clear message
    text = ""
    # Do NOT call: op.normalize_scan_text(raw)  ← this was the bug
```

**Then in `ocr_parser.normalize_scan_text`**, add a guard at the top:

```python
def normalize_scan_text(text: str | bytes) -> str:
    if isinstance(text, (bytes, bytearray)):
        # Safety: if raw bytes passed, try UTF-8 decode; if it looks like binary, discard
        try:
            decoded = text.decode("utf-8", errors="replace")
            if decoded.startswith("ÿØÿ") or "JFIF" in decoded[:20] or "Exif" in decoded[:20]:
                return ""  # Raw JPEG/image bytes — not text
            return decoded
        except Exception:
            return ""
    return text or ""
```

---

## USE GEMINI FREE / GROQ FREE FOR PARSING (no cost)

**File:** `backend/app/services/purchase_scan_service.py`

When Google Vision OCR is off, use **Gemini Vision** (free tier) to extract text AND parse:

```python
async def image_bytes_to_text_gemini_free(image_bytes: bytes) -> tuple[str, float]:
    """Uses Gemini 2.0 Flash (free) to extract text from bill image.
    Falls back to empty string if not configured.
    """
    import os
    api_key = os.getenv("GEMINI_API_KEY", "")
    if not api_key:
        return "", 0.0
    
    import base64
    b64 = base64.b64encode(image_bytes).decode()
    
    import httpx
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={api_key}"
    payload = {
        "contents": [{
            "parts": [
                {
                    "inline_data": {
                        "mime_type": "image/jpeg",
                        "data": b64
                    }
                },
                {
                    "text": (
                        "Extract all text from this purchase bill/handwritten note. "
                        "Preserve exact numbers, names, and spacing. "
                        "Output ONLY the raw extracted text, nothing else."
                    )
                }
            ]
        }],
        "generationConfig": {"temperature": 0, "maxOutputTokens": 1000}
    }
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            r = await client.post(url, json=payload)
            r.raise_for_status()
            data = r.json()
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        return text.strip(), 0.8
    except Exception as e:
        logger.warning("Gemini OCR failed: %s", e)
        return "", 0.0
```

**Update `image_bytes_to_text` to try Gemini when Vision key missing:**

```python
async def image_bytes_to_text(settings: Settings, image_bytes: bytes) -> tuple[str, float]:
    # Try Google Vision first
    if getattr(settings, "enable_ocr", False) and getattr(settings, "ocr_api_key", None):
        result = await _vision_ocr(settings, image_bytes)
        if result[0]:
            return result
    
    # Try Gemini free (GEMINI_API_KEY env var)
    result = await image_bytes_to_text_gemini_free(image_bytes)
    if result[0]:
        return result
    
    return "", 0.0
```

---

## AI PARSER: Structured purchase extraction

**File:** `backend/app/services/ocr_parser.py`

Replace the current regex-only parser with an AI-assisted parser using **Groq free** or **Gemini free**:

```python
async def extract_structured_purchase_from_text(
    text: str,
    catalog_items: list[dict],  # [{name, default_unit, kg_per_bag}]
    suppliers: list[dict],       # [{id, name}]
    brokers: list[dict],         # [{id, name}]
) -> dict:
    """
    Uses LLM to extract structured purchase data from OCR text.
    Falls back to regex if LLM unavailable.
    
    Supports:
    - Malayalam words (Suger, Sujar, Cheriyathara, etc.)
    - English/Manglish mix
    - Multiple items
    - Rates: P 56 / S 57 / purchase 56 / sell 57
    - Units: bag, kg, box, piece (and Malayalam equivalents)
    - Delivery charges: delivered, delhead, billty, freight
    """
    
    catalog_names = [i["name"] for i in catalog_items[:50]]  # limit context
    supplier_names = [s["name"] for s in suppliers[:30]]
    broker_names = [b["name"] for b in brokers[:30]]
    
    prompt = f"""You are a purchase bill parser for a South Indian commodity trading app.
Extract purchase data from this handwritten/scanned text.

Known catalog items: {', '.join(catalog_names)}
Known suppliers: {', '.join(supplier_names)}
Known brokers: {', '.join(broker_names)}

Rules:
- "Suger", "Sugar", "Sujar" → match to nearest catalog item
- "P 56" or "purchase 56" → purchase_rate = 56
- "S 57" or "sell 57" or "selling 57" → selling_rate = 57
- "50kg x 100 bag" → unit=bag, qty=100, kg_per_bag=50, total_kg=5000
- "5000kg" when item is "Sugar 50 KG" → qty=100 bags (5000÷50)
- "delivered 36" or "delhead 36" → delivered_rate=36
- "billty 18" → billty_rate=18
- "freight 500" → freight=500
- First line is usually supplier name
- Second line may be broker name
- Match names to known lists (fuzzy match); if no match, mark as "new"
- Malayalam words: Suger=Sugar, Rava=Sooji, Chakkarappetti=Sugar, Matta=Matta Rice

Return ONLY valid JSON, no explanation:
{{
  "supplier_name": "matched name or raw text",
  "supplier_match_id": "uuid or null if new",
  "supplier_is_new": true/false,
  "broker_name": "matched name or null",
  "broker_match_id": "uuid or null if new",
  "broker_is_new": true/false,
  "items": [
    {{
      "item_name_raw": "as written",
      "item_name_matched": "matched catalog name or raw",
      "item_match_id": "uuid or null",
      "item_is_new": true/false,
      "qty": 100,
      "unit": "bag",
      "kg_per_bag": 50,
      "total_kg": 5000,
      "purchase_rate": 56.0,
      "selling_rate": 57.0
    }}
  ],
  "delivered_rate": 36.0,
  "billty_rate": null,
  "freight": null,
  "payment_days": null,
  "confidence": 0.85
}}

Text to parse:
{text}"""

    # Try Groq free (llama-3.1-8b-instant is free)
    import os
    groq_key = os.getenv("GROQ_API_KEY", "")
    if groq_key:
        try:
            import httpx, json
            async with httpx.AsyncClient(timeout=20.0) as client:
                r = await client.post(
                    "https://api.groq.com/openai/v1/chat/completions",
                    headers={"Authorization": f"Bearer {groq_key}", "Content-Type": "application/json"},
                    json={
                        "model": "llama-3.1-8b-instant",
                        "messages": [{"role": "user", "content": prompt}],
                        "temperature": 0,
                        "response_format": {"type": "json_object"},
                    }
                )
                r.raise_for_status()
                raw = r.json()["choices"][0]["message"]["content"]
                return json.loads(raw)
        except Exception as e:
            logger.warning("Groq parse failed: %s", e)
    
    # Try Gemini free
    gemini_key = os.getenv("GEMINI_API_KEY", "")
    if gemini_key:
        try:
            import httpx, json
            async with httpx.AsyncClient(timeout=20.0) as client:
                r = await client.post(
                    f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={gemini_key}",
                    json={
                        "contents": [{"parts": [{"text": prompt}]}],
                        "generationConfig": {"temperature": 0, "responseMimeType": "application/json"}
                    }
                )
                r.raise_for_status()
                raw = r.json()["candidates"][0]["content"]["parts"][0]["text"]
                return json.loads(raw)
        except Exception as e:
            logger.warning("Gemini parse failed: %s", e)
    
    # Fallback: regex parser (existing logic)
    return _regex_parse_fallback(text, catalog_items, suppliers, brokers)
```

---

## DUPLICATE PREVENTION

**File:** `backend/app/routers/me.py` — in `scan_purchase_bill` endpoint

After parsing, check for near-duplicate names BEFORE flagging as new:

```python
from difflib import get_close_matches

def _fuzzy_match(name: str, names: list[str], cutoff: float = 0.7) -> str | None:
    """Returns best match name or None."""
    name_clean = name.strip().upper()
    names_upper = [n.upper() for n in names]
    matches = get_close_matches(name_clean, names_upper, n=1, cutoff=cutoff)
    if matches:
        idx = names_upper.index(matches[0])
        return names[idx]
    return None

# Usage in scan endpoint:
supplier_match = _fuzzy_match(parsed["supplier_name"], [s["name"] for s in suppliers])
if supplier_match:
    parsed["supplier_name"] = supplier_match
    parsed["supplier_is_new"] = False
```

---

## SCAN PAGE UI FIX — Preview table (full viewport, no scroll)

**File:** `lib/features/purchase/presentation/scan_purchase_page.dart`

After successful parse, show extracted data in a structured confirmation table:

```
┌─────────────────────────────────────────────────────┐
│ SCAN RESULT                          Confidence: 85% │
├─────────────────────────────────────────────────────┤
│ Supplier    [surag ✓]  or  [New: Surag +]           │
│ Broker      [kkkk ✓]   or  [New: kkkk +]            │
├─────────────────────────────────────────────────────┤
│ Item          Qty    Unit   P-Rate  S-Rate           │
│ Sugar 50 KG   100    bag    ₹56     ₹57              │
│  → 100 bags × 50 kg/bag = 5,000 kg                  │
├─────────────────────────────────────────────────────┤
│ Delivered rate: ₹36                                  │
├─────────────────────────────────────────────────────┤
│ [☑ I confirm all rows are correct]                  │
│ [← Edit]        [Use this data → New purchase]      │
└─────────────────────────────────────────────────────┘
```

**Rules:**

- Supplier/Broker show as GREEN chip if matched in DB, AMBER chip if new (auto-create on confirm)
- Each item row is tappable to edit inline
- Unit shows as "bag" with sub-text "50 kg/bag = 5,000 kg total"
- "Use this data" disabled until checkbox checked
- Tapping "New: Surag +" shows confirmation "Create new supplier 'Surag'? Yes / Match existing"

---

## MALAYALAM / MANGLISH WORD MAP

Add to `backend/app/services/ocr_parser.py`:

```python
# Malayalam commodity names → English catalog matches
MALAYALAM_TO_ENGLISH = {
    # Rice
    "arishi": "rice", "ari": "rice", "matta": "matta rice",
    "cherumani": "cherumani rice", "jaya": "jaya rice",
    # Sugar
    "suger": "sugar", "sujar": "sugar", "chakkarappetti": "sugar",
    "chakka": "sugar", "sharkkara": "sugar",
    # Pulses
    "payar": "cherupayar", "cherupayar": "cherupayar",
    "kadala": "kadala", "uzhunnu": "uzhunnu",
    "thuvara": "thuvara", "parippu": "masoor dall",
    # Spices
    "malli": "malli", "jeerakam": "jeerakam", "manjal": "manjal",
    "mulaku": "chilli", "chilli": "chilli", "uluva": "uluva",
    # Flour
    "rava": "maida atta sooji", "sooji": "maida atta sooji",
    "maida": "maida atta sooji", "atta": "wheat flour",
    "kadalamavu": "kadalamavu",
    # Other
    "ellu": "ellu", "kappalandi": "kappalandi",
    "avil": "avil", "bellam": "bellam",
}

def normalize_item_name(raw: str) -> str:
    """Normalise Malayalam/Manglish item names to catalog English names."""
    lower = raw.strip().lower()
    for mal, eng in MALAYALAM_TO_ENGLISH.items():
        if mal in lower:
            return eng.upper()
    return raw.strip().upper()
```

---

## VALIDATION

- Scan handwritten note → supplier field shows "surag" not JFIF binary
- Scan "Sugar 50kg x 100 Bag" → item shows 100 bags, 5000 kg, P:56, S:57
- Scan "delhead 36" → delivered_rate = 36 in parsed output
- "New supplier" auto-flagged → create on confirm, no duplicate
- Manglish "Suger" → matched to "SUGAR" in catalog
- Preview table fits in one viewport, no horizontal scroll
- "Use this data" disabled until confirmation checkbox ticked

