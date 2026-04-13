# Owner-first purchase assistant — Phase 1 (implementation notes)

This document captures the **UX audit summary**, **data surfaces**, **WhatsApp assistant behavior**, and **shared reliability/security rules** implemented alongside the code. The canonical roadmap lives in your Cursor plan; this file is the shipped companion.

## 1. UX audit (navigation & surfaces)

| Area | Finding | Mitigation in code |
|------|---------|-------------------|
| Bottom nav | Four tabs + FAB is acceptable for owner workflow | **Catalog** label (was “Contacts”) clarifies suppliers/items/categories hub; FAB remains one-tap **New purchase**. |
| Purchase entry | Category repeated when catalog item already implies category | **Simple mode**: category row hidden when a catalog item is selected; category still sent from catalog. |
| WhatsApp | Users did not see where to chat | **Settings → WhatsApp assistant** shows server-configured assistant number (when `WHATSAPP_ASSISTANT_E164` or `AUTHKEY_FROM_NUMBER` is set) + instructions. |
| Reports | Already had date chips (Today, week, month, etc.) | No change required; KPI + tables remain owner-first. |

## 2. Purchase entry UX (simple vs advanced)

- **Simple (default)**: Item, catalog pick, qty/unit, purchase/landed basis, selling; optional PIP (`SmartPricePanel`). Landed line readout stays compact until **Advanced costs** is on.
- **Advanced costs**: Invoice, commission modes, transport, place; full landed breakdown.
- **Flow**: `Preview` → dialog → **Confirm & save** → `_previewToken` → save (matches backend preview token flow).
- **Duplicates**: Client `checkDuplicate` + server `find_duplicates` + `force_duplicate` — unchanged, documented here as single pipeline.

## 3. Owner hierarchy & catalog surfaces

- **Category → item → variant** remains; Contacts page titled **Catalog** with tabs Suppliers | Brokers | Categories | Items.
- Detail routes: `/supplier/:id`, `/broker/:id`, `/catalog/item/:id`, `/item-analytics/:name`, `/contacts/category`.

## 4. WhatsApp assistant (text + media placeholders)

**Text (production):**

- Linked user only (`find_user_by_chat_phone`).
- Draft entry: multiline `item/qty/unit/buy/land` → state `pending_confirm` → **YES/NO** — **no blind save**.
- Queries: TODAY, OVERVIEW/REPORT, BEST SUPPLIER, BEST \<item\>.
- Rate limits + quiet hours (IST) via Redis-backed guards.

**Voice / image / PDF:**

- Webhook processes **audio** and **image**/**document** messages with a clear fallback message (STT/OCR not wired in webhook path yet; app OCR/STT remains primary when enabled).
- Keeps compliance: no auto-save from media until parser + confirm pipeline exists.

## 5. Reliability, security, AI guardrails

- **Membership**: All entry writes go through authenticated routers + `persist_confirmed_entry`.
- **Preview token**: `entry_preview_token` ties confirm to preview.
- **Duplicates**: `find_duplicates` on confirm unless `force_duplicate`.
- **AI**: In-app `/ai` redirects home; assistant logic stays server-side; WhatsApp uses deterministic SQL summaries + structured draft parse — no LLM required for core flows.

## 6. Premium / performance

- Prefer **one primary scroll** per screen; entry sheet uses `ClampingScrollPhysics` on list.
- **Meaningful colors**: `HexaColors.profit` / `loss` / `costMuted` for totals.
- Charts: `fl_chart` wrapped per existing rules where used.

---

*Last updated with Phase 1 implementation.*
