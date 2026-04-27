# HARISREE APP — FULL VISUAL AUDIT + CURSOR PRO PROMPTS

# Based on 51 Real App Screenshots | April 27, 2026

---

## WHAT I SAW — PAGE BY PAGE (HONEST)

### ✅ WORKING WELL

- Home dashboard circle chart — clean, teal, good
- Maintenance payment card on home — shows correctly
- Supplier list with Tap-to-call and WhatsApp — good UX
- Purchase entry 4-step wizard — good structure
- Bottom sheet Add Item form — mostly good
- AI chat WhatsApp-style — good visual design

### ❌ BROKEN / BAD (REAL ISSUES FROM SCREENSHOTS)

---

## BUG LIST (FROM SCREENSHOTS — NOT GUESSES)

### 🔴 CRITICAL

**BUG-R1: Reports Item table COMPLETELY OVERFLOWS (img_48)**

- 8 columns: Item, Bags, Box, Tin, Kg, Avg₹, Sel₹, Total₹
- Text breaks mid-word: "Ba gs" "Bo x" "Av g ₹" "Sel ₹"
- Numbers break across lines: "₹2,27,2 50" "₹2,52,50 0"
- This is the WORST visual bug in the whole app
- Fix: Remove Box, Tin columns (show only Bags + Kg) and remove Sel₹ from table view
- Show only: Item | Bags | Kg | Avg Rate | Total Spend

**BUG-R2: Supplier detail metrics all show 0 (img_08)**

- TOTAL QTY = 0.0 (wrong — should be 100 bags)
- AVG LANDING = ₹0.00 (wrong — should be ₹52/kg)
- TOTAL PROFIT = ₹0 (wrong — should be ₹10,000)
- AVG MARGIN = 0.0% (wrong — should be 3.9%)
- Purchase bill shows ₹2,70,08 8 — number cuts off at screen edge
- "Price vs other suppliers: 0% No data" — misleading
- Root cause: metrics cards fetch separately from purchase history
and the provider/API for supplier metrics is returning empty data

**BUG-R3: AI chat stuck in loop — "Need item. Example: item rice" (img_03)**

- User says: "create purchase on Surag supplier item sandwich, oil, 12 box"
- AI says: "Need item. Example: item rice"
- User says: "sunrich oil"
- AI AGAIN says: "Need item. Example: item rice"
- AI is stuck — it does not extract item name from a sentence correctly
- It only matches exact keyword format not natural language
- Also: "profit?" → AI says "Profit details are missing" but ₹10,000 profit
is visible on home screen — AI is not reading from the analytics API

**BUG-R4: Alerts & Reminders page COMPLETELY EMPTY (img_16,17,18,20)**

- All 4 tabs: All, Alerts, Reminders, System — all show blank
- One purchase of ₹2,70,185 is marked "Due soon" in supplier ledger
- This should show as an alert but it does not
- The alerts engine is not triggering for overdue/due-soon purchases

**BUG-R5: Cloud payment card shows error (img_15)**

- "Unable to load cloud payment details — Retry"
- This is a failed API call every time Settings opens
- Fix: Make this section purely local (SharedPreferences) — no API call needed
The payment status is developer-side info, not from server

### 🟡 MEDIUM

**BUG-M1: Supplier ledger header missing info (img_09)**

- Shows: name "surag" + phone "123456789"
- Missing: address, GSTIN, city, date range of statement
- "Line subtotal (catalog math) ₹2,70,088" — confusing label
- "Outstanding (unpaid balance) ₹2,70,185" — amount mismatch with bill total
(difference is ₹97 — likely freight or rounding not included in line subtotal)
- Fix: Show supplier card: Name (bold) | Address | Phone | GSTIN | Date range

**BUG-M2: Broker list shows "Commission: Per cent\n2" (img_13)**

- Should show: "Commission: 2%"
- "Per cent" is a raw enum value being displayed directly
- Fix: In broker list tile, format commission as: "${broker.commissionPercent}%"
Never show the raw enum string "Per cent"

**BUG-M3: Category page only shows 2 categories (img_06)**

- Oil: 3 items, RICE: 2 items — seed data partially loaded
- 9 categories in seed JSON but only 2 showing
- Subcategory detail shows "General" with 0 items (img_07) — placeholder leak
- Fix: Run seed for all businesses AND hide subcategories with 0 items

**BUG-M4: Suppliers Anuvind, Ravi show blank subtitles (img_11)**

- No location, no phone — blank under name
- These suppliers have no phone/address filled in
- Fix: Show placeholder "No contact saved" in grey instead of blank
Add "Tap to edit" hint

**BUG-M5: Home chart text truncated "5000 ..." (img_19)**

- Circle shows "100 BAG • 0 BOX • 0 TIN • 5000 ..."
- Text cut with "..." — kg value truncated
- Fix: Remove BOX and TIN from this line when they are 0
Show: "100 BAG • 5000 KG" only

**BUG-M6: Category tab shows "RICE — BIRIYANI RICE" (img_21)**

- Subcategory name shown with full path — too long, ugly
- Fix: Show just "BIRIYANI RICE" not "RICE — BIRIYANI RICE"

**BUG-M7: Purchase history line shows "₹2,70,08 8" cut (img_08)**

- Amount "₹2,70,088" breaks across lines at narrow screen
- Fix: Use Flexible or constrained width for amount text

**BUG-M8: "General" subcategory shows with 0 items (img_07)**

- This is a default placeholder subcategory that should be hidden
- Fix: Filter subcategories where item_count == 0

**BUG-M9: Item entry form bottom sheet only half viewport (img_45)**

- Sheet starts halfway up screen — user cannot see all fields easily
- Fix: Set initial snap to 0.85 (85% of viewport) with drag to full
DraggableScrollableSheet initialChildSize: 0.85, maxChildSize: 1.0

**BUG-M10: Reports table missing Spend + Rate columns (img_25, 26)**

- Category view: shows only "Category | Total qty" — missing spend amount per category
- Supplier view: shows only "Supplier | Deals" — missing spend per supplier
- These are the most important numbers — should be the FIRST columns shown

### 🟢 LOW

**BUG-L1: Reports table horizontal scroll disabled but table overflows**

- No horizontal scroll → overflow crashes readability
- Either add scroll OR reduce columns strictly

**BUG-L2: Supplier detail "Price vs other suppliers: 0%" misleading**

- When only 1 supplier exists, this shows 0% — confusing
- Fix: Hide this section when fewer than 2 suppliers

**BUG-L3: Broker ledger button is dark green, not teal**

- "New purchase" button in broker empty state = dark green (#1B4332)
- All primary buttons should be teal (#17A8A7)

**BUG-L4: Alerts page has no "No alerts" empty state for "All" tab**

- "All" tab shows blank (img_18) — no empty state illustration
- Only "Alerts" tab shows the bell icon + "No reminders yet" (img_17)
- Fix: Show same empty state for ALL tabs

**BUG-L5: Add item form "Landing cost" label**

- "Landing cost *" → change to "Purchase Rate (₹/unit) *"
- "Selling price" → "Selling Rate (₹/unit)"
- These labels are clearer for the user

**BUG-L6: Logo placeholder black box in Settings (img_14)**

- Logo preview shows a black square when no logo is set
- Fix: Show a grey dotted border placeholder with camera icon instead

**BUG-L7: Search bar suggestions overlap content (reported by user)**

- When typing in search, autocomplete suggestions appear behind other widgets
- Fix: Wrap search results in Material with elevation: 8 and proper z-index

**BUG-L8: Delete not updating all pages**

- After deleting a purchase, some pages still show old data
- Fix: In delete handler, add ref.invalidate() for ALL providers:
homeSnapshotProvider, reportsProvider, supplierDetailProvider,
itemDetailProvider, purchaseListProvider

---

## CURSOR PRO PROMPTS — COPY PASTE EXACTLY

---

### PROMPT A — Fix reports table overflow (MOST URGENT — BUG-R1)

```
@reports_page.dart  (or wherever the Item/Supplier/Category report table is built)

PROBLEM: The Item report table has 8 columns and completely overflows the screen.
Text like "Bags" becomes "Ba gs" and numbers like ₹2,27,250 become "₹2,27,2 50".

FIX ITEM TABLE:
Remove columns: Box, Tin, Sel₹ (selling price)
Keep only: Item | Bags | Kg | Avg Rate | Total Spend

New column widths (use Table with fixed columnWidths):
  Item:       FlexColumnWidth(3.0)
  Bags:       FixedColumnWidth(52)
  Kg:         FixedColumnWidth(56)
  Avg Rate:   FixedColumnWidth(64)
  Total:      FixedColumnWidth(76)

FIX SUPPLIER TABLE:
Add "Spend" column after "Supplier"
Remove any column that shows per-unit rates
Keep: Supplier | Deals | Spend

New column widths:
  Supplier:   FlexColumnWidth(2.5)
  Deals:      FixedColumnWidth(48)
  Spend:      FixedColumnWidth(80)

FIX CATEGORY TABLE:
Add "Spend" column
Keep: Category | Bags | Spend

All header cells: fontSize 11, fontWeight bold, color Color(0xFF374151)
All data cells: fontSize 12 for numbers, fontSize 11 for names
Number cells: TextAlign.right, fontWeight bold
No horizontal scroll. All content must fit in 390px width.
Total row: background Color(0xFFECFDF5), text Color(0xFF059669), fontWeight bold

Do NOT change any provider or API call logic.
Do NOT change any calculation logic.
Do NOT remove existing imports.
```

---

### PROMPT B — Fix supplier metrics showing 0 (BUG-R2)

```
@supplier_detail_page.dart

PROBLEM: TOTAL QTY, AVG LANDING, TOTAL PROFIT, AVG MARGIN all show 0
even though purchases exist for this supplier.

STEP 1: Find where these metric values are read from.
Check if they come from:
  a) A provider that fetches supplier analytics separately
  b) The same purchase list data that shows in "Trade purchase history"

STEP 2: If the history list shows purchases correctly but metrics show 0,
the metrics provider is not being initialized/called correctly.
Find the AsyncValue or FutureProvider for supplier metrics.
Ensure it receives the correct supplierId parameter.
Log: print('Supplier metrics fetch for: $supplierId');
and print the raw API response.

STEP 3: Fix the purchase amount display.
Find where "₹2,70,08 8" is rendered (number broken across lines).
Wrap the amount Text widget:
  Text(
    amountStr,
    overflow: TextOverflow.ellipsis,
    maxLines: 1,
    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
  )
or constrain with: SizedBox(width: 100, child: Text(...))

STEP 4: In the supplier detail header card, add:
  - Supplier address (if available)
  - Phone number with tap-to-call
  - GSTIN (if available)
  - Date range of shown data ("Apr 2026" or "All time")

STEP 5: Remove "Price vs other suppliers" section entirely when
  supplierCount == 1. Replace with nothing (SizedBox.shrink()).

Do NOT change calculation logic.
Do NOT remove any existing provider.
```

---

### PROMPT C — Fix broker commission display (BUG-M2)

```
@broker_list_tile.dart  OR  wherever broker list items are built

PROBLEM: Shows "Commission: Per cent" on one line and "2" on next line.
This is a raw enum value ("Per cent") being shown directly.

FIX:
Find the broker commission display text.
Change from: broker.commissionType.toString() or similar
Change to: "${broker.commissionPercent ?? 0}%"

The full subtitle should read: "Commission: 2%" in one line.

Also fix: broker empty state button color
Find: "New purchase" FilledButton in broker empty state
Change its backgroundColor from any dark green to: const Color(0xFF17A8A7)

Also in supplier detail page:
Fix AppBar actions — add Edit icon button:
  IconButton(
    icon: const Icon(Icons.edit_outlined),
    tooltip: 'Edit supplier',
    onPressed: () => _navigateToEditSupplier(),
  )

Do NOT change any broker data model or API.
```

---

### PROMPT D — Fix home circle text truncation (BUG-M5, BUG-M6)

```
@home_page.dart

FIX 1 — Circle chart subtitle text:
Find the text showing "100 BAG • 0 BOX • 0 TIN • 5000 ..."
Change to only show units that are > 0:
  final parts = <String>[];
  if (bags > 0) parts.add('$bags BAG');
  if (kg > 0) parts.add('$kg KG');
  if (box > 0) parts.add('$box BOX');
  if (tin > 0) parts.add('$tin TIN');
  final unitText = parts.join(' • ');
Never show "0 BOX" or "0 TIN" — hide zero values.

FIX 2 — Category tab subcategory name:
Find where "RICE — BIRIYANI RICE" is rendered in the Category tab list.
Change from: "${category.name} — ${subcategory.name}"
Change to: "${subcategory.name}" only (show just the subcategory name)

FIX 3 — Active chip color:
Find the date filter chips (Today, Week, Month, Year).
The active chip background must be: const Color(0xFF17A8A7)
The active chip text color must be: Colors.white
The inactive chip text color must be: const Color(0xFF374151)

Do NOT change any providers or calculation logic.
```

---

### PROMPT E — Fix alerts page empty state (BUG-R4, BUG-L4)

```
@alerts_page.dart  (or alerts_reminders_page.dart)

PROBLEM 1: All 4 tabs show blank — no empty state for "All" tab.
FIX: For every tab (All, Alerts, Reminders, System), when list is empty:
  Show:
    Icon(Icons.notifications_none_outlined, size: 64, color: Colors.grey.shade300)
    Text('No alerts yet', style: bold fontSize 16)
    Text('Payment due alerts and reminders will appear here.',
      style: muted fontSize 13, textAlign: center)

PROBLEM 2: Purchase marked "Due soon" in supplier ledger does NOT appear here.
FIX: In the alerts data source, check:
  - Is there a query that fetches trade_purchases where payment_due_date < now()+7days?
  - If this query exists but returns empty, log the raw result.
  - If this query does not exist, add it to the alerts provider:
    Fetch all purchases where status != 'paid' AND purchase_date + payment_days <= today + 7
    For each result, create an AlertItem with:
      title: "Payment due: ${purchase.humanId}"
      subtitle: "${purchase.supplierName} · Rs. ${purchase.totalAmount}"
      dueDate: purchase.dueDate
      type: AlertType.payment

PROBLEM 3: Cloud billing alert not showing.
FIX: Add a local alert for cloud billing:
  On app start, check SharedPreferences key "cloud_paid_${YYYY_MM}"
  If not paid AND today >= 9th of month:
    Add a static alert item:
      title: "Cloud billing due"
      subtitle: "Rs. 2,500 due — pay to Hexastack Solutions"
      type: AlertType.system

Do NOT change the tab/chip selection logic.
Do NOT change any navigation.
```

---

### PROMPT F — Fix cloud payment settings error (BUG-R5)

```
@settings_page.dart

PROBLEM: "Unable to load cloud payment details — Retry" error showing
every time Settings opens. This makes an API call that always fails.

FIX:
1. Find the API call for cloud payment details.
2. Remove this API call entirely.
3. Replace the Cloud hosting section with a purely local widget
   that reads from SharedPreferences:

Widget _cloudBillingSection() {
  final now = DateTime.now();
  final monthKey = 'cloud_paid_${now.year}_${now.month}';
  final isPaid = prefs.getBool(monthKey) ?? false;
  final paidDate = prefs.getString('cloud_paid_date_${now.year}_${now.month}');
  
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeader('Cloud Hosting'),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Render Backend'),
            subtitle: Text(isPaid
              ? 'Paid this month${paidDate != null ? " ($paidDate)" : ""}'
              : 'Due on 9th — Rs. 670/month'),
            trailing: isPaid
              ? const Icon(Icons.check_circle, color: Colors.green)
              : TextButton(
                  onPressed: _markCloudPaid,
                  child: const Text('Mark paid'),
                ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('UPI'),
            subtitle: const Text('krishnaanamdhu12-5@okicici'),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy UPI ID',
              onPressed: () {
                Clipboard.setData(const ClipboardData(
                  text: 'krishnaanamdhu12-5@okicici'));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('UPI ID copied')));
              },
            ),
          ),
        ]),
      ),
    ],
  );
}

void _markCloudPaid() {
  final now = DateTime.now();
  final monthKey = 'cloud_paid_${now.year}_${now.month}';
  prefs.setBool(monthKey, true);
  prefs.setString('cloud_paid_date_${now.year}_${now.month}',
    DateFormat('dd MMM yyyy').format(now));
  setState(() {});
}

Also update the maintenance amount to ₹2,000 (not ₹2,500).

Do NOT remove sign out button.
Do NOT change any other settings section.
```

---

### PROMPT G — Fix item entry form (BUG-M9, BUG-L5)

```
@entry_create_sheet.dart  OR  add_item_bottom_sheet.dart

FIX 1 — Bottom sheet snap height:
Find DraggableScrollableSheet or showModalBottomSheet.
Set: initialChildSize: 0.88, minChildSize: 0.6, maxChildSize: 1.0
This makes the form take 88% of screen height immediately.

FIX 2 — Field label changes:
  "Landing cost *" → "Purchase Rate ₹/unit *"
  "Selling price" → "Selling Rate ₹/unit (optional)"

FIX 3 — Calculation preview:
Find the "0 kg × ₹0 = ₹0" preview text.
Change to: "${qty} ${unit} × Rs.${rate} = Rs.${total}"
Show both unit total AND kg equivalent if unit is bag:
  "100 bag × Rs.52 = Rs.5,200 per bag"
  "= 5,000 kg total"

FIX 4 — Default values not autofilling:
When an item is selected from catalog search:
  - unit field must auto-fill from catalogItem.defaultUnit
  - landing cost must auto-fill from catalogItem.defaultLandingCost
  - kg_per_unit must auto-fill from catalogItem.kgPerUnit
  - These are editable but must auto-fill
  Verify: after onItemSelected callback, call setState() with all values

FIX 5 — Purchase line display in step 3:
Find where "100 bag · ₹52/kg → line ₹270088 · Profit ₹10000" is shown
Change "→ line" to nothing. Format as:
  Row: [ItemName bold] [Edit] [Delete]
  Row: [100 bag · Rs.52/kg] [Total: Rs.2,70,088]
  Row: Profit: Rs.10,000 in green small text

Do NOT change calculation logic.
Do NOT change step navigation (Back/Next buttons).
```

---

### PROMPT H — Rebuild AI system prompt + response logic (BUG-R3)

```
@ai_chat_provider.dart  AND  @ai_system_prompt.dart (or wherever system prompt is defined)

CRITICAL PROBLEM: AI is stuck saying "Need item. Example: item rice"
even when user clearly says "sunrich oil" or "oil 12 box".

The AI cannot extract item names from natural sentences.
The rule-based parser is too strict.

FIX 1 — System prompt rewrite:
Replace the current system prompt with:

"""
You are a smart purchase assistant for a Kerala wholesale grocery business.

YOUR DATA ACCESS:
- Trade purchases: all purchase bills with supplier, items, qty, rate, total
- Suppliers: name, phone, address
- Items: name, category, default rate
- You can read landing_cost as the purchase price (same thing)
- You can read selling_price as the billing rate

WHAT YOU CAN DO:
1. Answer questions about purchases, spending, profit, suppliers
2. Create new purchases (ask for: supplier, item(s), qty, unit, rate)
3. Show reports: today/week/month totals

RULES:
- "profit" in this app = selling_price - landing_cost per unit × qty
- "landing cost" = "buy price" = "purchase rate" — all same field
- When user says any item name, match it to closest catalog item
- Accept natural language: "100 bags basmathu at 52 from surag" = full purchase
- Never ask "Need item. Example: item rice" — just ask naturally:
  "Which item did you buy? (e.g. Basmathu rice, Sunrich oil)"
- After showing a purchase preview, show TWO buttons: Save | Cancel
- Keep answers SHORT — max 3 lines for simple questions
- For profit questions, always calculate from purchase data directly

RESPONSE FORMAT:
- Simple answers: plain text, max 3 lines
- Purchase preview: show as a clean summary card
- Data questions: give the number first, then one line of context
"""

FIX 2 — Item extraction:
Find the intent parser for "create purchase" intent.
When extracting item name from user message:
  - Do NOT require exact keyword format "item X"
  - Try to match ANY word in the message against the catalog items list
  - Use fuzzy matching: if message contains "oil" → check catalog for items
    containing "oil" (Sunrich Oil, Edible Oil, etc.)
  - If multiple matches, ask user to pick from a short list
  - Never loop the same error message twice

FIX 3 — Profit response:
When user asks "profit?" or "what is my profit":
  - Call the analytics API for current month
  - Return: "This month: Rs. X profit (Y%) from Z deals"
  - Do NOT say "profit details are missing"

FIX 4 — Quick chips:
Find the quick command chips row.
Current chips: Profit | New purchase | Today | Suppliers
Change to: Today profit | Add purchase | Month report | Top supplier | Due payments

Do NOT change the chat message bubble design.
Do NOT change message send/receive logic.
```

---

### PROMPT I — Fix delete → all pages update (BUG-L8)

```
@purchase_delete_handler.dart  OR  wherever delete purchase is called

PROBLEM: After deleting a purchase, some pages still show old data.

Find the delete function. After successful delete API call, add:
  ref.invalidate(homeSnapshotProvider);
  ref.invalidate(reportsSummaryProvider);
  ref.invalidate(supplierPurchasesProvider(supplierId));
  ref.invalidate(supplierAnalyticsProvider(supplierId));
  ref.invalidate(itemPurchasesProvider(itemId));
  ref.invalidate(purchaseListProvider);
  ref.invalidate(alertsProvider);

Also add a SnackBar confirmation:
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Purchase deleted'),
      backgroundColor: Colors.red.shade600,
      action: SnackBarAction(
        label: 'OK',
        textColor: Colors.white,
        onPressed: () {},
      ),
    ),
  );

Then pop the current page: context.pop();

SAME FIX for edit/update: after successful edit, invalidate the same providers.

Do NOT add any new API calls.
Do NOT change the delete confirmation dialog.
```

---

### PROMPT J — Fix supplier ledger header + statement (BUG-M1)

```
@supplier_ledger_page.dart

PROBLEM: Ledger header shows only name + phone number.
Missing: address, GSTIN, date range.
Label "Line subtotal (catalog math)" is confusing.

FIX 1 — Header card:
Replace current header with:
  Card(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(supplier.name, style: bold fontSize 18),
          if (supplier.address?.isNotEmpty == true)
            Text(supplier.address!, style: muted fontSize 12),
          Row(children: [
            if (supplier.phone != null)
              TextButton.icon(
                icon: Icon(Icons.phone, size: 14),
                label: Text(supplier.phone!),
                onPressed: () => _tapToCall(supplier.phone!),
              ),
            if (supplier.gstNumber?.isNotEmpty == true)
              Text('GST: ${supplier.gstNumber}',
                style: muted fontSize 11),
          ]),
          const Divider(),
          Text('Statement Period: ${_dateRangeLabel}',
            style: muted fontSize 12),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Bills: ${purchaseCount}',
                style: bold fontSize 13),
              Text('Total: Rs. ${_formatMoney(billTotal)}',
                style: bold fontSize 14 color teal),
            ],
          ),
          if (outstandingAmount > 0)
            Text('Outstanding: Rs. ${_formatMoney(outstandingAmount)}',
              style: bold color orange fontSize 13),
        ],
      ),
    ),
  )

FIX 2 — Remove "Line subtotal (catalog math)" label
Replace with just: "Total (sum of line amounts)"
Or remove it entirely — show only "Bill total" and "Outstanding"

FIX 3 — PDF statement for supplier:
In the supplier statement PDF, add header section:
  Business name + address + GSTIN (from business profile)
  "SUPPLIER STATEMENT"
  Supplier name, address, phone
  Period: From dd MMM yyyy to dd MMM yyyy
  
Add footer:
  "Generated by Harisree Purchase App | ${today}"

Do NOT change any calculation or data fetching logic.
```

---

### PROMPT K — Fix page navigation speed (remove loaders)

```
FIND all pages that have page-level loading animations:
  CircularProgressIndicator on full page
  Any FadeTransition or SlideTransition on page push

REMOVE all page transition animations:
In MaterialApp or GoRouter, set:
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    },
  )

The ZoomPageTransitionsBuilder is Flutter's default native zoom —
instant-feeling, no artificial slide/fade delay.

FIND in home_page.dart, reports_page.dart, supplier_detail_page.dart:
All occurrences of:
  loading: () => const Center(child: CircularProgressIndicator())
  OR
  loading: () => SizedBox.shrink()

Replace with shimmer placeholder:
  loading: () => _shimmerPlaceholder()

Widget _shimmerPlaceholder() {
  return Column(children: [
    for (int i = 0; i < 3; i++)
      Container(
        height: 72,
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
  ]);
}

Also: remove any Timer.periodic or Future.delayed in page init
that artificially delays data display.

Do NOT change any navigation routes.
Do NOT change provider refresh logic.
```

---

## PRODUCTION DATA SEED — RUN IN RENDER SHELL

After ALL code fixes, run this to seed ALL users with categories + items:

```bash
# In Render Dashboard → your service → Shell tab:
cd backend
DATABASE_URL=$DATABASE_URL python -c "
import asyncio
from app.database import get_sync_engine
from app.services.catalog_suppliers_seed import run_catalog_suppliers_seed
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker

engine = get_sync_engine()
Session = sessionmaker(bind=engine)

with Session() as db:
    rows = db.execute(text('SELECT id, name FROM businesses')).fetchall()
    print(f'Seeding {len(rows)} businesses...')
    for row in rows:
        import uuid
        biz_id = uuid.UUID(str(row[0]))
        try:
            stats = run_catalog_suppliers_seed(db, biz_id)
            db.commit()
            print(f'OK: {row[1]} — {stats}')
        except Exception as e:
            db.rollback()
            print(f'ERR: {row[1]} — {e}')
print('Done.')
"
```

---

## COMPLETE TODO LIST — PRIORITY ORDER

### TODAY (1-2 hours each in Cursor)

- PROMPT A — Fix reports table overflow (most visible bug)
- PROMPT F — Fix cloud settings error (quick fix)
- PROMPT D — Fix home circle text + chip colors
- PROMPT C — Fix broker commission display

### TOMORROW

- PROMPT B — Fix supplier metrics showing 0
- PROMPT J — Fix supplier ledger header
- PROMPT G — Fix item entry form
- PROMPT E — Fix alerts page

### DAY 3

- PROMPT H — Rebuild AI system prompt
- PROMPT I — Fix delete → all pages update
- PROMPT K — Remove page loading animations

### DAY 4

- Run production seed for all users
- Test PDF receipt (A5 format — already built)
- Enable real AI provider (Groq or OpenAI)
- Update maintenance amount to ₹2,000 in settings

---

## CURSOR PRO RULES FILE (.cursorrules) — ADD THIS

```
# Harisree Purchase App — Cursor Rules

## Data Rules
- All purchase data comes from trade_purchase_lines ONLY
- landing_cost = buy_price = purchase_rate — SAME FIELD, different names
- selling_price = billing_rate — SAME FIELD
- bag ≠ kg ≠ piece ≠ box — never assume equal
- total_kg = qty * kg_per_unit (only when unit is bag)
- Money format: NumberFormat('#,##,##0.00', 'en_IN') — Indian format

## UI Rules  
- Brand teal: Color(0xFF17A8A7) — use for ALL active chips, primary buttons
- Never show "0 BOX" or "0 TIN" — hide zero-value units
- No emojis or special symbols in PDF output — plain text only
- Numbers: always bold, TextAlign.right
- Important labels: fontSize 13+, fontWeight bold, color Color(0xFF0F172A)
- Muted text: color Color(0xFF64748B)

## Provider Rules
- After every create/edit/delete, invalidate ALL affected providers
- Never call ref.invalidate() inside build() — only in callbacks
- Loading state: use shimmer Container, not CircularProgressIndicator

## Naming Rules
- "Landing cost" is correct technical term in code
- Show as "Purchase Rate" in UI labels
- "Commission: 2%" not "Commission: Per cent\n2"
- Broker percentage: "${broker.commissionPercent}%" format

## Print/PDF Rules
- Always use Rs. prefix, never ₹ symbol
- Strip all emojis with _safePdf() before rendering
- A4 for full invoice, A5 for compact receipt
- HSN code must appear on every line item
```

---

*Generated: April 27, 2026 | Real screenshot audit | Hexastack Solutions*