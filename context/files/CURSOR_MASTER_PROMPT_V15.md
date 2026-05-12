# CURSOR AGENT MASTER PROMPT — Purchase Assistant v15
> REPO: github.com/ANANDU-2000/PurchaseAssiastant (latest)
> ONE-SHOT: Paste ENTIRE file into Cursor Composer → Agent mode.
> Model: claude-sonnet-4. Mode: AGENT (not Ask or Edit).
> Works phase by phase. Updates SOLUTION_TASKS_V15.md after each task.

---

## IDENTITY & RULES

You are a senior Flutter/Dart + FastAPI engineer for the **Harisree Purchase Assistant** — a live production app for a Kerala wholesale grocery trading business. This is a real client. Precision matters.

**Stack:** Flutter 3.x · Dart 3.3 · Riverpod 2.6 · GoRouter 14 · speech_to_text ^7.0.0 · FastAPI (Python) · PostgreSQL (Supabase)

**ABSOLUTE RULES:**
1. ✅ After EVERY task: update checkbox in `SOLUTION_TASKS_V15.md` (add ✅ YYYY-MM-DD)
2. ✅ After EVERY file change: run `flutter analyze` in `flutter_app/`, fix all new errors
3. ❌ NEVER modify `*_test.dart` files
4. ❌ NEVER add `print()` statements
5. ❌ NEVER add new pubspec packages without explicit instruction here
6. ✅ Read `DEEP_AUDIT_V15.md` first for full context
7. ✅ Backend changes go in `backend/app/`, Flutter changes in `flutter_app/lib/`

---

## ════════════════════════════════════
## PHASE 0-A: STOP THE API FLOOD
## Priority: HIGHEST — fixes the 4.9 min load time visible in screenshots
## ════════════════════════════════════

### TASK 0-A-1: Debounce `invalidateBusinessAggregates`

**File:** `flutter_app/lib/core/providers/business_aggregates_invalidation.dart`

This function currently fires 24 provider invalidations simultaneously. When called from multiple sources (timer + resume + chip change), the network gets flooded with 6× duplicate API calls.

Step 1 — Add debounce at the top of the file (after imports, before any functions):
```dart
// Debounce guard: prevent stampede when called from multiple sources within 400ms.
Timer? _businessAggregateDebounce;
```

Step 2 — Rename the existing `invalidateBusinessAggregates` to `_doInvalidateBusinessAggregates`.

Step 3 — Create new `invalidateBusinessAggregates` wrapper:
```dart
/// Debounced wrapper around [_doInvalidateBusinessAggregates].
/// Safe to call from multiple sources; only fires once per 400ms window.
void invalidateBusinessAggregates(dynamic ref) {
  _businessAggregateDebounce?.cancel();
  _businessAggregateDebounce = Timer(const Duration(milliseconds: 400), () {
    _businessAggregateDebounce = null;
    _doInvalidateBusinessAggregates(ref);
  });
}
```

Step 4 — Make sure `import 'dart:async';` is at the top of the file (check — it may already be there).

Step 5 — Run: `flutter analyze`

Update SOLUTION_TASKS_V15.md: T-001 ✅

---

### TASK 0-A-2: Reduce Initial Purchase Fetch Limit

**File:** `flutter_app/lib/core/providers/trade_purchases_provider.dart`

Find:
```dart
const kTradePurchasesAlertFetchLimit = 4000;
const kTradePurchasesHistoryFetchLimit = 4000;
```

Change to:
```dart
const kTradePurchasesAlertFetchLimit = 50;
const kTradePurchasesHistoryFetchLimit = 100;
```

These 4000-record limits cause massive data transfers on every invalidation (10.4 KB per 50 records × 80 pages = 800 KB per list fetch). The history list has pagination — use it.

Run: `flutter analyze`

Update SOLUTION_TASKS_V15.md: T-002 ✅

---

### TASK 0-A-3: Add Last-Fetch Guard to Periodic Timer

**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

Find the `_HomePageState` class. Find the `_poll` timer setup (search for `Timer.periodic`).

Step 1 — Add state variable near other timer declarations:
```dart
DateTime? _lastFullRefreshAt;
```

Step 2 — Find `_refresh()` method. At the START of the method, add:
```dart
_lastFullRefreshAt = DateTime.now();
```

Step 3 — Find the `didChangeAppLifecycleState` handler. After `_resumeRefreshDebounce = Timer(...)` fires, set:
```dart
_resumeRefreshDebounce = Timer(const Duration(milliseconds: 320), () {
  if (!mounted) return;
  _lastFullRefreshAt = DateTime.now();  // ADD THIS LINE
  ref.invalidate(homeDashboardDataProvider);
  // ... rest of existing code
});
```

Step 4 — Find the `Timer.periodic` handler. Change it to:
```dart
_poll = Timer.periodic(const Duration(minutes: 10), (_) {
  if (!mounted) return;
  if (_resumeRefreshDebounce?.isActive == true) return;
  // Skip if a full refresh happened within the last 2 minutes
  final last = _lastFullRefreshAt;
  if (last != null && DateTime.now().difference(last).inMinutes < 2) return;
  _lastFullRefreshAt = DateTime.now();
  invalidateTradePurchaseCaches(ref);
});
```

Run: `flutter analyze`

Update SOLUTION_TASKS_V15.md: T-003 ✅

---

### TASK 0-A-4: Fix Load Cap Timer — Actually Stop the Spinner

**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

Find the `_loadCapTimer` usage (search for `_loadCapTimer`). Currently it just sets itself to null without updating state.

Step 1 — In `HomeDashboardDataNotifier` class (file: `flutter_app/lib/core/providers/home_dashboard_provider.dart`), add this public method at the end of the class:
```dart
/// Safety valve: force-clear the refreshing flag after a timeout.
/// Called by the UI if the spinner would run > 6 seconds.
void forceStopRefreshing() {
  if (!_dead && state.refreshing) {
    state = HomeDashboardDashState(
      snapshot: state.snapshot,
      refreshing: false,
    );
  }
}
```

Step 2 — Back in `home_page.dart`, find where `_loadCapTimer` is set. Replace the timer body:
```dart
// Find this (broken):
_loadCapTimer = Timer(const Duration(seconds: 8), () {
  if (!mounted) return;
  _loadCapTimer = null;
});

// Replace with (fixed):
_loadCapTimer = Timer(const Duration(seconds: 6), () {
  if (!mounted) return;
  _loadCapTimer = null;
  // Force-clear the spinner if still stuck after 6s
  ref.read(homeDashboardDataProvider.notifier).forceStopRefreshing();
});
```

Run: `flutter analyze`

Update SOLUTION_TASKS_V15.md: T-004 ✅

---

## ════════════════════════════════════
## PHASE 0-B: DASHBOARD UI FIXES
## ════════════════════════════════════

### TASK 0-B-1: Fix Empty State for Today / No-Data Periods

**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

Find where the dashboard data is rendered in the `build()` method. Find the section that handles the donut/ring chart or "Loading Items breakdown..." text.

After the main stats area (total amount, unit counts), before the breakdown tabs, add empty state handling:

```dart
// Find the breakdown section. If it currently looks like:
//   if (data.itemSlices.isEmpty)
//     const Center(child: Text('Loading Items breakdown...'))

// Replace with:
if (!state.refreshing && data.totalPurchase == 0 && data.purchaseCount == 0)
  Padding(
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
    child: Column(
      children: [
        Icon(Icons.receipt_long_outlined, size: 52, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(
          _currentPeriodEmptyLabel(period),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Tap + to record your first purchase',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade400),
        ),
      ],
    ),
  )
else if (data.itemSlices.isEmpty && state.refreshing)
  // Show shimmer rows instead of "Loading..." text
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Column(
      children: List.generate(4, (_) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      )),
    ),
  ),
```

Add helper method:
```dart
String _currentPeriodEmptyLabel(HomePeriod period) {
  return switch (period) {
    HomePeriod.today => 'No purchases today',
    HomePeriod.week => 'No purchases this week',
    HomePeriod.month => 'No purchases this month',
    HomePeriod.year => 'No purchases this year',
    HomePeriod.custom => 'No purchases in this period',
  };
}
```

Run: `flutter analyze`

Update SOLUTION_TASKS_V15.md: T-005 ✅

---

### TASK 0-B-2: Tab KeepAlive — Prevent Re-renders on Tab Switch

**File:** `flutter_app/lib/features/home/presentation/home_page.dart`

Find the `TabBarView` that renders the 4 breakdown tabs (Category, Subcategory, Supplier, Items).

For each tab child widget: if they are inline built (not separate classes), extract them into separate `StatefulWidget` classes with `AutomaticKeepAliveClientMixin`:

```dart
class _CategoryBreakdownTab extends StatefulWidget {
  const _CategoryBreakdownTab({required this.data, required this.refreshing});
  final HomeDashboardData data;
  final bool refreshing;
  @override
  State<_CategoryBreakdownTab> createState() => _CategoryBreakdownTabState();
}

class _CategoryBreakdownTabState extends State<_CategoryBreakdownTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required for mixin
    // Move the existing tab content here
    // ...
  }
}
```

Create the same pattern for Subcategory, Supplier, and Items tabs.

Replace inline tab content in `TabBarView` with:
```dart
TabBarView(
  controller: _tabController,
  children: [
    _CategoryBreakdownTab(data: data, refreshing: state.refreshing),
    _SubcategoryBreakdownTab(data: data, refreshing: state.refreshing),
    _SupplierBreakdownTab(data: data, refreshing: state.refreshing),
    _ItemsBreakdownTab(data: data, refreshing: state.refreshing),
  ],
),
```

Run: `flutter analyze`

Update SOLUTION_TASKS_V15.md: T-007 ✅

---

## ════════════════════════════════════
## PHASE 1: SPEECH + MALAYALAM SUPPORT
## Priority: HIGH — client's #1 workflow request
## ════════════════════════════════════

### TASK 1-A: Add Malayalam Locale to Speech Recognition

**File:** `flutter_app/lib/features/assistant/presentation/assistant_chat_page.dart`

Step 1 — Add state variables near `_listening` declaration:
```dart
String _speechLocale = 'ml-IN';
bool _showLocaleToggle = false;
String _partialSpeech = '';
```

Step 2 — In `_initSpeech()`, after `setState(() => _speechOn = ok)`:
```dart
if (ok) {
  try {
    final locales = await _speech!.locales();
    // Find Malayalam locale
    final mlLocale = locales.where((l) => l.localeId.contains('ml')).firstOrNull;
    // Find English India locale
    final enLocale = locales.where((l) =>
      l.localeId.contains('en-IN') || l.localeId.contains('en_IN')
    ).firstOrNull;
    if (mlLocale != null && mounted) {
      setState(() {
        _speechLocale = mlLocale.localeId;
        _showLocaleToggle = enLocale != null;
      });
    }
  } catch (_) {
    // Locale detection failed — keep default
  }
}
```

Step 3 — In `_startListen()`, update the `listen()` call:
```dart
await _speech!.listen(
  onResult: (r) {
    if (!mounted) return;
    if (r.finalResult) {
      final t = r.recognizedWords.trim();
      if (t.isNotEmpty) {
        setState(() {
          _ctrl.text = t;
          _ctrl.selection = TextSelection.collapsed(offset: t.length);
          _partialSpeech = '';
        });
      } else {
        setState(() => _partialSpeech = '');
      }
    } else {
      // Show partial results while speaking
      setState(() => _partialSpeech = r.recognizedWords.trim());
    }
  },
  localeId: _speechLocale,  // ← THE FIX: pass ML or EN locale
  listenOptions: stt.SpeechListenOptions(
    listenMode: stt.ListenMode.dictation,
    partialResults: true,
  ),
);
```

Step 4 — In `_stopListen()`, add:
```dart
Future<void> _stopListen() async {
  if (_speech == null) return;
  await _speech!.stop();
  if (mounted) setState(() {
    _listening = false;
    _partialSpeech = '';
  });
}
```

Step 5 — Add locale toggle method:
```dart
void _toggleLocale() {
  setState(() {
    _speechLocale = _speechLocale.startsWith('ml') ? 'en-IN' : 'ml-IN';
  });
}
```

Run: `flutter analyze`

Update SOLUTION_TASKS_V15.md: T-008 ✅

---

### TASK 1-B: Show Partial Speech Transcript

**File:** `flutter_app/lib/features/assistant/presentation/assistant_chat_page.dart`

Find the `AnimatedPadding` widget near the bottom of `build()` that wraps `Column > [QuickPromptsBar, InputBar]`.

Insert the partial transcript widget BETWEEN `QuickPromptsBar` and `InputBar`:
```dart
AnimatedPadding(
  // ...existing wrapper...
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      QuickPromptsBar(onPrompt: _onQuickPrompt),
      // ADD: partial speech display
      if (_listening && _partialSpeech.isNotEmpty)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF075E54).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF075E54).withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.graphic_eq_rounded,
                size: 16, color: Color(0xFF075E54)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _partialSpeech,
                  style: AssistantChatTheme.inter(13,
                    c: const Color(0xFF111B21)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      InputBar(
        controller: _ctrl,
        // ...existing InputBar params...
      ),
    ],
  ),
),
```

Run: `flutter analyze`

Update SOLUTION_TASKS_V15.md: T-009 ✅

---

### TASK 1-C: Add ML/EN Toggle Next to Mic Button

**File:** `flutter_app/lib/features/assistant/presentation/widgets/input_bar.dart`

Find `InputBar` widget constructor. Add new parameters:
```dart
class InputBar extends StatelessWidget {
  const InputBar({
    // ... existing params ...
    this.speechLocaleLabel = 'ML',     // NEW
    this.showLocaleToggle = false,      // NEW
    this.onLocaleToggle,               // NEW
    super.key,
  });

  final String speechLocaleLabel;
  final bool showLocaleToggle;
  final VoidCallback? onLocaleToggle;
```

Find where the mic button is rendered inside `InputBar`. Add the locale toggle chip next to it (BEFORE the mic button):
```dart
// ADD before mic IconButton:
if (showLocaleToggle && speechReady)
  GestureDetector(
    onTap: onLocaleToggle,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: speechLocaleLabel == 'ML'
            ? const Color(0xFF075E54)
            : const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        speechLocaleLabel,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: speechLocaleLabel == 'ML' ? Colors.white : Colors.grey.shade700,
        ),
      ),
    ),
  ),
```

Back in `assistant_chat_page.dart`, update `InputBar` usage to pass new params:
```dart
InputBar(
  controller: _ctrl,
  focusNode: _inputFocus,
  onSend: _send,
  loading: _loading,
  speechReady: _speechOn,
  listening: _listening,
  onMicDown: _startListen,
  onMicUp: _stopListen,
  replySnippet: _replySnippet,
  onDismissReply: () => setState(() => _replySnippet = null),
  // NEW:
  speechLocaleLabel: _speechLocale.startsWith('ml') ? 'ML' : 'EN',
  showLocaleToggle: _showLocaleToggle,
  onLocaleToggle: _toggleLocale,
),
```

Run: `flutter analyze`

Update SOLUTION_TASKS_V15.md: T-010 ✅

---

## ════════════════════════════════════
## PHASE 1: AI PREVIEW UPGRADE
## ════════════════════════════════════

### TASK 1-D: Fix PreviewCard — Route Multi-Line Drafts to Table

**File:** `flutter_app/lib/features/assistant/presentation/widgets/preview_card.dart`

Find `PreviewCard.parse()`. After the entity check, before single-line parsing, add:
```dart
static PreviewCardData? parse(Map<String, dynamic> d) {
  if (d['__assistant__'] == 'entity') {
    return const PreviewCardData(
      item: 'New record',
      // ... rest of entity case unchanged
    );
  }
  final lines = d['lines'];
  if (lines is! List || lines.isEmpty) return null;
  // NEW: if more than 1 line, return null so PurchasePreviewTable is used
  if (lines.length > 1) return null;
  // Single-line case only from here:
  final line = lines.first;
  // ... rest unchanged
}
```

This is a minimal 2-line fix that routes all multi-item purchases to `PurchasePreviewTable` automatically.

Run: `flutter analyze`

Update SOLUTION_TASKS_V15.md: T-011 ✅

---

### TASK 1-E: Fix Supplier Name in PreviewCard

**File:** `flutter_app/lib/features/assistant/presentation/widgets/preview_card.dart`

In `PreviewCard.parse()`, find:
```dart
final supplier = d['supplier_id'] != null ? 'Linked supplier' : '—';
```

Replace with:
```dart
final supplierRaw = d['supplier_name']?.toString().trim() ??
    d['supplier']?.toString().trim() ??
    '';
final supplier = supplierRaw.isNotEmpty
    ? supplierRaw
    : (d['supplier_id'] != null ? 'Linked' : '—');
```

Also find the `PurchasePreviewTable` widget (in `lib/features/assistant/presentation/widgets/purchase_preview_table.dart` — check if this file exists; if not, skip this sub-step). Find where supplier is displayed and apply the same fix.

Run: `flutter analyze`

Update SOLUTION_TASKS_V15.md: T-012 ✅

---

### TASK 1-F: Upgrade Quick Prompts to Business-Specific Actions

**File:** `flutter_app/lib/features/assistant/presentation/providers/assistant_quick_prompts_provider.dart`

Find the default prompts list. Replace the generic prompts with business-relevant ones:

```dart
static const _defaultPrompts = [
  AssistantQuickPrompt(
    label: '+ Purchase',
    message: 'New purchase',
  ),
  AssistantQuickPrompt(
    label: '📊 Profit',
    message: "What's my profit this month?",
  ),
  AssistantQuickPrompt(
    label: '🚚 Pending',
    message: 'Show pending deliveries',
  ),
  AssistantQuickPrompt(
    label: '📦 Top Items',
    message: 'Top items this month',
  ),
  AssistantQuickPrompt(
    label: '🏭 Suppliers',
    message: 'List active suppliers this month',
  ),
];
```

Also update the welcome message in `assistant_chat_page.dart` `initState`:
```dart
_msgs.add(
  ChatMessage(
    id: 'welcome',
    text: 'നമസ്കാരം! How can I help today?\n'
        '• Say or type a purchase: "surag 50 bags thuvara 3500"\n'
        '• Ask about profit: "this month profit"\n'
        '• Create supplier: "new supplier ravi 9876543210"\n'
        'Hold 🎤 to speak in Malayalam or English.',
    isUser: false,
    at: DateTime.now(),
  ),
);
```

Run: `flutter analyze`

Update SOLUTION_TASKS_V15.md: T-014 ✅

---

## ════════════════════════════════════
## PHASE 1: WHATSAPP AI BACKEND FIXES
## ════════════════════════════════════

### TASK 1-G: Fix Supplier Fuzzy Match + Better Not-Found Reply

**File:** `backend/app/services/app_assistant_chat.py`

Find where supplier name matching happens. Search for `fuzz.token_sort_ratio` or `_score` function usage for supplier lookup.

Find the threshold comparison (likely `>= 0.80` or `>= 80`):
```python
# Find something like:
if _score(user_supplier, supplier.name) >= 0.80:
    matched_supplier = supplier
```

Change the not-found reply logic: instead of hard-failing with "not found", show closest match:
```python
# After supplier fuzzy search loop:
if not matched_supplier:
    # Find closest match above 65% threshold
    best_match_name = None
    best_score = 0.0
    for s in all_suppliers:
        sc = _score(user_supplier_name, s.name)
        if sc > best_score:
            best_score = sc
            best_match_name = s.name

    if best_match_name and best_score >= 0.65:
        # Return clarification, not hard fail
        return {
            "reply": f"Supplier '{user_supplier_name}' not found. "
                     f"Did you mean '{best_match_name}'? "
                     f"Reply 'yes' to use {best_match_name}, or give the exact name.",
            "intent": "clarify",
            # ...
        }
```

Also lower the main match threshold from 0.80 to 0.75 so "surga" → "surag" (token_sort_ratio = 88) matches directly.

Update SOLUTION_TASKS_V15.md: T-015 ✅

---

### TASK 1-H: Fix Selling Rate Alias (`s rate`, `srate`)

**File:** `backend/app/services/intent_stub.py`

Find the selling rate / selling price extraction regex or keyword list. Search for `selling_price` or `sell`.

Add these aliases to the selling rate parsing:
```python
# Find the section that extracts selling rate. It likely has:
SELL_PATTERNS = [r'\bsell(?:ing)?\s+(?:price\s+)?(\d+)', ...]

# ADD these patterns:
SELL_PATTERNS = [
    r'\bs(?:\s*)?rate\s+(\d+(?:\.\d+)?)',      # "s rate 78", "s.rate 78"
    r'\bsrate\s+(\d+(?:\.\d+)?)',               # "srate78"
    r'\bsell(?:ing)?\s+(?:rate\s+)?(\d+(?:\.\d+)?)',  # "selling 78"
    r'\bsell\s+(\d+(?:\.\d+)?)',               # "sell 78"
    r'\bs\.r\s+(\d+(?:\.\d+)?)',               # "s.r 78"
]
```

Also update `backend/app/services/assistant_system_prompt.py`:

In the `SYSTEM_PROMPT`, find the line about rate aliases. Add:
```
Treat "s rate", "srate", "selling rate", "sell", "sr" as selling_price.
```

Update SOLUTION_TASKS_V15.md: T-016 ✅

---

### TASK 1-I: Add Bulk Entry Format to System Prompt

**File:** `backend/app/services/assistant_system_prompt.py`

Find `SYSTEM_PROMPT`. Find the section about multi-line purchases or `data.lines`. Add this block:

```python
# In SYSTEM_PROMPT, add after the existing TRADE PURCHASE PREVIEW section:
"""
BULK ENTRY FORMAT (WhatsApp / multi-line):
When the user sends multiple lines, each line is one item. Parse ALL lines into data.lines.
Format: [item name] [qty] [unit] [buy/rate] [sell/s rate]

Example input:
  surag
  thuvara jp 67 bags 3510 rate 3840 sell
  thuvara gold 30kg 5 bags 3150 rate 3360 sell

Expected output:
{
  "intent": "create_entry",
  "data": {
    "supplier_name": "Surag",
    "lines": [
      {"item_name": "THUVARA JP", "qty": 67, "unit": "bag", "landing_cost": 3510, "selling_price": 3840},
      {"item_name": "THUVARA GOLD 30KG", "qty": 5, "unit": "bag", "landing_cost": 3150, "selling_price": 3360}
    ]
  }
}
CRITICAL: Never truncate lines. Include EVERY item the user listed.
"""
```

Update SOLUTION_TASKS_V15.md: T-017 ✅

---

## ════════════════════════════════════
## FINAL CHECKS
## ════════════════════════════════════

After ALL phases complete:

```bash
# Flutter
cd flutter_app
flutter analyze
flutter test

# Check no print statements added
grep -rn "^\s*print(" lib/ --include="*.dart"

# Python backend
cd ../backend
python -m py_compile app/services/app_assistant_chat.py
python -m py_compile app/services/intent_stub.py
python -m py_compile app/services/assistant_system_prompt.py
```

Fix any errors. Then commit:
```bash
git add .
git commit -m "fix: API flood debounce, Malayalam speech, AI preview all-lines, fuzzy supplier, bulk entry"
```

Update `SOLUTION_TASKS_V15.md` — mark all completed tasks and update progress table.

---

## CRITICAL DO-NOT LIST

- ❌ Do NOT change `calc_engine.dart` — calculation logic is correct
- ❌ Do NOT change `ai_scan_purchase_draft_map.dart` — scanner mapping is stable
- ❌ Do NOT change any auth flow files
- ❌ Do NOT change pubspec.yaml
- ❌ Do NOT change test files
- ❌ Do NOT add print() statements anywhere
- ❌ Do NOT change `vercel.json` or deployment configs
- ❌ Do NOT refactor the purchase wizard step structure
