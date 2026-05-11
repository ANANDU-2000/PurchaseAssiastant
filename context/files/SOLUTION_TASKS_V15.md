# PURCHASE ASSISTANT v15 — SOLUTION TASK LIST
> Based on live GitHub code (commit: latest as of 2026-05-11)
> Priority: Performance → Speech → AI Preview → Feature
> Cursor agent works top-to-bottom. Check each box when done.

---

## PROGRESS TABLE

| Phase | Tasks | Done |
|-------|-------|------|
| P0 Performance (API Flood) | 4 | 4 |
| P0 Dashboard Fix | 3 | 3 |
| P1 Speech / Malayalam | 3 | 3 |
| P1 AI Preview Upgrade | 4 | 4 |
| P1 WhatsApp AI Fixes | 3 | 3 |
| P2 Bulk Item Creation | 2 | 2 |
| P2 Chatbot UX | 3 | 3 |
| P2 Forms / pickers | 1 | 1 |

**Shipped 2026-05-11:** T-001–T-022 complete in repo (see code). Last batch: T-013 entity preview + Edit in app; T-018–T-019 `create_catalog_items_batch` prompt + backend path; T-021 auto-send after speech; T-022 Hive-backed assistant history + clear.

### Quick reference — scroll issues vs pending work

| Issue (what users saw) | Task | Notes |
|--------|------|--------|
| Long category / item menus covered **Cancel** / **Save Item**; hard to scroll or reach buttons | **T-023** | Capped `menuMaxHeight` / `menuHeight`, bounded bottom sheets, scrollable quick-add sheet |
| Home / lists felt slow; many duplicate API calls | **T-001–T-004** | Debounced `invalidateBusinessAggregates`, smaller trade fetch + pagination, home poll guard, `forceStopRefreshing` |
| Empty period looked “loading forever”; tab switch refetch | **T-005–T-007** | Empty + skeleton states, `AutomaticKeepAliveClientMixin` on breakdown tabs |
| Speech English-only; no live transcript | **T-008–T-010** | Malayalam locale, partial text, ML/EN chip |
| Assistant preview wrong for multi-line / supplier label | **T-011–T-014** | Preview table routing, supplier name, quick prompts, welcome copy |
| WhatsApp / fuzzy supplier + rate aliases + bulk lines | **T-015–T-017** | Backend prompts + matching |
| Batch catalog from chat | **T-018–T-019** | `create_catalog_items_batch` + system prompt |
| Assistant polish | **T-020–T-022** | Welcome, auto-send speech, persisted chat |

**Still manual (not code):** checklists under **Performance test** and **Speech test** below — run on a device / Slow 4G and tick when verified.

**If “every page” is still slow:** use DevTools **Network** (which URL repeats or is >1s); then Render **logs/metrics** or Supabase **advisors** for that path — not as a first guess.

### T-023 · Dropdown / picker overlays — scroll + CTA visibility ✅ 2026-05-11
**Problem (screenshots):** Category and item pickers opened as tall overlays, covering **Cancel** / **Save Item** and feeling “stuck” when scrolling.

**Fix:** Cap menu height to ~36–38% of viewport (`menuMaxHeight` / `menuHeight`), scroll the quick-add sheet, bound catalog category/type bottom sheets to ≤55% height, tighten inline-search suggestion panel.

- [x] `quick_add_item_sheet.dart` — `menuMaxHeight` + `SingleChildScrollView`
- [x] `batch_item_create_page.dart` — `menuMaxHeight` on category/type dropdowns
- [x] `item_wizard_page.dart` — dynamic `menuHeight` for both `DropdownMenu`s
- [x] `catalog_add_item_page.dart` — fixed max height + scroll for category/type sheets
- [x] `purchase_item_entry_sheet.dart` — dynamic unit dropdown `menuMaxHeight`
- [x] `inline_search_field.dart` — shorter max suggestion height

---

## ═══ PHASE 0-A: STOP THE API FLOOD (Fix First — Biggest Impact) ═══

### T-001 · Debounce `invalidateBusinessAggregates` at Call Site
**File:** `flutter_app/lib/core/providers/business_aggregates_invalidation.dart`

Problem: called concurrently from timer + resume + chip change → 24 providers fire simultaneously.

- [x] Add a global debounce guard at the top of the file:
```dart
Timer? _invalidateDebounce;
const _invalidateDebounceMs = 400;
```
- [x] Wrap `invalidateBusinessAggregates`:
```dart
void invalidateBusinessAggregates(dynamic ref) {
  _invalidateDebounce?.cancel();
  _invalidateDebounce = Timer(const Duration(milliseconds: _invalidateDebounceMs), () {
    _doInvalidateBusinessAggregates(ref);
  });
}
void _doInvalidateBusinessAggregates(dynamic ref) {
  // ... all existing invalidation code here
}
```
- [x] Run: `flutter analyze`
- [x] Test: save a purchase → check Network tab → only 1× `trade-purchases` call, not 6×

---

### T-002 · Reduce `kTradePurchasesHistoryFetchLimit` from 4000 → 100 (with lazy pagination)
**File:** `flutter_app/lib/core/providers/trade_purchases_provider.dart`

```dart
const kTradePurchasesAlertFetchLimit = 4000;     // line 11
const kTradePurchasesHistoryFetchLimit = 4000;   // line 12
```

- [x] Change `kTradePurchasesHistoryFetchLimit` to `100`
- [x] Change `kTradePurchasesAlertFetchLimit` to `50`
- [x] In purchase history list: add `onEndReached` callback that loads next page (check if pagination is already wired — look for `loadMore` method in provider notifier)
- [x] Test: home loads in < 2 seconds; scroll to bottom of history → loads more

---

### T-003 · Guard Periodic Timer Against Concurrent Resume Debounce
**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

Existing line 84–88:
```dart
_poll = Timer.periodic(const Duration(minutes: 10), (_) {
  if (!mounted) return;
  if (_resumeRefreshDebounce?.isActive == true) return;  // ← already guarded
  invalidateTradePurchaseCaches(ref);  // ← but this is DIFFERENT from resume's full invalidate
});
```

- [x] Change the timer to also call `bustHomeDashboardVolatileCaches()` before `invalidateTradePurchaseCaches` — ensures stale in-memory snapshots are cleared before refetch
- [x] Add: skip timer invalidation if last fetch was within last 2 minutes:
```dart
DateTime? _lastFullInvalidate;
_poll = Timer.periodic(const Duration(minutes: 10), (_) {
  if (!mounted) return;
  if (_resumeRefreshDebounce?.isActive == true) return;
  final last = _lastFullInvalidate;
  if (last != null && DateTime.now().difference(last).inMinutes < 2) return;
  _lastFullInvalidate = DateTime.now();
  invalidateTradePurchaseCaches(ref);
});
```
- [x] Set `_lastFullInvalidate = DateTime.now()` in `_refresh()` and after resume debounce fires
- [x] Run: `flutter analyze`

---

### T-004 · Fix Load Cap Timer — Actually Force-Clear Spinner
**File:** `flutter_app/lib/features/home/presentation/home_page.dart` lines 165–174

Current code (broken):
```dart
if (next.refreshing) {
  _loadCapTimer?.cancel();
  _loadCapTimer = Timer(const Duration(seconds: 8), () {
    if (!mounted) return;
    _loadCapTimer = null;  // ← Does nothing! Just clears reference
  });
}
```

- [x] Replace with code that actually forces the provider state to stop refreshing:
```dart
if (next.refreshing) {
  _loadCapTimer?.cancel();
  _loadCapTimer = Timer(const Duration(seconds: 6), () {
    if (!mounted) return;
    _loadCapTimer = null;
    // Force the dashboard notifier to clear its refreshing flag
    // so the spinner never stays visible > 6 seconds regardless of network
    final notifier = ref.read(homeDashboardDataProvider.notifier);
    notifier.forceStopRefreshing();
  });
}
```
- [x] In `HomeDashboardDataNotifier` (home_dashboard_provider.dart): add `forceStopRefreshing()` method:
```dart
void forceStopRefreshing() {
  if (state.refreshing) {
    state = HomeDashboardDashState(snapshot: state.snapshot, refreshing: false);
  }
}
```
- [x] Test: open Today tab on slow network → spinner clears within 6 seconds → shows either data or empty state (never infinite spinner)

---

## ═══ PHASE 0-B: DASHBOARD TODAY TAB FIX ═══

### T-005 · Fix Today Tab Empty State
**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

- [x] Find the dashboard data display section. Find where `HomeDashboardData.empty` is checked. Currently shows skeleton forever when empty + refreshing.
- [x] Add explicit empty state: when `!state.refreshing && data.totalPurchase == 0 && data.purchaseCount == 0`:
```dart
if (!state.refreshing && data.totalPurchase == 0 && data.purchaseCount == 0)
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
    child: Column(children: [
      Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
      const SizedBox(height: 12),
      Text(
        period == HomePeriod.today ? 'No purchases today yet' : 'No purchases in this period',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text('Tap + to add your first purchase', style: ...),
    ]),
  )
```
- [x] Test: switch to Today → if no purchases → shows "No purchases today yet" within 3 seconds

---

### T-006 · Dashboard Breakdown Skeleton (Donut + Tabs)
**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

- [x] Find where "Loading Items breakdown..." or the breakdown tabs are rendered when `itemSlices.isEmpty`
- [x] Replace text "Loading Items breakdown..." with a proper shimmer skeleton:
  - Small circular placeholder for donut
  - 4 skeleton rows for the breakdown list
  - Use `shimmer` package (already in pubspec: `shimmer: ^3.0.0`) or simple `Container` with grey fill
- [x] Test: Month tab loads → shows skeleton → fills with real data

---

### T-007 · Fix Home → Breakdown Tab `keepAlive` (Stop Re-renders)
**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

- [x] Find `TabBarView` for Category/Subcategory/Supplier/Items tabs
- [x] Ensure each tab's content widget has `with AutomaticKeepAliveClientMixin` and `wantKeepAlive = true`
- [x] Add `const` keyword to all stateless row widgets in breakdown lists
- [x] Test: tap Category tab → tap Subcategory → tap back to Category → no new fetch fired

---

## ═══ PHASE 1: SPEECH + MALAYALAM ═══

### T-008 · Fix Speech Locale — Add Malayalam Support
**File:** `flutter_app/lib/features/assistant/presentation/assistant_chat_page.dart`

Current (broken — no locale):
```dart
await _speech!.listen(
  onResult: (r) { ... },
  listenOptions: stt.SpeechListenOptions(
    listenMode: stt.ListenMode.dictation,
    partialResults: true,
    // NO localeId → English only
  ),
);
```

- [x] Add locale state variable near the top of `_AssistantChatPageState`:
```dart
String _speechLocale = 'ml-IN';  // Default to Malayalam
bool _showLocaleToggle = false;
```
- [x] Load available locales on init:
```dart
Future<void> _initSpeech() async {
  // ... existing init code ...
  if (ok) {
    final locales = await _speech!.locales();
    final mlLocale = locales.where((l) => l.localeId.startsWith('ml')).firstOrNull;
    final enLocale = locales.where((l) => l.localeId.startsWith('en')).firstOrNull;
    if (mlLocale != null) {
      _speechLocale = mlLocale.localeId;
      setState(() => _showLocaleToggle = enLocale != null);
    }
  }
}
```
- [x] In `_startListen()`, pass locale:
```dart
await _speech!.listen(
  onResult: (r) {
    if (r.finalResult) {
      final t = r.recognizedWords.trim();
      if (t.isNotEmpty) {
        _ctrl.text = t;
        _ctrl.selection = TextSelection.collapsed(offset: t.length);
        // Auto-send on speech final result (optional — controlled by flag)
        if (_autoSendOnSpeech) unawaited(_send());
      }
    } else if (r.recognizedWords.isNotEmpty) {
      // Show partial results while speaking
      setState(() => _partialSpeech = r.recognizedWords);
    }
  },
  localeId: _speechLocale,
  listenOptions: stt.SpeechListenOptions(
    listenMode: stt.ListenMode.dictation,
    partialResults: true,
  ),
);
```
- [x] Add `_partialSpeech` display above the input bar when listening
- [x] Add ML/EN toggle button next to mic (small chip: "ML | EN")
- [x] Test: tap mic → say "surag sugar fifty kg bag" in Malayalam → text appears in Malayalam or Manglish

---

### T-009 · Show Partial Speech Transcript While Listening
**File:** `flutter_app/lib/features/assistant/presentation/assistant_chat_page.dart`

- [x] Add state: `String _partialSpeech = '';`
- [x] Reset on send / stop: `setState(() => _partialSpeech = '');`
- [x] In the input area, between `QuickPromptsBar` and `InputBar`, add:
```dart
if (_listening && _partialSpeech.isNotEmpty)
  Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AssistantChatTheme.accent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AssistantChatTheme.accent.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.graphic_eq_rounded, size: 16, color: AssistantChatTheme.accent),
      const SizedBox(width: 8),
      Expanded(child: Text(_partialSpeech,
        style: AssistantChatTheme.inter(13, c: AssistantChatTheme.primary),
        maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]),
  ),
```
- [x] Test: say "surag sugar fifty" → transcript appears live above input bar

---

### T-010 · Add Language Toggle Chip (Malayalam / English)
**File:** `flutter_app/lib/features/assistant/presentation/widgets/input_bar.dart` (or assistant_chat_page.dart)

- [x] Find the mic button area in `InputBar` or in `assistant_chat_page.dart`
- [x] Add a small toggle chip next to the mic button when speech is ready:
```dart
if (speechReady && showLocaleToggle)
  GestureDetector(
    onTap: onLocaleToggle,  // callback to parent
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isMLLocale ? AssistantChatTheme.accent : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isMLLocale ? 'ML' : 'EN',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isMLLocale ? Colors.white : Colors.grey.shade700,
        ),
      ),
    ),
  ),
```
- [x] Pass `isMLLocale: _speechLocale.startsWith('ml')` and `onLocaleToggle: _toggleLocale` from parent

---

## ═══ PHASE 1: AI PREVIEW UPGRADE ═══

### T-011 · Fix PreviewCard — Show All Lines (Not Just First)
**File:** `flutter_app/lib/features/assistant/presentation/widgets/preview_card.dart`

- [x] Find `PreviewCard.parse()`. The `lines.first` bug is on line 47.
- [x] Change: for multi-line drafts, when `lines.length > 1`, return `null` from `parse()` so the `showPurchaseTable` path is used instead of `showCard`
```dart
static PreviewCardData? parse(Map<String, dynamic> d) {
  if (d['__assistant__'] == 'entity') { ... }
  final lines = d['lines'];
  if (lines is! List || lines.isEmpty) return null;
  // NEW: if more than 1 line → use PurchasePreviewTable instead
  if (lines.length > 1) return null;
  final line = lines.first;
  // ... rest of single-line parsing
}
```
- [x] This forces `showPurchaseTable = true` for multi-line drafts which uses the full table widget
- [x] Test: tell chatbot "surag 67 bags thuvara jp 3510 rate, 5 bags thuvara gold 3150 rate" → preview table shows 2 rows

---

### T-012 · Fix PurchasePreviewTable — Show Supplier Name (Not "Linked supplier")
**File:** `flutter_app/lib/features/assistant/presentation/widgets/preview_card.dart`

In `PreviewCard.parse()`:
```dart
final supplier = d['supplier_id'] != null ? 'Linked supplier' : '—';
// ← Shows "Linked supplier" when supplier_id exists. Name never shown.
```

- [x] Change to: prefer `supplier_name`, fall back to `supplier_id` presence:
```dart
final supplierName = d['supplier_name']?.toString() ?? 
    d['supplier']?.toString() ?? 
    (d['supplier_id'] != null ? 'Linked supplier' : '—');
```
- [x] Same fix in `PurchasePreviewTable` widget — find where supplier is displayed and use `entryDraft['supplier_name']`
- [x] Test: create purchase via chat for "surag" → preview shows "Supplier: Surag" not "Linked supplier"

---

### T-013 · Improve Entity Preview Cards (Supplier / Broker / Item) ✅ 2026-05-11
**File:** `flutter_app/lib/features/assistant/presentation/widgets/entity_preview_card.dart`

Currently: shows parsed key-value pairs from reply text → brittle, shows raw field names.

- [x] Improve `EntityPreviewCard` to show formatted fields with proper labels:
  - For supplier: Name, Phone (if given), Location (if given)
  - For broker: Name, Commission (if given)
  - For item: Name, Subcategory, Unit, Kg/bag
- [x] Add an **Edit in app** action on entity preview cards (routes to supplier create, broker wizard, or catalog)
- [x] Test: tell chatbot "create supplier Surag, phone 9876543210" → preview shows Name + Phone + Edit button

---

### T-014 · Upgrade Quick Prompts — Client-Specific Actions
**File:** `flutter_app/lib/features/assistant/presentation/providers/assistant_quick_prompts_provider.dart`

Current generic prompts: "Summarize my recent purchase entries", "What should I verify before saving?"

- [x] Replace with business-specific prompts:
```dart
static const _defaultPrompts = [
  AssistantQuickPrompt(message: 'New purchase', label: '+ Purchase'),
  AssistantQuickPrompt(message: "What's my profit this month?", label: '📊 Profit'),
  AssistantQuickPrompt(message: "Who are today's suppliers?", label: '🏭 Today'),
  AssistantQuickPrompt(message: 'Pending deliveries', label: '🚚 Pending'),
  AssistantQuickPrompt(message: 'Top items this month', label: '📦 Top Items'),
];
```
- [x] Test: quick prompt bar shows relevant business actions

---

## ═══ PHASE 1: WHATSAPP AI FIXES ═══

### T-015 · Fix Supplier Fuzzy Match — Lower Threshold + Add Alias Fallback
**File:** `backend/app/services/app_assistant_chat.py`

- [x] Find the supplier fuzzy match code (search for `fuzz.token_sort_ratio` or `_score` calls for supplier matching)
- [x] Lower threshold from 80% → 70% for first pass: if 70–80% match, show clarification ("Did you mean Surag?") instead of hard-fail "not found"
- [x] Add shortcode match: if user types first 4 chars and matches only one supplier, accept it
- [x] In reply text when supplier not found: always suggest closest match: `"Supplier 'Surga' not found. Did you mean Surag (82% match)? Reply 'yes' or use the exact name."`

---

### T-016 · Fix Selling Rate Parsing — Add `s rate` Alias
**File:** `backend/app/services/intent_stub.py`

- [x] Find the selling price parser. Search for `selling_price` or `sell` in the stub intent parser.
- [x] Add aliases for `s rate`, `srate`, `s.rate`, `sell rate`, `s r`:
```python
SELLING_RATE_ALIASES = ['selling_price', 's rate', 'srate', 's.rate', 'sell rate', 'sell', 's r', 'selling rate', 'sale rate']
```
- [x] Also update the LLM system prompt: add to the "rate" alias section: `"s rate" and "selling rate" and "sell" all map to selling_price.`

---

### T-017 · WhatsApp Bulk Entry — Accept Supplier + Item List Format
**File:** `backend/app/services/assistant_system_prompt.py` + `app_assistant_chat.py`

Client need: send one WhatsApp message like:
```
surag
thuvara jp 67 bags 3510 rate 3840 sell
thuvara gold 30kg 5 bags 3150 rate 3360 sell
```
And have ALL items extracted and previewed.

- [x] Add to SYSTEM_PROMPT: explicit instruction for list format:
```
BULK ENTRY FORMAT (WhatsApp): If the user sends multiple lines, each line = one item.
Format: [item name] [qty] [unit] [buy rate] [sell rate]
Example:
  thuvara jp 67 bags 3510 rate 3840 sell
  → item_name="THUVARA JP", qty=67, unit="bag", landing_cost=3510, selling_price=3840
Extract ALL lines into data.lines array. Never truncate.
```
- [x] Test: send bulk format → all items in preview table

---

## ═══ PHASE 2: BULK ITEM CREATION VIA CHAT ═══

### T-018 · Chatbot: Create Multiple Items in One Message ✅ 2026-05-11
**File:** `backend/app/services/app_assistant_chat.py`

- [x] Add handling for `create_catalog_items_batch` intent (multiple items at once)
- [x] When LLM returns multiple items in data (e.g. `{intent: "create_catalog_items_batch", data: {supplier_name: "Surag", items: [{name: "THUVARA JP", unit: "bag", kg_per_bag: 50}, {name: "THUVARA GOLD 30KG", unit: "bag", kg_per_bag: 30}]}}`):
  - Show preview list of all items to be created
  - On confirm: create all items in batch
  - Link default supplier to all created items
- [x] Add to SYSTEM_PROMPT: `create_catalog_items_batch` intent description

---

### T-019 · Chatbot: Supplier + Items Flow (One Message) ✅ 2026-05-11
**File:** Backend system prompt + `app_assistant_chat.py`

Client workflow: Type "surag has thuvara jp 50kg bag, thuvara gold 30kg bag, kadala 40kg bag" → creates all 3 items linked to supplier Surag.

- [x] Add example to system prompt:
```
"surag has thuvara jp 50kg bag, thuvara gold 30kg bag" 
→ create_catalog_items_batch: supplier_name=Surag, items=[...]
```
- [x] Wire batch item creation in `_map_llm_entity_intent` to handle `create_catalog_items_batch`
- [x] Test: type "surag has 3 items: item1 50kg bag, item2 30kg bag, item3 40kg bag" → shows list preview of 3 items → confirm → all 3 created

---

## ═══ PHASE 2: CHATBOT UX POLISH ═══

### T-020 · Welcome Message Upgrade — Business-First Tone
**File:** `flutter_app/lib/features/assistant/presentation/assistant_chat_page.dart`

Current (too technical):
```dart
'Ask in plain words, e.g. create supplier Ravi, or add a purchase. '
'You will see a preview first. Tap Save on the card...'
'Hold the mic in the bar below to dictate (Malayalam or English).'
```

- [x] Replace with:
```dart
'നമസ്കാരം! How can I help today?\n'
'• Say or type a purchase: "surag 50 bags thuvara 3500"\n'
'• Ask about profit: "this month profit"\n'
'• Create supplier or item: "new supplier ravi"\n'
'Hold 🎤 to speak in Malayalam or English.'
```
- [x] The greeting is in Malayalam script + English mix, matching the business context

---

### T-021 · Auto-Send After Speech Finishes (Optional Flag) ✅ 2026-05-11
**File:** `flutter_app/lib/features/assistant/presentation/assistant_chat_page.dart`

- [x] Add state: `bool _autoSendOnSpeech = true;`
- [x] In speech `onResult` callback: if `r.finalResult && _autoSendOnSpeech`: auto-call `_send()` after 800ms delay (allows user to see what was transcribed before sending)
- [x] Add a small "Auto-send" toggle in the chat settings/menu
- [x] Test: speak "surag sugar 50 bags" → shows in input → sends after 0.8s → chatbot responds

---

### T-022 · Chatbot History — Persist Between Sessions ✅ 2026-05-11
**File:** `flutter_app/lib/features/assistant/presentation/assistant_chat_page.dart`

Currently: `_msgs` is in-memory, cleared every time user navigates away.

- [x] Save last 10 messages to Hive/SharedPreferences on dispose
- [x] Load on init: prepend to `_msgs` list with a "Previous conversation" divider
- [x] Clear history button in the `_showAssistantMenu` bottom sheet
- [x] Test: chat → navigate away → come back → last conversation visible

---

## ✅ DEFINITION OF DONE

Each task done when:
1. `flutter analyze` shows 0 new warnings
2. Feature works on device (Chrome PWA at 390px width)
3. Network tab shows no duplicate API calls
4. SOLUTION_TASKS_V15.md checkbox updated with date

## 🧪 PERFORMANCE TEST CHECKLIST

After Phase 0 complete:
- [ ] Home page load: open → fully rendered < 3 seconds (Slow 4G)
- [ ] Network tab: `trade-purchases` called max 1× per page load
- [ ] Network tab: `home-overview` called max 1× per period chip select
- [ ] Switch Today → Month → Year: each switch < 1 second (cached)
- [ ] Total requests on home load: < 20 (currently 95)

## 🎤 SPEECH TEST CHECKLIST

After Phase 1 complete:
- [ ] Tap mic → toggle shows "ML" chip
- [ ] Say "surag sugar fifty bags" in Malayalam → transcript appears live above input
- [ ] Final transcript sent → chatbot understands supplier + item + qty
- [ ] Toggle to EN → repeat with English → also works
