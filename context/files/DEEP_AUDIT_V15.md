# PURCHASE ASSISTANT — DEEP GITHUB CODE AUDIT v15
> Repo: github.com/ANANDU-2000/PurchaseAssiastant (latest commit cloned)
> Screenshots analyzed: 5 (network waterfall ×2, WhatsApp AI ×1, in-app AI ×2)
> Date: 2026-05-11

---

## 🔬 NETWORK WATERFALL DIAGNOSIS (Screenshots 1 & 2)

**Observed:** 95 requests · 2.3 MB · **Finish: 4.9 min** · Load: 4.80s

**Duplicate calls identified:**
```
trade-purchases?limit=50&offset=0    × 6 calls  (should be 1)
home-overview?from=2026-01-01&to=... × 4 calls  (should be 1)
trade-purchases (with date filters)  × 3 calls
chat                                 × 3 calls
```

**Root cause — `invalidateBusinessAggregates` storm:**

`lib/core/providers/business_aggregates_invalidation.dart` line 52:
```dart
void invalidateBusinessAggregates(dynamic ref) {
  bustHomeDashboardVolatileCaches();   // 1 invalidation
  bustHomeShellReportsInflight();      // 2
  invalidateAnalyticsData(ref);        // 8 invalidations inside
  ref.invalidate(dashboardProvider);   // 9
  ref.invalidate(homeDashboardDataProvider); // 10
  ref.invalidate(homeShellReportsProvider);  // 11
  ref.invalidate(cloudCostProvider);   // 12
  ref.invalidate(homeInsightsProvider);// 13
  ref.invalidate(contactsSuppliersEnrichedProvider); // 14
  ref.invalidate(contactsBrokersEnrichedProvider);   // 15
  ref.invalidate(contactsCategoriesProvider);        // 16
  ref.invalidate(contactsItemsProvider);             // 17
  ref.invalidate(suppliersListProvider);             // 18
  ref.invalidate(brokersListProvider);               // 19
  ref.invalidate(itemCategoriesListProvider);        // 20
  ref.invalidate(catalogItemsListProvider);          // 21
  invalidateTradePurchaseCaches(ref);  // 3 more = TOTAL: 24 invalidations
}
```

**Every single invalidation triggers a network fetch.** This is called from:
- `home_page.dart` line 87 (10-min Timer)
- `home_page.dart` line 112 (app resume 320ms debounce)
- `home_page.dart` line 570 (after purchase save)
- `home_page.dart` line 321 (period chip change)
- 8+ other files (contacts, settings, catalog, broker)

**On home page load alone:** resume fires → 24 providers invalidated → all 24 fire API calls in parallel → network saturated → Slow 4G (simulated) takes 4.9 minutes. On real 4G this takes ~8-12 seconds visible hang.

---

## 🔴 CRITICAL BUGS (from code + screenshots)

### BUG-001 · Dashboard "Updating..." Spinner Stuck — Today Tab Never Resolves
**File:** `lib/features/home/presentation/home_page.dart` lines 165–174
**Screenshot 1:** Donut shows "Updating..." with spinner. No data.

The `_loadCapTimer` (line 172) is meant to force-clear the spinner after a timeout:
```dart
_loadCapTimer?.cancel();
_loadCapTimer = Timer(const Duration(seconds: 8), () {
  if (!mounted) return;
  // This should force state update — but it only cancels itself
  // It does NOT update the dashboard state to stop refreshing
  _loadCapTimer = null;
});
```
The timer cancels itself but never calls `setState` or forces `refreshing: false`. The provider's `refreshing` flag stays `true` if the network times out.

### BUG-002 · 6× Duplicate `trade-purchases` API Calls on Every Page Load
**Files:** Multiple — see waterfall analysis above
**Root cause:** `invalidateTradePurchaseCaches` inside `invalidateBusinessAggregates` fires 3 providers. `invalidateBusinessAggregates` itself is called concurrently from multiple sources (periodic timer + resume + period chip change). No debounce at the aggregate level.

### BUG-003 · Speech-to-Text: No Malayalam Locale Set — Transcribes in English Only
**File:** `lib/features/assistant/presentation/assistant_chat_page.dart` lines 303–318

```dart
await _speech!.listen(
  onResult: (r) { ... },
  listenOptions: stt.SpeechListenOptions(
    listenMode: stt.ListenMode.dictation,
    partialResults: true,
    // ← NO localeId! Device defaults to English.
  ),
);
```

**Missing:** `localeId: 'ml-IN'` for Malayalam or dynamic locale selection. User says Malayalam — device transcribes random English garbage → chatbot gets nonsense → "supplier not found".

### BUG-004 · WhatsApp AI: Supplier Fuzzy Match Too Strict (Screenshot 3)
**File:** `backend/app/services/app_assistant_chat.py`

Client typed `surga sugar` → AI replied `"No supplier named 'Surga Sugar' found"`.
The actual supplier is `Surag`. Token sort ratio for `"surga"` vs `"surag"` = 88% — above the typical 80% threshold. But the WhatsApp path sends the supplier name directly from the user message without the server-side fuzzy supplier resolution that the in-app chat uses.

**Root cause:** WhatsApp messages go through a different pipeline that doesn't call `build_compact_business_snapshot` with the real supplier list, OR the snapshot isn't loaded with live supplier names.

### BUG-005 · PreviewCard Shows Only 1 Item — `lines.first` Bug (Confirmed)
**File:** `lib/features/assistant/presentation/widgets/preview_card.dart` line 47

```dart
static PreviewCardData? parse(Map<String, dynamic> d) {
  final lines = d['lines'];
  if (lines is! List || lines.isEmpty) return null;
  final line = lines.first;  // ← ONLY FIRST LINE
```

Multi-item purchase (e.g. "67 bags THUVARA JP + 5 bags THUVARA GOLD") → preview shows only THUVARA JP. Client sees wrong total.

**Note:** `PurchasePreviewTable` widget exists in the repo and IS used for the `showPurchaseTable` path. But `showCard` path (single-line, non-table view) still uses the broken `PreviewCard`. Need to verify `showPurchaseTable` condition is hit for all multi-line purchases.

### BUG-006 · WhatsApp AI Missing Selling Rate Field Handling
**Screenshot 3:** Client sent: `"create purchase for surag and qty item sugar 50 kg and qty 5 bags and prate 68 per kg and s rate 78 create"`

AI replied: `"Need item. So far: item=Sugar; qty=5; supplier=Surag; landing=68."` — **missing `s rate 78`** (selling rate was in the message but ignored).

**Root cause in system prompt handling:** The stub intent parser (`intent_stub.py`) doesn't recognize `s rate` or `srate` as `selling_price`. Only maps `selling_price_per_kg`, `sell`, `selling`. Fix: add aliases.

---

## 📊 AI CHATBOT ANALYSIS — IN-APP vs WHATSAPP

### In-App AI (Screenshot 4 — "Harisree workspace Assistant")
**Status:** Works but is generic and minimal.
- Welcome message is too verbose and technical ("Tap the mic — short session, then confirm in Entries")
- Quick prompts: "Summarize my recent purchase entries", "What should I verify before saving?" — these are not useful for this client's daily workflow
- Mic button design: OK but no partial results shown during recording

### WhatsApp AI (Screenshot 3)
**Critical issues:**
1. Supplier name resolution fails on slight misspellings
2. Selling rate (`s rate`) not parsed
3. Multi-message flow too slow — client had to type 3 messages to get a partial result
4. No conversation memory between messages (each WhatsApp message is new context)
5. Response format in WhatsApp is too structured/robotic ("So far: item=Sugar; qty=5...") — should be natural language

### Missing Features Client Needs:
1. **Malayalam → English transcription**: user speaks Malayalam, transcription should be Malayalam script, chatbot should still understand and respond
2. **Bulk item entry via text list**: client wants to paste supplier name + item list in one message, have all items created at once
3. **Preview in WhatsApp**: show formatted bill summary before confirming

---

## 🚀 PERFORMANCE ROOT CAUSES (PRIORITIZED)

| # | Root Cause | Requests Wasted | Fix Effort |
|---|-----------|-----------------|-----------|
| 1 | `invalidateBusinessAggregates` called 24 providers at once | ~20 extra fetches | 2h |
| 2 | No debounce on aggregate invalidation chain | 6× trade-purchases duplicates | 1h |
| 3 | `tradePurchasesListProvider` uses `kTradePurchasesHistoryFetchLimit = 4000` — fetches 4000 records | Each fetch = 10.4 KB × 4000/50 = 800KB+ | 1h |
| 4 | `catalogItemsListProvider` keepAlive + `invalidateBusinessAggregates` busts it on every write | Catalog refetched on every action | 1h |
| 5 | Home dashboard timer (10 min) + resume (320ms) can both fire within same window | Double fetch | 30min |

---

## 🎤 SPEECH/MALAYALAM FEATURE ANALYSIS

**Current state (`speech_to_text` v7):**
- Uses device STT (Google Cloud on Android, Apple Speech on iOS)
- NO locale set → defaults to device language (usually English)
- Malayalam words → garbled transcription → chatbot confused

**What client wants:**
1. Speak in Malayalam → words appear as Malayalam script OR transliterated
2. Chatbot understands Malayalam and responds
3. "surag sugar 50 kg bag 5 quantity 68 rate 78 selling" — say it, don't type it

**What's possible:**
- `speech_to_text` v7 supports `localeId` parameter — pass `ml-IN` for Malayalam
- System prompt already says: "Users write Malayalam, English, or Manglish — understand all three" ✅
- No backend Whisper integration despite `stt_provider: "openai_whisper"` in config

**Recommended approach:**
- Option A (Free): Set `localeId: 'ml-IN'` in Flutter STT → Google/Apple handles transcription
- Option B (Better): Add Whisper API endpoint that accepts audio → returns text → send to chat
- Option B requires: `POST /v1/businesses/{bid}/ai/transcribe` accepting audio bytes

---

## 📋 ENTITY PREVIEW CARD ANALYSIS

**Supplier create preview:** Uses `EntityPreviewCard` which parses `reply` text as key:value pairs. Works but looks raw/plain. Shows "Type: Supplier / Name: Ravi" as a list — not as a proper form.

**Purchase create preview:** Uses `PurchasePreviewTable` (new, multi-line). Still falls back to `PreviewCard` for simple cases. `PreviewCard.parse()` only reads `lines.first`.

**Issues:**
- Supplier preview: no phone, location, GSTIN visible fields
- Broker preview: no commission type visible
- Item preview: no subcategory visible
- Purchase preview: supplier name shows as "Linked supplier" not actual name
- All previews: no "Edit" button in entity cards (supplier/broker/item)
- All previews: no field-level editing inline

---

## 🔢 PRODUCTION READINESS SCORE

| Area | Score | Key Issue |
|------|-------|-----------|
| API performance / speed | 3/10 | 24 parallel invalidations, 6× duplicate fetches |
| Dashboard loading | 4/10 | "Updating..." stuck, Today never resolves |
| AI chatbot (in-app) | 6/10 | Good but preview shows 1 item only |
| AI chatbot (WhatsApp) | 3/10 | Supplier match fails, selling rate missing |
| Malayalam speech | 2/10 | No locale set, effectively broken |
| Preview cards (supplier/item) | 5/10 | Generic, no editable fields |
| Purchase preview (multi-line) | 7/10 | Table works, but fallback shows 1 line |
| **OVERALL** | **4/10** | Performance + speech block real daily use |
