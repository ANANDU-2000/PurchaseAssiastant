# HARISREE PURCHASE APP — COMPLETE MASTER PLAN

# April 22, 2026 | Cursor Pro $20 Plan Guide + Seed Data + Priority Fix Order

---

## 📊 DATA ANALYSIS RESULTS

### From Products_list.xlsx (505 products)

- **504 valid products** across **62 subcategories** → grouped into **10 parent categories**
- Units found: BAG, KG-BAG, KGS, KG., PCS, PIECES → normalized to: `bag`, `kg`, `piece`

### From Customer_List.csv (1,497 entries)

- **804 suppliers WITH GST** → add to app as verified suppliers
- **693 without GST** → skip (unreliable/informal)

---
TASK: Make changes ONLY if all validations pass. Do NOT leave partial or broken code.

GOAL:

* Zero API errors
* Zero UI break
* Instant DB → UI sync
* No stale data
* Production-safe

---

STRICT RULES (MANDATORY)

1. BEFORE ANY CHANGE

* Identify affected files
* Check dependencies (providers, API, models)
* DO NOT break existing flows

2. DURING CHANGE

* Keep code minimal
* Do NOT add unnecessary layers
* Follow existing architecture

3. AFTER CHANGE (MANDATORY VALIDATION)

A. API VALIDATION

* All endpoints return correct shape
* No missing fields
* No null crashes
* Create / Update / Delete all working

B. DATABASE VALIDATION

* Data saved correctly
* No duplicate inserts
* No missing relations
* Supplier ↔ Item ↔ Purchase mapping correct

C. STATE MANAGEMENT (VERY IMPORTANT)

* ref.invalidate() used correctly
* No stale providers
* UI reflects latest DB instantly

Must validate:

* suppliersListProvider
* brokersListProvider
* catalogItemsListProvider
* tradePurchasesListProvider

D. CALCULATION VALIDATION

* totals match backend
* tax correct
* commission correct
* freight logic correct

E. UI VALIDATION (CRITICAL)

* NO horizontal scroll anywhere
* Keyboard never hides input
* Save button always visible
* No overflow errors
* No broken layouts

F. PERFORMANCE

* No unnecessary rebuilds
* No heavy widgets
* No lag in search

---

4. IF ANY ISSUE FOUND

* FIX immediately
* DO NOT continue with broken logic

---

5. FINAL CHECK (MUST PASS ALL)

✔ create purchase works
✔ edit purchase works
✔ delete works
✔ supplier search works
✔ item search works
✔ totals correct
✔ UI clean (no overflow)
✔ no stale data after save

---

OUTPUT FORMAT:

1. What was changed
2. Files modified
3. Why change was needed
4. Validation results (ALL PASSED REQUIRED)

IF NOT ALL PASSED → DO NOT FINISH TASK
TASK: Fix issue WITHOUT breaking working features.

PROCESS:

1. Reproduce issue
2. Find root cause (not symptoms)
3. Fix minimal code
4. Validate full flow (create/edit/delete)

CHECK:

* API response correct
* DB updated
* UI refreshed (no stale data)
* No new bugs introduced

DO NOT:

* rewrite unrelated code
* add complexity
* ignore edge cases

OUTPUT:

* root cause
* fix applied
* validation passed
TASK: Improve UX WITHOUT breaking logic.

STRICT UX RULES:

* Single screen flow
* No horizontal scroll
* Minimal clicks
* Inline search only
* No modal interruptions
* Clean spacing
* Consistent font & size
* Keyboard safe

VALIDATE:

* input always visible
* no overflow
* fast interaction (<= 2 taps per action)

OUTPUT:

* UI changes
* before vs after improvement
* validation passed


## 🗂️ CATEGORY TREE (From Your Excel Data)

```
Rice
  ├── BIRIYANI RICE (19 products)
  ├── CHERUMANI RICE (42 products)
  ├── JAYA RICE (5 products)
  ├── MATTA RICE (10 products)
  ├── PONNI RICE (10 products)
  └── RAW RICE (10 products)

Edible Oil
  ├── DALDA (11 products)
  ├── EDIBLE OIL (17 products)
  └── Oil (15 products)

Pulses & Grains
  ├── CHERUPAYAR (15 products)
  ├── KADALA (16 products)
  ├── THUVARA (14 products)
  ├── UZHUNNU (5 products)
  ├── PAYAR (9 products)
  ├── MASOOR DALL (7 products)
  ├── GREENPEAS (5 products)
  ├── WHITE KADALA (3 products)
  ├── WHITE PEAS (3 products)
  ├── Rajma Payar (4 products)
  ├── MUTHIRA (4 products)
  ├── FRIED GRAM (3 products)
  └── VADAPARIPP (2 products)

Spices
  ├── Spices (46 products)
  ├── CHILLI (19 products)
  ├── MALLI (6 products)
  ├── JEERAKAM (3 products)
  ├── KAAYAM (5 products)
  ├── KADUK (5 products)
  ├── MANJAL (4 products)
  ├── ELLU (4 products)
  ├── ULUVA (2 products)
  ├── DRY GINGER (1 product)
  └── PERINJEERAKAM (3 products)

Flour & Atta
  ├── MAIDA ATTA SOOJI (27 products)
  ├── WHEAT (8 products)
  ├── WHEAT FLOUR (4 products)
  ├── Kadalamavu (5 products)
  ├── RAGI (1 product)
  └── CORNFLOUR (1 product)

Dry Fruits & Nuts
  ├── CASHEW NUT (6 products)
  ├── DRY FRUITS (5 products)
  ├── KISMIS (12 products)
  └── KAPPALANDI (6 products)

Essentials
  ├── AVIL (8 products)
  ├── SUGAR (2 products)
  ├── SALT (6 products)
  ├── BELLAM (3 products)
  └── KALKANDAM (3 products)

Packaged Foods
  ├── FAST FOOD ITEMS (30 products)
  └── FRYMES (6 products)

Others
  ├── VEGETABLES (9 products)
  └── CATTLE FEED (4 products)

Miscellaneous
  ├── THINA, BATRI, DILSHAD, MALAR, PULI...

```

---

## 📁 PROJECT FOLDER STRUCTURE (Add These Folders)

```
PurchaseAssistant/
├── flutter_app/
│   └── lib/
│       ├── features/
│       │   ├── pdf/                          ← NEW
│       │   │   ├── presentation/
│       │   │   │   └── pdf_preview_page.dart
│       │   │   └── services/
│       │   │       ├── pdf_generator.dart    ← main PDF builder
│       │   │       ├── pdf_templates/
│       │   │       │   ├── purchase_invoice.dart
│       │   │       │   └── ledger_statement.dart
│       │   │       └── pdf_share_service.dart
│       │   └── seed/                         ← NEW
│       │       └── seed_data.dart            ← categories + sample suppliers
│       └── assets/
│           ├── fonts/                        ← for PDF
│           │   └── (DM Sans or Noto Sans TTF)
│           └── images/
│               └── harisree_logo.png
│
├── backend/
│   └── scripts/
│       ├── seed_categories.py               ← NEW
│       ├── seed_suppliers.py                ← NEW
│       ├── seed_products.py                 ← NEW
│       └── data/
│           ├── categories_seed.json         ← NEW (from your Excel)
│           ├── suppliers_seed.json          ← NEW (804 GST suppliers)
│           └── products_seed.json           ← NEW (504 products)

```

---

## 🌱 SEED DATA: Categories JSON

Save as `backend/scripts/data/categories_seed.json`:

```json
[
  {
    "name": "Rice",
    "subcategories": [
      {"name": "BIRIYANI RICE", "hsn": "10063090", "default_unit": "bag"},
      {"name": "CHERUMANI RICE", "hsn": "10063090", "default_unit": "bag"},
      {"name": "JAYA RICE", "hsn": "10063090", "default_unit": "bag"},
      {"name": "MATTA RICE", "hsn": "10063090", "default_unit": "bag"},
      {"name": "PONNI RICE", "hsn": "10063090", "default_unit": "bag"},
      {"name": "RAW RICE", "hsn": "10063090", "default_unit": "bag"}
    ]
  },
  {
    "name": "Edible Oil",
    "subcategories": [
      {"name": "EDIBLE OIL", "hsn": "15091000", "default_unit": "kg"},
      {"name": "DALDA", "hsn": "15161010", "default_unit": "kg"},
      {"name": "Oil", "hsn": "15091000", "default_unit": "kg"}
    ]
  },
  {
    "name": "Pulses & Grains",
    "subcategories": [
      {"name": "KADALA", "hsn": "07131000", "default_unit": "kg"},
      {"name": "CHERUPAYAR", "hsn": "07131000", "default_unit": "kg"},
      {"name": "THUVARA", "hsn": "07135000", "default_unit": "kg"},
      {"name": "UZHUNNU", "hsn": "07131000", "default_unit": "kg"},
      {"name": "PAYAR", "hsn": "07131000", "default_unit": "kg"},
      {"name": "MASOOR DALL", "hsn": "07134000", "default_unit": "kg"},
      {"name": "GREENPEAS", "hsn": "07131000", "default_unit": "kg"},
      {"name": "WHITE KADALA", "hsn": "07131000", "default_unit": "kg"},
      {"name": "Rajma Payar", "hsn": "07133300", "default_unit": "kg"},
      {"name": "MUTHIRA", "hsn": "07131000", "default_unit": "kg"},
      {"name": "FRIED GRAM", "hsn": "07131000", "default_unit": "kg"}
    ]
  },
  {
    "name": "Spices",
    "subcategories": [
      {"name": "CHILLI", "hsn": "09042110", "default_unit": "kg"},
      {"name": "MALLI", "hsn": "09092100", "default_unit": "kg"},
      {"name": "JEERAKAM", "hsn": "09093100", "default_unit": "kg"},
      {"name": "KAAYAM", "hsn": "09099900", "default_unit": "kg"},
      {"name": "KADUK", "hsn": "09041110", "default_unit": "kg"},
      {"name": "MANJAL", "hsn": "09096300", "default_unit": "kg"},
      {"name": "Spices", "hsn": "09109914", "default_unit": "kg"}
    ]
  },
  {
    "name": "Flour & Atta",
    "subcategories": [
      {"name": "MAIDA ATTA SOOJI", "hsn": "11029000", "default_unit": "bag"},
      {"name": "WHEAT FLOUR", "hsn": "11010000", "default_unit": "bag"},
      {"name": "WHEAT", "hsn": "10019900", "default_unit": "bag"},
      {"name": "Kadalamavu", "hsn": "11061000", "default_unit": "kg"},
      {"name": "RAGI", "hsn": "10083000", "default_unit": "kg"},
      {"name": "CORNFLOUR", "hsn": "11081200", "default_unit": "kg"}
    ]
  },
  {
    "name": "Dry Fruits & Nuts",
    "subcategories": [
      {"name": "CASHEW NUT", "hsn": "08011100", "default_unit": "kg"},
      {"name": "KISMIS", "hsn": "08062000", "default_unit": "kg"},
      {"name": "KAPPALANDI", "hsn": "12024200", "default_unit": "kg"},
      {"name": "DRY FRUITS", "hsn": "08134000", "default_unit": "kg"}
    ]
  },
  {
    "name": "Essentials",
    "subcategories": [
      {"name": "AVIL", "hsn": "19041020", "default_unit": "bag"},
      {"name": "SUGAR", "hsn": "17011400", "default_unit": "kg"},
      {"name": "SALT", "hsn": "25010090", "default_unit": "kg"},
      {"name": "BELLAM", "hsn": "17019910", "default_unit": "kg"},
      {"name": "KALKANDAM", "hsn": "17019910", "default_unit": "kg"}
    ]
  },
  {
    "name": "Packaged Foods",
    "subcategories": [
      {"name": "FAST FOOD ITEMS", "hsn": "19019000", "default_unit": "piece"},
      {"name": "FRYMES", "hsn": "20059900", "default_unit": "piece"}
    ]
  }
]

```

---

## 🌱 SEED SCRIPT: Python (run on backend)

Save as `backend/scripts/seed_categories.py`:

```python
"""
Run: python scripts/seed_categories.py
Seeds categories + subcategories into ItemCategory + CatalogItem tables.
"""
import asyncio, json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.models import ItemCategory, CatalogItem
from app.database import DATABASE_URL

engine = create_async_engine(DATABASE_URL, echo=False)
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

BUSINESS_ID = "YOUR_BUSINESS_UUID_HERE"  # Replace with real business UUID

async def seed():
    with open(os.path.join(os.path.dirname(__file__), 'data/categories_seed.json')) as f:
        data = json.load(f)
    
    async with AsyncSessionLocal() as db:
        for cat_data in data:
            # Check if category exists
            from sqlalchemy import select
            res = await db.execute(
                select(ItemCategory).where(
                    ItemCategory.business_id == BUSINESS_ID,
                    ItemCategory.name == cat_data['name']
                )
            )
            cat = res.scalar_one_or_none()
            if not cat:
                cat = ItemCategory(business_id=BUSINESS_ID, name=cat_data['name'])
                db.add(cat)
                await db.flush()
                print(f"✅ Category: {cat_data['name']}")
            else:
                print(f"⏭️  Exists: {cat_data['name']}")
            
            # Add subcategories as CatalogItems
            for sub in cat_data.get('subcategories', []):
                res2 = await db.execute(
                    select(CatalogItem).where(
                        CatalogItem.business_id == BUSINESS_ID,
                        CatalogItem.category_id == cat.id,
                        CatalogItem.name == sub['name']
                    )
                )
                item = res2.scalar_one_or_none()
                if not item:
                    item = CatalogItem(
                        business_id=BUSINESS_ID,
                        category_id=cat.id,
                        name=sub['name'],
                        default_unit=sub.get('default_unit', 'kg'),
                    )
                    db.add(item)
                    print(f"   ➕ Item: {sub['name']}")
        
        await db.commit()
        print("\n✅ Seed complete!")

asyncio.run(seed())

```

---

## 🌱 SEED SCRIPT: Suppliers (804 with GST)

Save as `backend/scripts/seed_suppliers.py`:

```python
"""
Run: python scripts/seed_suppliers.py
Seeds 804 suppliers who have GST numbers from Customer_List.csv
"""
import asyncio, json, os, sys, re, csv
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import select
from app.models import Supplier
from app.database import DATABASE_URL

engine = create_async_engine(DATABASE_URL, echo=False)
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

BUSINESS_ID = "YOUR_BUSINESS_UUID_HERE"  # Replace

async def seed():
    with open(os.path.join(os.path.dirname(__file__), 'data/suppliers_seed.json')) as f:
        suppliers = json.load(f)
    
    async with AsyncSessionLocal() as db:
        added = skipped = 0
        for s in suppliers:
            res = await db.execute(
                select(Supplier).where(
                    Supplier.business_id == BUSINESS_ID,
                    Supplier.name == s['name']
                )
            )
            existing = res.scalar_one_or_none()
            if existing:
                skipped += 1
                continue
            
            sup = Supplier(
                business_id=BUSINESS_ID,
                name=s['name'],
                phone=s.get('phone') or None,
                gst=s.get('gst') or None,
                location=s.get('location') or None,
                email=s.get('email') or None,
            )
            db.add(sup)
            added += 1
        
        await db.commit()
        print(f"✅ Added: {added} | Skipped: {skipped}")

asyncio.run(seed())

```

**NOTE**: You need to add `gst` and `email` fields to the Supplier model if not present:

```python
# In backend/app/models/contacts.py, add to Supplier:
gst: Mapped[str | None] = mapped_column(String(20), nullable=True)
email: Mapped[str | None] = mapped_column(String(255), nullable=True)

```

---

## 📄 PDF FOLDER + GENERATOR

### pubspec.yaml — add these packages:

```yaml
dependencies:
  pdf: ^3.10.8
  printing: ^5.12.0
  path_provider: ^2.1.2
  share_plus: ^7.2.2

```

### `lib/features/pdf/services/pdf_generator.dart`

```dart
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PurchasePdfGenerator {
  static Future<pw.Document> buildInvoice({
    required Map<String, dynamic> entry,
    required List<Map<String, dynamic>> lines,
  }) async {
    final pdf = pw.Document();
    
    // Load font for Malayalam/Indian text
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    
    final supplier = entry['supplier_name'] ?? '-';
    final broker   = entry['broker_name'] ?? '';
    final date     = entry['entry_date'] ?? '';
    final entryId  = entry['id']?.toString().substring(0, 8) ?? '';

    double total = 0;
    for (final l in lines) {
      total += ((l['qty'] as num? ?? 0) * (l['buy_price'] as num? ?? 0)).toDouble();
    }

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── HEADER ──────────────────────────
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('NEW HARISREE AGENCY',
                    style: pw.TextStyle(font: fontBold, fontSize: 16)),
                  pw.Text('6/366A, Thrithallur, Thrissur 680619',
                    style: pw.TextStyle(font: font, fontSize: 10)),
                  pw.Text('Ph: 8078103800 / 7025333999',
                    style: pw.TextStyle(font: font, fontSize: 10)),
                ]),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text('PURCHASE ENTRY',
                    style: pw.TextStyle(font: fontBold, fontSize: 14,
                      color: PdfColors.teal700)),
                  pw.Text('ID: #$entryId',
                    style: pw.TextStyle(font: font, fontSize: 10)),
                  pw.Text('Date: $date',
                    style: pw.TextStyle(font: font, fontSize: 10)),
                ]),
              ],
            ),
            pw.Divider(thickness: 1.5, color: PdfColors.teal700),
            pw.SizedBox(height: 8),
            
            // ── SUPPLIER + BROKER ────────────────
            pw.Row(children: [
              pw.Text('Supplier: ', style: pw.TextStyle(font: fontBold, fontSize: 11)),
              pw.Text(supplier, style: pw.TextStyle(font: font, fontSize: 11)),
              if (broker.isNotEmpty) ...[
                pw.SizedBox(width: 24),
                pw.Text('Broker: ', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                pw.Text(broker, style: pw.TextStyle(font: font, fontSize: 11)),
              ],
            ]),
            pw.SizedBox(height: 12),
            
            // ── ITEMS TABLE ──────────────────────
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1.2),
                2: const pw.FlexColumnWidth(0.8),
                3: const pw.FlexColumnWidth(1.2),
                4: const pw.FlexColumnWidth(1.5),
              },
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.teal700),
                  children: [
                    _hCell('Item', fontBold),
                    _hCell('Qty', fontBold),
                    _hCell('Unit', fontBold),
                    _hCell('Rate (Rs)', fontBold),
                    _hCell('Amount (Rs)', fontBold),
                  ],
                ),
                // Data rows
                ...lines.map((l) {
                  final qty   = (l['qty'] as num?)?.toDouble() ?? 0;
                  final unit  = l['unit']?.toString() ?? 'kg';
                  final rate  = (l['buy_price'] as num?)?.toDouble() ?? 0;
                  final amt   = qty * rate;
                  return pw.TableRow(children: [
                    _dCell(l['item_name']?.toString() ?? '', font),
                    _dCell(qty.toStringAsFixed(unit == 'bag' ? 0 : 1), font),
                    _dCell(unit.toUpperCase(), font),
                    _dCell('Rs ${rate.toStringAsFixed(2)}', font),
                    _dCell('Rs ${amt.toStringAsFixed(2)}', font, bold: fontBold),
                  ]);
                }),
              ],
            ),
            pw.SizedBox(height: 8),
            
            // ── TOTALS ───────────────────────────
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.teal50,
                  border: pw.Border.all(color: PdfColors.teal700),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Row(children: [
                      pw.Text('Total Amount: ', style: pw.TextStyle(font: fontBold, fontSize: 12)),
                      pw.Text('Rs ${total.toStringAsFixed(2)}',
                        style: pw.TextStyle(font: fontBold, fontSize: 14,
                          color: PdfColors.teal700)),
                    ]),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 16),
            
            // ── FOOTER ───────────────────────────
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Generated by Harisree Purchase App',
                  style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey500)),
                pw.Text('Authorised Signatory',
                  style: pw.TextStyle(font: fontBold, fontSize: 10)),
              ],
            ),
          ],
        );
      },
    ));
    return pdf;
  }

  static pw.Widget _hCell(String t, pw.Font f) => pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(t, style: pw.TextStyle(font: f, fontSize: 10, color: PdfColors.white)),
  );
  
  static pw.Widget _dCell(String t, pw.Font f, {pw.Font? bold}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(t, style: pw.TextStyle(font: bold ?? f, fontSize: 10)),
  );
}

```

### `lib/features/pdf/services/pdf_share_service.dart`

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'pdf_generator.dart';

class PdfShareService {
  static Future<void> shareEntryPdf({
    required Map<String, dynamic> entry,
    required List<Map<String, dynamic>> lines,
  }) async {
    final doc = await PurchasePdfGenerator.buildInvoice(entry: entry, lines: lines);
    final bytes = await doc.save();
    
    final dir = await getTemporaryDirectory();
    final entryId = entry['id']?.toString().substring(0, 8) ?? 'entry';
    final file = File('${dir.path}/harisree_$entryId.pdf');
    await file.writeAsBytes(bytes);
    
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Purchase Entry - ${entry['entry_date']}',
    );
  }
}

```

---

## 🚀 CURSOR PRO GUIDE — SAVE TOKENS, GET BEST RESULTS

### Your Plan: $20/month Pro

- Uses fast model (Sonnet) — good for code tasks
- Switch to "Auto" for complex planning

### 💰 HOW TO SAVE MONEY (Token Rules)

**Rule 1 — One file per session**

```
BAD:  "Fix all the files in my project"
GOOD: "Fix only flutter_app/lib/features/entries/presentation/entry_create_sheet.dart"

```

**Rule 2 — Use @file instead of pasting code**

```
In Cursor chat: @entry_create_sheet.dart fix the supplier picker search

```

**Rule 3 — Use short precise prompts**

```
BAD:  "The search is not working well and users can not find things and it needs to be instant"
GOOD: "Fix search_page.dart line 83: change q.length >= 3 to q.length >= 1. Add 250ms debounce."

```

**Rule 4 — Use Cursor Composer (Ctrl+Shift+I) for multi-file edits** Composer can edit 5-10 files at once → 1 session instead of 10

**Rule 5 — Write .cursorrules file** (already done — see below)

---

## 📝 .cursorrules FILE (Save in project root)

```
# HARISREE PURCHASE APP — CURSOR AI RULES
# Business: New Harisree Agency, Thrissur, Kerala
# Stack: Flutter (Riverpod + GoRouter) + FastAPI + PostgreSQL

## CONTEXT
- This is a wholesale purchase management app for a rice/oil/spices trader
- Owner: Sunil sir — uses WhatsApp, speaks Malayalam and English
- 5 team members, each owns specific pages (see ownership comments in files)

## STRICT RULES

### NEVER CHANGE (Protected)
- run_app_assistant_turn()
- prepare_create_entry_preview()
- commit_create_entry_confirmed()
- All route paths in app_router.dart
- All provider files in core/providers/
- All backend tests in backend/tests/

### ALWAYS DO
- Use HapticFeedback.selectionClick() on nav taps
- Use HapticFeedback.mediumImpact() on save actions
- Wrap fl_chart with LayoutBuilder + RepaintBoundary
- Set explicit text colors (never rely on theme inheritance inside colored cards)
- Show shimmer Container (not SizedBox.shrink()) during loading
- Search minimum 1 character (never >= 3)
- All monetary: NumberFormat.currency(locale:'en_IN', symbol:'₹', decimalDigits:0)

### NEVER DO
- Remove ref.invalidate() calls — they sync state
- Auto-save entries without Preview → YES confirmation
- Show raw DioException to users (show friendly retry card)
- Use Colors.white for card backgrounds in dark theme
- Add any WhatsApp FAB except as a chip on home page
- Use horizontal scroll anywhere in the app

### BUSINESS DATA
- Company: NEW HARISREE AGENCY
- Address: 6/366A, Thrithallur, Thrissur 680619
- Phone: 8078103800 / 7025333999
- Owner phone: (Sunil sir)
- GST: (if known)

### DATA HIERARCHY
- Category (Rice) → Subcategory (BIRIYANI RICE) → Item (ALIF LAILA 50KG)
- Supplier linked to: purchases, items (preferred supplier)
- Broker linked to: purchases, commission %
- Units: kg, bag, piece | kg_per_bag from item master

### CALCULATIONS (STRICT)
- If unit=bag: total_kg = qty × kg_per_bag
- landing_cost = buy_price + transport + commission_share
- profit = (selling_price - landing_cost) × qty
- margin_pct = profit / (selling_price × qty) × 100

### COLORS
canvas: #FFFFFF (light mode)
primary teal: #17A8A7
profit green: #16A34A
loss red: #DC2626
warning amber: #D97706
text dark: #0F172A
text secondary: #64748B
border: #E2E8F0

### PDF RULES
- Use pdf: ^3.10.8 package
- Font: NotoSans (for Indian text support)
- No emojis in PDF — text only
- Columns: Item | Qty | Unit | Rate | Amount
- Footer: "Generated by Harisree Purchase App"
- No colored backgrounds except header row (teal)

```

---

## 🎯 PRIORITY ORDER — WHERE TO START IN CURSOR

### Session 1 — LOGIC FIRST (Most Important)

**Prompt to use:**

```
@entry_create_sheet.dart

Fix these 3 bugs in simple mode:
1. Line ~2445: Hide _landedCostReadout() when _advancedEntryOptions == false (duplicate display)
2. Line ~2388: Remove entire "Stock notes (optional)" ExpansionTile block
3. Rename label "Landed cost / unit (₹) *" → "Rate / unit (₹) *"
   Rename label "Selling price / unit" → "Billing Rate / unit (₹)"
Do not change any calculation logic.

```

### Session 2 — SEARCH FIX

```
@search_page.dart
1. Line 83: change q.length >= 3 to q.length >= 1
2. Line 124: change hint text to "Search items, suppliers..."
3. Add 250ms debounce using Timer to the onChanged handler
4. Add autocorrect: true, enableSuggestions: true to the search TextField

```

### Session 3 — HOME UX

```
@home_page.dart
1. Fix active date chip: change color from cs.inverseSurface to const Color(0xFF17A8A7), text white
2. All loading: () => SizedBox.shrink() → replace with shimmer Container(height: X, color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12))
3. Remove the _SevenDayProfitChartRow() widget call from build() (chart exists in Analytics)
4. Add HapticFeedback.selectionClick() to all nav item onTap calls

```

### Session 4 — PDF SETUP

```
Create new folder: lib/features/pdf/services/
Create file: lib/features/pdf/services/pdf_generator.dart
[paste the PurchasePdfGenerator code from this document]

Create file: lib/features/pdf/services/pdf_share_service.dart
[paste the PdfShareService code from this document]

Add to pubspec.yaml:
  pdf: ^3.10.8
  printing: ^5.12.0
  path_provider: ^2.1.2
  share_plus: ^7.2.2

```

### Session 5 — ANALYTICS TABLE

```
@analytics_page.dart

In _ItemsTabState build():
Replace the card list view with a DataTable.
Keep all existing providers and data (rows variable).
Use this table structure:
Columns: Item | Category | Qty | Avg Rate | Profit | Margin %
Margin % column: green badge if >= 10%, amber if 5-10%, red if < 5%
Wrap in SingleChildScrollView(scrollDirection: Axis.horizontal)

```

### Session 6 — SUPPLIER DETAIL FIX

```
@supplier_detail_page.dart

1. Replace the 6 separate metric cards (DEALS, PURCHASE, TOTAL QTY, AVG LANDING, TOTAL PROFIT, AVG MARGIN) with one SingleChildScrollView(scrollDirection: Axis.horizontal) containing compact _compactStat widgets (label + value, 2 lines, no icons)

2. Fix date filter chips: remove async wait for chip labels — render [7d][30d][90d][All] immediately as hardcoded ChoiceChip widgets. Only their selected state needs a provider.

3. Add to AppBar actions: edit icon + share icon

```

### Session 7 — AI CHAT FIX

```
@assistant_chat_page.dart

1. After each bot message bubble, check if it has a previewToken. If yes, show two buttons:
   - OutlinedButton "✗ Cancel" (red) → sends "NO" to chat
   - FilledButton "✓ Save Entry" (teal) → sends "YES" to chat

2. Add AI status dot in AppBar next to "AI Assistant" title:
   Green dot = model response is not 'assistant' (real AI active)
   Amber dot = model is 'assistant' (stub/demo mode)

3. Add horizontal ScrollView of quick command chips above input bar:
   "📦 Add purchase", "📊 Month report", "🏆 Best supplier?", "Today profit?"

```

### Session 8 — BACKEND SEED DATA

```
In backend/scripts/, create:
1. data/categories_seed.json  [paste from this document]
2. seed_categories.py  [paste from this document — set BUSINESS_ID]
3. seed_suppliers.py  [paste from this document — set BUSINESS_ID]

Then run:
cd backend
python scripts/seed_categories.py
python scripts/seed_suppliers.py

```

---

## ⚠️ CURSOR ALWAYS FAILS — ROOT CAUSES + FIXES


| Problem             | Why Cursor fails                      | Fix                                        |
| ------------------- | ------------------------------------- | ------------------------------------------ |
| Breaks working code | Prompt too vague, Cursor guesses      | Always specify exact line numbers          |
| Changes wrong file  | Cursor picks similar file names       | Use @filename in prompt                    |
| Removes imports     | Cursor "cleans up" after edit         | Add: "Do not remove any imports"           |
| Breaks providers    | Doesn't understand Riverpod lifecycle | Add: "Never remove ref.invalidate() calls" |
| Wrong calculations  | Assumes bag = piece                   | Add business context to .cursorrules       |
| Adds emojis to PDF  | Thinks emojis look nice               | Add: "No emojis in PDF — text only"        |


### Template Prompt Structure (copy this pattern):

```
File: [exact file path]
Task: [one specific task only]
Line/Location: [line number or function name]
Change: [exact change — before → after]
Do NOT: [what to avoid]
Do NOT change: [protected functions]

```

---

## ✅ VERIFIED DATA SUMMARY


| Data                           | Count   | Action                                |
| ------------------------------ | ------- | ------------------------------------- |
| Suppliers with GST             | **804** | Add via seed_suppliers.py             |
| Suppliers without GST          | 693     | Skip                                  |
| Total products                 | **504** | Add via seed_products.py (when ready) |
| Categories (subcategory level) | **62**  | Grouped into 10 parent categories     |
| Parent categories              | **10**  | Add via seed_categories.json          |


---

*Harisree Purchase App | Complete Master Plan | April 22, 2026* *New Harisree Agency, Thrissur | Owner: Sunil sir*