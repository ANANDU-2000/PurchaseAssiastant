# HARISREE APP — ENTRY FORM + VIEW PAGES + LEDGER + PDF STATEMENT
# Cursor Pro Prompts | April 27, 2026

---

## WHAT NEEDS TO CHANGE (CLEAR SUMMARY)

| Page | Remove | Add |
|---|---|---|
| Item Entry (Step 3) | Half-height bottom sheet | Full viewport form page |
| Supplier View | 4 metric cards, charts, "Price vs", trend | Header info + history list + statement link |
| Item View | Same metric cards | Item info + purchase history + statement |
| Ledger/Statement | "catalog math" label, bad search | Date filter + search by invoice/name/DI number + edit/delete |
| PDF Statement | Missing date range, bad header | Header + body table + footer with date filter |

---

## PROMPT 1 — ITEM ENTRY: FULL VIEWPORT FORM (NOT BOTTOM SHEET)

```
@entry_create_sheet.dart  AND  @add_item_bottom_sheet.dart
OR wherever "Add item" opens the half-height sheet

CURRENT PROBLEM (from screenshot img_45):
- Sheet opens at ~50% screen height — fields cut off
- User cannot see calculation preview while typing
- Background page shows through — confusing
- Small drag handle at top wastes space

TARGET: A full-screen white page, not a modal sheet.
Think of Tally-style data entry — clean, fast, full screen, keyboard stays up.

CHANGE 1 — Open as full screen page instead of bottom sheet:
Replace showModalBottomSheet with Navigator.push (or context.push) to a new page:
  AddItemEntryPage(
    supplierId: supplierId,
    onSaved: (line) => _onLineSaved(line),
  )

CHANGE 2 — Page layout (AddItemEntryPage):

Scaffold(
  backgroundColor: Colors.white,
  appBar: AppBar(
    title: Text(isEditing ? 'Edit Item' : 'Add Item'),
    backgroundColor: Colors.white,
    foregroundColor: Color(0xFF0F172A),
    elevation: 0,
    leading: IconButton(
      icon: Icon(Icons.close),
      onPressed: () => Navigator.pop(context),
    ),
    actions: [
      TextButton(
        onPressed: _onSave,
        child: Text('SAVE', style: TextStyle(
          color: Color(0xFF17A8A7),
          fontWeight: FontWeight.bold,
          fontSize: 15,
        )),
      ),
    ],
  ),
  body: SingleChildScrollView(
    padding: EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Item search
        _itemSearchField(),
        SizedBox(height: 12),
        
        // 2. Qty + Unit on same row
        Row(children: [
          Expanded(flex: 2, child: _qtyField()),
          SizedBox(width: 10),
          Expanded(flex: 2, child: _unitDropdown()),
          // show kg equivalent if unit = bag
          if (_unit == 'bag' && _kgPerUnit != null)
            Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.only(left: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kg/bag', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(_kgPerUnit.toString(),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
        ]),
        SizedBox(height: 12),
        
        // 3. Purchase Rate (large, prominent)
        _labeledField(
          label: 'Purchase Rate (Rs./unit) *',
          field: _landingCostField(),
          hint: 'e.g. 2600',
        ),
        SizedBox(height: 12),
        
        // 4. Selling Rate (optional, smaller)
        _labeledField(
          label: 'Selling Rate (Rs./unit)',
          field: _sellingPriceField(),
          hint: 'Optional — for profit tracking',
        ),
        SizedBox(height: 16),
        
        // 5. Live calculation box — always visible
        _calculationBox(),
        SizedBox(height: 16),
        
        // 6. HSN + Notes — collapsed by default
        ExpansionTile(
          title: Text('HSN / Notes (optional)',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          tilePadding: EdgeInsets.zero,
          children: [
            _hsnField(),
            SizedBox(height: 8),
            _notesField(),
          ],
        ),
      ],
    ),
  ),
  // Bottom bar with Add More + Save
  bottomNavigationBar: SafeArea(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _onSaveAndAddMore,
            style: OutlinedButton.styleFrom(
              foregroundColor: Color(0xFF17A8A7),
              side: BorderSide(color: Color(0xFF17A8A7)),
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('SAVE & ADD MORE'),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: _onSave,
            style: FilledButton.styleFrom(
              backgroundColor: Color(0xFF17A8A7),
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('SAVE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    ),
  ),
)

CHANGE 3 — Calculation box (always visible, updates live):
Widget _calculationBox() {
  final total = (_qty ?? 0) * (_landingCost ?? 0);
  final totalKg = (_unit == 'bag') ? (_qty ?? 0) * (_kgPerUnit ?? 0) : null;
  return Container(
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Color(0xFFF0FDFD),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Color(0xFF17A8A7).withOpacity(0.3)),
    ),
    child: Column(children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${_qty ?? 0} ${_unit ?? ""} × Rs.${_landingCost ?? 0}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          Text('= Rs.${_formatMoney(total)}',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A))),
        ],
      ),
      if (totalKg != null)
        Padding(
          padding: EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total weight', style: TextStyle(fontSize: 11, color: Colors.grey)),
              Text('$totalKg kg', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      if (_sellingPrice != null && _sellingPrice! > 0)
        Padding(
          padding: EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Profit', style: TextStyle(fontSize: 11, color: Colors.grey)),
              Text(
                'Rs.${_formatMoney((_sellingPrice! - (_landingCost ?? 0)) * (_qty ?? 0))}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: (_sellingPrice! > (_landingCost ?? 0))
                    ? Colors.green.shade600 : Colors.red.shade400,
                ),
              ),
            ],
          ),
        ),
    ]),
  );
}

CHANGE 4 — Auto-fill when item selected from search:
In onItemSelected callback:
  setState(() {
    _selectedItem = item;
    _unit = item.defaultUnit;               // auto-fill unit
    _landingCost = item.defaultLandingCost; // auto-fill rate
    _kgPerUnit = item.kgPerUnit;            // auto-fill kg/bag
    _hsnCode = item.hsnCode;                // auto-fill HSN
  });
  // Move focus to qty field immediately
  FocusScope.of(context).requestFocus(_qtyFocusNode);

CHANGE 5 — Item list in Step 3 (after saving items):
Replace the existing item list cards with clean rows:
  for each saved line:
    Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.itemName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text('${line.qty} ${line.unit}  ·  Rs.${line.landingCost}/unit',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Text('Total: Rs.${_formatMoney(line.total)}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                    color: Color(0xFF17A8A7))),
              ],
            ),
          ),
          Column(children: [
            TextButton(onPressed: () => _editLine(line), child: Text('Edit')),
            TextButton(
              onPressed: () => _deleteLine(line),
              child: Text('Remove', style: TextStyle(color: Colors.red)),
            ),
          ]),
        ],
      ),
    )

Do NOT change step 1 (Supplier) or step 2 (Terms) pages.
Do NOT change any API call or calculation logic.
Do NOT change provider invalidation.
```

---

## PROMPT 2 — SUPPLIER VIEW PAGE: FULL REDESIGN (NO METRICS)

```
@supplier_detail_page.dart

REMOVE COMPLETELY (do not keep, do not hide — delete):
  - TOTAL QTY metric card
  - AVG LANDING metric card
  - TOTAL PROFIT metric card
  - AVG MARGIN metric card
  - "Price vs other suppliers" section
  - "Avg landing trend" line chart section
  - All metric-related providers and fetch calls for these 4 cards

REASON: These metrics are wrong (showing 0) and confusing.
A wholesale business owner needs: WHO bought WHAT, WHEN, for HOW MUCH. That is all.

NEW PAGE STRUCTURE — 3 clear sections:

═══ SECTION 1: HEADER ═══

AppBar:
  title: supplier.name (bold)
  backgroundColor: white
  actions: [
    IconButton(icon: Icons.edit_outlined, tooltip: 'Edit', onPressed: _editSupplier),
    IconButton(icon: Icons.picture_as_pdf_outlined, tooltip: 'Statement PDF',
      onPressed: _generateStatementPdf),
    IconButton(icon: Icons.share_outlined, tooltip: 'Share', onPressed: _shareStatement),
  ]

Below AppBar — Supplier Info Card:
Card(
  margin: EdgeInsets.all(12),
  child: Padding(
    padding: EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      
      // Name row
      Text(supplier.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      SizedBox(height: 4),
      
      // Address (if available)
      if (supplier.address?.isNotEmpty == true)
        Row(children: [
          Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
          SizedBox(width: 4),
          Expanded(child: Text(supplier.address!, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
        ]),
      SizedBox(height: 4),
      
      // Phone + WhatsApp row
      Row(children: [
        if (supplier.phone?.isNotEmpty == true)
          GestureDetector(
            onTap: () => _launchPhone(supplier.phone!),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Color(0xFF17A8A7).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Icon(Icons.phone, size: 14, color: Color(0xFF17A8A7)),
                SizedBox(width: 4),
                Text(supplier.phone!, style: TextStyle(fontSize: 12, color: Color(0xFF17A8A7))),
              ]),
            ),
          ),
        SizedBox(width: 8),
        if (supplier.whatsappNumber?.isNotEmpty == true)
          GestureDetector(
            onTap: () => _launchWhatsApp(supplier.whatsappNumber!),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Icon(Icons.message, size: 14, color: Colors.green.shade600),
                SizedBox(width: 4),
                Text('WhatsApp', style: TextStyle(fontSize: 12, color: Colors.green.shade600)),
              ]),
            ),
          ),
      ]),
      SizedBox(height: 4),
      
      // GSTIN (if available)
      if (supplier.gstNumber?.isNotEmpty == true)
        Text('GSTIN: ${supplier.gstNumber}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontFamily: 'monospace')),
      
      Divider(height: 16),
      
      // Quick summary — 3 numbers only, in one line
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _quickStat('Bills', '$_totalBills'),
          _vDivider(),
          _quickStat('Total Spend', 'Rs.${_formatMoney(_totalSpend)}'),
          _vDivider(),
          _quickStat('Unpaid', 'Rs.${_formatMoney(_outstanding)}',
            valueColor: _outstanding > 0 ? Colors.orange : Colors.green),
        ],
      ),
    ]),
  ),
)

Widget _quickStat(String label, String value, {Color? valueColor}) {
  return Column(children: [
    Text(value, style: TextStyle(
      fontSize: 14, fontWeight: FontWeight.bold,
      color: valueColor ?? Color(0xFF0F172A))),
    SizedBox(height: 2),
    Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
  ]);
}

Widget _vDivider() => Container(width: 1, height: 30, color: Colors.grey.shade200);

═══ SECTION 2: DATE FILTER + SEARCH BAR ═══

// Date filter chips — hardcoded, instant
Padding(
  padding: EdgeInsets.symmetric(horizontal: 12),
  child: Row(children: [
    for (final label in ['This Month', '3 Months', '6 Months', 'All'])
      Padding(
        padding: EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label, style: TextStyle(fontSize: 12)),
          selected: _dateFilter == label,
          onSelected: (_) => setState(() => _dateFilter = label),
          selectedColor: Color(0xFF17A8A7),
          labelStyle: TextStyle(
            color: _dateFilter == label ? Colors.white : Color(0xFF374151)),
          side: BorderSide.none,
          backgroundColor: Colors.grey.shade100,
        ),
      ),
  ]),
),
SizedBox(height: 8),

// Search
Padding(
  padding: EdgeInsets.symmetric(horizontal: 12),
  child: TextField(
    controller: _searchController,
    decoration: InputDecoration(
      hintText: 'Search by invoice no., item name...',
      prefixIcon: Icon(Icons.search, size: 18),
      filled: true, fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.circular(10)),
      contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    ),
  ),
),
SizedBox(height: 8),

═══ SECTION 3: PURCHASE HISTORY LIST ═══

// Section header
Padding(
  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text('Purchase History',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      Text('${_filteredPurchases.length} bills',
        style: TextStyle(fontSize: 12, color: Colors.grey)),
    ],
  ),
),

// List
ListView.builder(
  shrinkWrap: true,
  physics: NeverScrollableScrollPhysics(),
  itemCount: _filteredPurchases.length,
  itemBuilder: (ctx, i) {
    final p = _filteredPurchases[i];
    return _purchaseRow(p);
  },
)

Widget _purchaseRow(TradePurchase p) {
  return InkWell(
    onTap: () => context.push('/purchases/${p.id}'),
    child: Container(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(p.humanId, style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13,
                color: Color(0xFF17A8A7))),
              Text('Rs.${_formatMoney(p.totalAmount)}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(DateFormat('dd MMM yyyy').format(p.purchaseDate),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              _paymentStatusChip(p),
            ],
          ),
          SizedBox(height: 5),
          // Items in this bill — one line per item
          for (final line in p.lines)
            Padding(
              padding: EdgeInsets.only(top: 2),
              child: Row(children: [
                Expanded(child: Text(line.itemName,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                Text('${line.qty} ${line.unit}',
                  style: TextStyle(fontSize: 12)),
                SizedBox(width: 12),
                Text('Rs.${_formatMoney(lineMoney(line))}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              ]),
            ),
          // Action row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _editPurchase(p),
                child: Text('Edit', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => _deletePurchase(p),
                child: Text('Delete',
                  style: TextStyle(fontSize: 12, color: Colors.red)),
              ),
              TextButton(
                onPressed: () => _printPurchase(p),
                child: Text('Print', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _paymentStatusChip(TradePurchase p) {
  Color color;
  String label;
  if (p.isPaid) { color = Colors.green; label = 'Paid'; }
  else if (p.isDueSoon) { color = Colors.orange; label = 'Due soon'; }
  else { color = Colors.red; label = 'Unpaid'; }
  return Container(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
  );
}

═══ FAB: New Purchase ═══
floatingActionButton: FloatingActionButton.extended(
  onPressed: _newPurchase,
  backgroundColor: Color(0xFF17A8A7),
  icon: Icon(Icons.add),
  label: Text('New Purchase'),
)

ALSO — "Full PUR ledger" button:
Replace the current text link with a proper button:
  Padding(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: OutlinedButton.icon(
      onPressed: _openLedger,
      icon: Icon(Icons.receipt_long_outlined, size: 16),
      label: Text('View Full Statement'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Color(0xFF17A8A7),
        side: BorderSide(color: Color(0xFF17A8A7)),
        minimumSize: Size(double.infinity, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  )

Do NOT add back the 4 metric cards.
Do NOT add back any chart.
Do NOT change supplier edit logic.
```

---

## PROMPT 3 — ITEM VIEW PAGE: FULL REDESIGN (NO METRICS)

```
@item_detail_page.dart  OR  @catalog_item_detail_page.dart

SAME APPROACH AS SUPPLIER VIEW — remove metrics, add clear history.

REMOVE: All metric cards (total qty, avg rate, profit, margin, trend chart)
KEEP: Item name, category, HSN, default unit, default rate

NEW PAGE STRUCTURE:

═══ HEADER ═══
AppBar:
  title: item.name (bold)
  actions: [
    IconButton(icon: Icons.edit_outlined, onPressed: _editItem),
    IconButton(icon: Icons.picture_as_pdf_outlined, onPressed: _statementPdf),
  ]

Item Info Card:
Card(
  margin: EdgeInsets.all(12),
  child: Padding(
    padding: EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(item.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      SizedBox(height: 4),
      Row(children: [
        _infoChip(item.categoryName),
        SizedBox(width: 6),
        _infoChip(item.defaultUnit),
        if (item.hsnCode?.isNotEmpty == true) ...[
          SizedBox(width: 6),
          _infoChip('HSN: ${item.hsnCode}'),
        ],
      ]),
      if (item.itemCode?.isNotEmpty == true)
        Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Code: ${item.itemCode}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ),
      Divider(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _quickStat('Purchases', '$totalBills'),
          _vDivider(),
          _quickStat('Total Qty', '$totalQty ${item.defaultUnit}'),
          _vDivider(),
          _quickStat('Avg Rate', 'Rs.${avgRate.toStringAsFixed(0)}'),
        ],
      ),
    ]),
  ),
)

Widget _infoChip(String label) {
  return Container(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
  );
}

═══ DATE FILTER + SEARCH ═══
Same as supplier view:
  Chips: This Month | 3 Months | 6 Months | All
  Search: "Search by invoice no., supplier name..."

═══ PURCHASE HISTORY LIST ═══
Same row design as supplier view BUT show supplier name prominently:

Widget _itemPurchaseRow(TradePurchaseLine line, TradePurchase parent) {
  return Container(
    margin: EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: Colors.grey.shade200),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(parent.supplierName ?? '—',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        Text('Rs.${_formatMoney(lineMoney(line))}',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ]),
      SizedBox(height: 2),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(DateFormat('dd MMM yyyy').format(parent.purchaseDate),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        Text('${line.qty} ${line.unit}  ·  Rs.${line.landingCost}/unit',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ]),
      SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(parent.humanId, style: TextStyle(fontSize: 11, color: Color(0xFF17A8A7))),
        _paymentStatusChip(parent),
      ]),
    ]),
  );
}

Do NOT add profit/margin/revenue columns.
Do NOT add any charts.
Do NOT change item edit logic.
```

---

## PROMPT 4 — SUPPLIER LEDGER: DATE FILTER + SEARCH + ACTIONS

```
@supplier_ledger_page.dart

CURRENT PROBLEMS (from img_09):
- Header shows name + phone only, missing address/GSTIN/date range
- "Line subtotal (catalog math)" — confusing internal label
- Search only works by item name, not invoice number or date
- No edit/delete actions on individual purchase rows
- No select-all for bulk actions
- No date range filter

CHANGE 1 — Remove confusing labels:
  DELETE: "Line subtotal (catalog math) ₹2,70,088"
  KEEP ONLY: "Total Bills: 1  ·  Total: Rs.2,70,185"
  KEEP: "Outstanding: Rs.2,70,185" in orange if > 0

CHANGE 2 — Search field (improved):
Change hint: "Search by invoice no., item, date..."
Search should match:
  - purchase.humanId (invoice number) e.g. "PUR-2026-0001" or just "0001"
  - any line.itemName
  - date string e.g. "27 Apr" or "April"
  
Implementation:
  final q = _searchController.text.toLowerCase();
  _filtered = _all.where((p) =>
    p.humanId.toLowerCase().contains(q) ||
    p.lines.any((l) => l.itemName.toLowerCase().contains(q)) ||
    DateFormat('dd MMM yyyy').format(p.purchaseDate).toLowerCase().contains(q)
  ).toList();

CHANGE 3 — Date filter bar (above search):
Row of chips: This Month | 3 Months | 6 Months | All Time | Custom
For "Custom" — show DateRangePicker
When filter changes, reload purchase list for that date range.

CHANGE 4 — Purchase row with actions:
Each purchase row must show:
  Row 1: [Invoice No. bold teal]  [Date grey]  [Amount bold right]
  Row 2: Item names — one per line: [Item] [Qty+Unit] [Rate] [Line Amount]
  Row 3 (status): [Payment status chip]  [Due date if unpaid]
  Row 4 (actions): [Edit] [Delete] [Print PDF]

No horizontal scroll inside the row.
All amounts right-aligned and bold.

CHANGE 5 — Select all + bulk actions:
Add checkbox column when user long-presses any row.
In multi-select mode, show bottom action bar:
  AppBar changes to: "3 selected" with close icon
  Bottom bar: [Print Selected] [Delete Selected]
  
Long press any row → enters multi-select mode, selects that row
Short tap when in multi-select → toggles selection
"Cancel" button exits multi-select mode

CHANGE 6 — Pull to refresh:
Wrap ListView with RefreshIndicator:
  RefreshIndicator(
    onRefresh: () async {
      ref.invalidate(supplierLedgerProvider(supplierId));
      await ref.read(supplierLedgerProvider(supplierId).future);
    },
    child: ListView.builder(...),
  )

Do NOT change totals calculation logic.
Do NOT change PDF generation call.
```

---

## PROMPT 5 — ITEM LEDGER: SAME AS SUPPLIER LEDGER

```
@item_ledger_page.dart  OR  @item_statement_page.dart

Apply SAME CHANGES as Prompt 4 (Supplier Ledger) but for item purchases:

HEADER shows:
  Item name (bold)
  Category · HSN: xxxxx · Code: yyy
  Total purchases: N  ·  Total qty: X bag (Y kg)
  Avg rate: Rs.Z per unit

SEARCH matches:
  - Invoice number (humanId)
  - Supplier name
  - Date

DATE FILTER: This Month | 3 Months | 6 Months | All Time

ROW shows:
  Row 1: [Supplier name bold]  [Invoice No. teal small]  [Amount bold right]
  Row 2: [Date]  [Qty + Unit]  [Rate per unit]
  Row 3: [Payment status chip]
  Row 4: [Edit] [Delete] [Print]

All same logic as supplier ledger.
```

---

## PROMPT 6 — PDF STATEMENT TEMPLATE (DATE FILTER BASED)

```
Create file: flutter_app/lib/core/services/supplier_statement_pdf.dart

This generates a clean A4 PDF statement for a supplier, filtered by date range.

USAGE:
  final pdf = await buildSupplierStatementPdf(
    supplier: supplier,
    purchases: filteredPurchases,       // already date-filtered list
    business: businessProfile,
    fromDate: _fromDate,
    toDate: _toDate,
  );

LAYOUT — 3 SECTIONS:

═══ HEADER (top of page) ═══
┌─────────────────────────────────────────────────────────────────┐
│  [LOGO if available]     NEW HARISREE AGENCY                   │
│                          6/366A Thrithallur, Thrissur 680619   │
│                          Ph: 8078103800  GSTIN: XXXXXXXXXXXX   │
│─────────────────────────────────────────────────────────────────│
│  SUPPLIER ACCOUNT STATEMENT                                     │
│  Supplier: SURAG TRADERS                 GSTIN: (if available) │
│  Address: Delhi                          Phone: 123456789      │
│  Period: 01 Apr 2026 – 27 Apr 2026      Date: 27 Apr 2026     │
└─────────────────────────────────────────────────────────────────┘

═══ BODY (repeating table) ═══
Columns (no horizontal overflow — fixed widths):
  Date       | Invoice No.   | Item(s)   | Qty    | Rate      | Amount
  FixedWidth   FixedWidth      FlexWidth   Fixed    Fixed       Fixed
  55mm         35mm            auto        25mm     25mm        30mm

For each purchase:
  Row 1: date | humanId | first item name | first item qty+unit | first item rate | bill total
  If multiple items: additional rows for each extra item (date/invoice blank, show item only)
  Subtotal row after each purchase if > 1 items

After all purchases:
  ─────────────────────────────────────────────────────────────────
  TOTAL    N bills              [total qty summary]      Rs.X,XX,XXX
  ─────────────────────────────────────────────────────────────────
  Outstanding (unpaid):                                  Rs.X,XX,XXX
  ─────────────────────────────────────────────────────────────────

═══ FOOTER (bottom of every page) ═══
Page X of Y
Generated by Harisree Purchase App on 27 Apr 2026
"This is a computer-generated statement. No signature required."

═══ CODE ═══

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models/trade_purchase_models.dart';
import '../models/business_profile.dart';

final _money = NumberFormat('#,##,##0.00', 'en_IN');
final _dateFmt = DateFormat('dd MMM yyyy');

String _rs(num n) => 'Rs. ${_money.format(n)}';
String _safe(String? s) => (s?.trim().isEmpty ?? true) ? '—' : s!
    .replaceAll(RegExp(r'[^\x20-\x7E\u00A0-\u024F]'), '').trim();

const _teal = PdfColor.fromInt(0xFF17A8A7);
const _dark = PdfColor.fromInt(0xFF0F172A);
const _muted = PdfColor.fromInt(0xFF64748B);
const _border = PdfColor.fromInt(0xFFE2E8F0);
const _greenBg = PdfColor.fromInt(0xFFECFDF5);
const _headerBg = PdfColor.fromInt(0xFFF8FAFC);

Future<pw.Document> buildSupplierStatementPdf({
  required SupplierModel supplier,
  required List<TradePurchase> purchases,
  required BusinessProfile business,
  required DateTime fromDate,
  required DateTime toDate,
}) async {
  final doc = pw.Document();
  
  // Totals
  final totalAmount = purchases.fold<double>(0, (s, p) => s + p.totalAmount);
  final outstanding = purchases
    .where((p) => !p.isPaid)
    .fold<double>(0, (s, p) => s + p.totalAmount);
  
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20 * PdfPageFormat.mm),
      
      header: (ctx) => _buildHeader(business, supplier, fromDate, toDate, ctx),
      footer: (ctx) => _buildFooter(ctx),
      
      build: (ctx) => [
        pw.SizedBox(height: 8),
        _buildTable(purchases),
        pw.SizedBox(height: 8),
        _buildTotalsBlock(purchases.length, totalAmount, outstanding),
      ],
    ),
  );
  return doc;
}

pw.Widget _buildHeader(
  BusinessProfile biz,
  SupplierModel sup,
  DateTime from,
  DateTime to,
  pw.Context ctx,
) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Column(children: [
      // Business row
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(_safe(biz.displayTitle),
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _teal)),
            if (biz.address?.isNotEmpty == true)
              pw.Text(_safe(biz.address), style: pw.TextStyle(fontSize: 8, color: _muted)),
            if (biz.phone?.isNotEmpty == true)
              pw.Text('Ph: ${_safe(biz.phone)}', style: pw.TextStyle(fontSize: 8, color: _muted)),
            if (biz.gstNumber?.isNotEmpty == true)
              pw.Text('GSTIN: ${_safe(biz.gstNumber)}',
                style: pw.TextStyle(fontSize: 8, color: _muted)),
          ]),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: pw.BoxDecoration(
              color: _teal,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text('ACCOUNT STATEMENT',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
                color: PdfColors.white)),
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Container(height: 1, color: _teal),
      pw.SizedBox(height: 6),
      // Supplier info row
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Supplier: ${_safe(sup.name)}',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            if (sup.address?.isNotEmpty == true)
              pw.Text(_safe(sup.address), style: pw.TextStyle(fontSize: 8, color: _muted)),
            if (sup.phone?.isNotEmpty == true)
              pw.Text('Ph: ${_safe(sup.phone)}', style: pw.TextStyle(fontSize: 8, color: _muted)),
            if (sup.gstNumber?.isNotEmpty == true)
              pw.Text('GSTIN: ${_safe(sup.gstNumber)}',
                style: pw.TextStyle(fontSize: 8, color: _muted)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('Period: ${_dateFmt.format(from)} – ${_dateFmt.format(to)}',
              style: pw.TextStyle(fontSize: 9, color: _muted)),
            pw.Text('Date: ${_dateFmt.format(DateTime.now())}',
              style: pw.TextStyle(fontSize: 9, color: _muted)),
          ]),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Container(height: 0.5, color: _border),
    ]),
  );
}

pw.Widget _buildTable(List<TradePurchase> purchases) {
  final rows = <pw.TableRow>[];
  
  // Header row
  rows.add(pw.TableRow(
    decoration: pw.BoxDecoration(color: _headerBg),
    children: [
      _th('Date'),
      _th('Invoice No.'),
      _th('Item'),
      _th('Qty', align: pw.TextAlign.center),
      _th('Rate', align: pw.TextAlign.right),
      _th('Amount', align: pw.TextAlign.right),
    ],
  ));
  
  // Data rows
  for (final p in purchases) {
    for (int i = 0; i < p.lines.length; i++) {
      final l = p.lines[i];
      final isFirst = i == 0;
      rows.add(pw.TableRow(
        decoration: pw.BoxDecoration(
          color: i.isEven ? PdfColors.white : _headerBg,
        ),
        children: [
          _td(isFirst ? _dateFmt.format(p.purchaseDate) : ''),
          _td(isFirst ? _safe(p.humanId) : '', color: _teal),
          _td(_safe(l.itemName)),
          _td('${l.qty} ${l.unit}', align: pw.TextAlign.center),
          _td(_rs(l.landingCost), align: pw.TextAlign.right),
          _td(_rs(lineMoney(tradePurchaseLineToCalcLine(l))),
            align: pw.TextAlign.right, bold: true),
        ],
      ));
    }
    // Bill subtotal row (only if multiple items)
    if (p.lines.length > 1) {
      rows.add(pw.TableRow(
        decoration: const pw.BoxDecoration(color: _greenBg),
        children: [
          _td('', colspan: 5),
          pw.SizedBox(),
          pw.SizedBox(),
          pw.SizedBox(),
          pw.SizedBox(),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: pw.Text('Bill: ${_rs(p.totalAmount)}',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _teal)),
          ),
        ],
      ));
    }
  }
  
  return pw.Table(
    border: pw.TableBorder.all(color: _border, width: 0.5),
    columnWidths: const {
      0: pw.FixedColumnWidth(42),   // Date
      1: pw.FixedColumnWidth(52),   // Invoice
      2: pw.FlexColumnWidth(3),     // Item
      3: pw.FixedColumnWidth(36),   // Qty
      4: pw.FixedColumnWidth(42),   // Rate
      5: pw.FixedColumnWidth(52),   // Amount
    },
    children: rows,
  );
}

pw.Widget _buildTotalsBlock(int billCount, double total, double outstanding) {
  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.Container(
      width: 200,
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        _totalRow('Total Bills', billCount.toString()),
        _totalRow('Total Amount', _rs(total), bold: true),
        if (outstanding > 0) ...[
          pw.Container(height: 0.5, color: _border),
          _totalRow('Outstanding (Unpaid)', _rs(outstanding),
            valueColor: PdfColors.orange),
        ],
      ]),
    ),
  );
}

pw.Widget _buildFooter(pw.Context ctx) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 6),
    child: pw.Column(children: [
      pw.Container(height: 0.5, color: _border),
      pw.SizedBox(height: 3),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 7, color: _muted)),
          pw.Text('Generated by Harisree Purchase App · ${_dateFmt.format(DateTime.now())}',
            style: pw.TextStyle(fontSize: 7, color: _muted)),
          pw.Text('Computer generated · No signature required',
            style: pw.TextStyle(fontSize: 7, color: _muted)),
        ],
      ),
    ]),
  );
}

pw.Widget _th(String t, {pw.TextAlign align = pw.TextAlign.left}) =>
  pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: pw.Text(t, textAlign: align,
      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _dark)));

pw.Widget _td(String t, {
  pw.TextAlign align = pw.TextAlign.left,
  bool bold = false,
  PdfColor? color,
}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Text(t, textAlign: align,
      style: pw.TextStyle(
        fontSize: 8,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color ?? _dark,
      )));

pw.Widget _totalRow(String label, String val, {bool bold = false, PdfColor? valueColor}) =>
  pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _muted)),
        pw.Text(val, style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: valueColor ?? _dark,
        )),
      ],
    ));
```

---

## PROMPT 7 — SAME PDF FOR ITEM STATEMENT

```
Create file: flutter_app/lib/core/services/item_statement_pdf.dart

Identical structure to supplier_statement_pdf.dart BUT:
  - Header section 2 shows ITEM info instead of supplier info:
      Item: BASMATHU RICE
      Category: Rice  |  HSN: 10063090  |  Code: BRKTH001
  - Table columns:
      Date | Invoice No. | Supplier | Qty | Rate | Amount
  - Totals block:
      Total Bills: N
      Total Qty: X bag (Y kg)
      Total Amount: Rs.Z

Call it from item detail page AppBar PDF button.
Use same _safe(), _rs(), _th(), _td() helpers — copy from supplier_statement_pdf.dart.
```

---

## CONNECT PDF STATEMENT TO LEDGER DATE FILTER

```
In supplier_ledger_page.dart and item_ledger_page.dart:

When user taps "Print Statement" or PDF icon in AppBar:
  1. Use the CURRENTLY ACTIVE date filter (not always all-time)
  2. Pass fromDate and toDate to buildSupplierStatementPdf()
  3. Show Printing.sharePdf() share sheet

Example:
  Future<void> _printStatement() async {
    final from = _getFromDate(_dateFilter);  // based on chip selection
    final to = DateTime.now();
    final pdf = await buildSupplierStatementPdf(
      supplier: widget.supplier,
      purchases: _filteredPurchases,
      business: _businessProfile,
      fromDate: from,
      toDate: to,
    );
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${widget.supplier.name}_statement_${DateFormat('MMMyyyy').format(to)}.pdf',
    );
  }

DateTime _getFromDate(String filter) {
  final now = DateTime.now();
  return switch (filter) {
    'This Month' => DateTime(now.year, now.month, 1),
    '3 Months'   => DateTime(now.year, now.month - 3, 1),
    '6 Months'   => DateTime(now.year, now.month - 6, 1),
    _            => DateTime(2000, 1, 1),  // All Time
  };
}
```

---

## PRIORITY ORDER

| # | Task | Time | Prompt |
|---|---|---|---|
| 1 | Item entry full viewport | 40 min | Prompt 1 |
| 2 | Supplier view redesign | 45 min | Prompt 2 |
| 3 | Item view redesign | 30 min | Prompt 3 |
| 4 | Supplier ledger date+search+actions | 40 min | Prompt 4 |
| 5 | Item ledger same | 20 min | Prompt 5 |
| 6 | PDF statement template | 30 min | Prompt 6 |
| 7 | Item PDF statement | 15 min | Prompt 7 |
| 8 | Connect PDF to date filter | 10 min | Connect section |

**Total estimated: ~4 hours in Cursor Pro**

---

## WHAT THE USER SEES AFTER ALL FIXES

**Supplier view:**
→ Name + address + phone (tap to call) + GSTIN
→ 3 numbers: Bills | Total Spend | Unpaid
→ Date chips + search bar
→ List of purchases with items, amounts, status
→ Edit / Delete / Print on each row
→ "View Full Statement" button → ledger page

**Ledger page:**
→ Header: supplier info + period + total
→ Date filter: This Month / 3 Months / All
→ Search: invoice number, item name, date
→ Each purchase: all items, all amounts, status
→ Long press → select mode → bulk delete or print
→ PDF button → generates statement for selected date range

**PDF Statement:**
→ Business header (name, address, GSTIN, logo)
→ "ACCOUNT STATEMENT" label
→ Supplier info + date range
→ Clean table: Date | Invoice | Item | Qty | Rate | Amount
→ Totals block: Bills + Amount + Outstanding
→ Footer: page number + generated date

*Hexastack Solutions | April 27, 2026*
