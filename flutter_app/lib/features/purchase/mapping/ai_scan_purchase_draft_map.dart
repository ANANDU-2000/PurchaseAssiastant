// Maps scanner v2/v3 wire JSON (ScanResult) ↔ PurchaseDraft for reusing
// PurchaseEntryWizardV2 after AI scan. See backend `scanner_v2/types.py`.

import '../domain/purchase_draft.dart';

double? _toDouble(Object? o) {
  if (o == null) return null;
  if (o is num) return o.toDouble();
  return double.tryParse(o.toString().trim());
}

String _draftUnitFromScanUnitType(String? ut) {
  switch ((ut ?? 'KG').toUpperCase()) {
    case 'BAG':
      return 'bag';
    case 'BOX':
      return 'box';
    case 'TIN':
      return 'tin';
    case 'PCS':
      return 'piece';
    default:
      return 'kg';
  }
}

String _scanUnitTypeFromDraftUnit(String unit) {
  switch (unit.trim().toLowerCase()) {
    case 'bag':
    case 'sack':
      return 'BAG';
    case 'box':
      return 'BOX';
    case 'tin':
      return 'TIN';
    case 'piece':
    case 'pcs':
      return 'PCS';
    default:
      return 'KG';
  }
}

PurchaseDraft purchaseDraftFromScanResultJson(Map<String, dynamic> scan) {
  final sup = scan['supplier'];
  String? supplierId;
  String? supplierName;
  if (sup is Map) {
    supplierId = sup['matched_id']?.toString().trim();
    if (supplierId != null && supplierId.isEmpty) supplierId = null;
    supplierName = (sup['matched_name'] ?? sup['raw_text'])?.toString().trim();
    if (supplierName != null && supplierName.isEmpty) supplierName = null;
  }

  String? brokerId;
  String? brokerName;
  final br = scan['broker'];
  if (br is Map) {
    brokerId = br['matched_id']?.toString().trim();
    if (brokerId != null && brokerId.isEmpty) brokerId = null;
    brokerName = (br['matched_name'] ?? br['raw_text'])?.toString().trim();
    if (brokerName != null && brokerName.isEmpty) brokerName = null;
  }

  double? deliveredRate;
  double? billtyRate;
  double? freightAmount;
  String freightType = 'separate';
  double? headerDiscountPercent;
  final ch = scan['charges'];
  if (ch is Map) {
    deliveredRate = _toDouble(ch['delivered_rate']);
    billtyRate = _toDouble(ch['billty_rate']);
    freightAmount = _toDouble(ch['freight_amount']);
    final ft = ch['freight_type']?.toString().trim().toLowerCase();
    if (ft != null && (ft == 'included' || ft == 'separate')) {
      freightType = ft;
    }
    headerDiscountPercent = _toDouble(ch['discount_percent']);
  }

  String commissionMode = kPurchaseCommissionModePercent;
  double? commissionPercent;
  double? commissionMoney;
  final bc = scan['broker_commission'];
  if (bc is Map) {
    final t = bc['type']?.toString().trim().toLowerCase();
    final v = _toDouble(bc['value']);
    if (t == 'percent' && v != null) {
      commissionMode = kPurchaseCommissionModePercent;
      commissionPercent = v;
    } else if (v != null) {
      commissionMode = kPurchaseCommissionModeFlatInvoice;
      commissionMoney = v;
    }
  }

  int? paymentDays;
  final pd = scan['payment_days'];
  if (pd is int) {
    paymentDays = pd;
  } else if (pd != null) {
    paymentDays = int.tryParse(pd.toString().trim());
  }

  final inv = scan['invoice_number']?.toString().trim();
  DateTime? purchaseDate = DateTime.now();
  final bd = scan['bill_date']?.toString().trim();
  if (bd != null && bd.length >= 10) {
    purchaseDate = DateTime.tryParse(bd.substring(0, 10)) ?? purchaseDate;
  }

  final itemsRaw = scan['items'];
  final lines = <PurchaseLineDraft>[];
  if (itemsRaw is List) {
    for (final e in itemsRaw) {
      if (e is! Map) continue;
      final it = Map<String, dynamic>.from(e);
      final ut = it['unit_type']?.toString() ?? 'KG';
      final unit = _draftUnitFromScanUnitType(ut);
      final rawName = it['raw_name']?.toString().trim() ?? '';
      final matchedName = it['matched_name']?.toString().trim() ?? '';
      final itemName =
          matchedName.isNotEmpty ? matchedName : (rawName.isNotEmpty ? rawName : 'Item');

      double qty;
      if (ut.toUpperCase() == 'BAG') {
        qty = _toDouble(it['bags']) ?? _toDouble(it['qty']) ?? 0;
      } else if (ut.toUpperCase() == 'KG') {
        qty = _toDouble(it['qty']) ?? _toDouble(it['total_kg']) ?? 0;
      } else {
        qty = _toDouble(it['qty']) ?? 0;
      }

      final catId = it['matched_catalog_item_id']?.toString().trim();
      final pr = _toDouble(it['purchase_rate']) ?? 0;
      final sr = _toDouble(it['selling_rate']);
      final wpu = _toDouble(it['weight_per_unit_kg']);

      double landingCost = pr;
      double? kgPerUnit;
      double? landingCostPerKg;

      if (ut.toUpperCase() == 'BAG' && wpu != null && wpu > 0) {
        kgPerUnit = wpu;
        final rateContext =
            it['rate_context']?.toString().trim().toLowerCase() ?? 'per_bag';
        if (rateContext == 'per_kg') {
          landingCostPerKg = pr;
          landingCost = pr > 0 && wpu > 0 ? pr * wpu : pr;
        } else {
          landingCost = pr;
          landingCostPerKg = pr > 0 && wpu > 0 ? pr / wpu : null;
        }
      }

      lines.add(
        PurchaseLineDraft(
          catalogItemId: (catId != null && catId.isNotEmpty) ? catId : null,
          itemName: itemName,
          qty: qty,
          unit: unit,
          landingCost: landingCost,
          kgPerUnit: kgPerUnit,
          landingCostPerKg: landingCostPerKg,
          sellingPrice: sr,
          taxPercent: _toDouble(it['tax_percent']),
        ),
      );
    }
  }

  return PurchaseDraft(
    supplierId: supplierId,
    supplierName: supplierName,
    brokerId: brokerId,
    brokerName: brokerName,
    brokerIdFromSupplier: null,
    purchaseDate: purchaseDate,
    invoiceNumber: (inv != null && inv.isNotEmpty) ? inv : null,
    paymentDays: paymentDays,
    headerDiscountPercent: headerDiscountPercent,
    commissionMode: PurchaseDraft.normalizeCommissionMode(commissionMode),
    commissionPercent: commissionPercent,
    commissionMoney: commissionMoney,
    deliveredRate: deliveredRate,
    billtyRate: billtyRate,
    freightAmount: freightAmount,
    freightType: freightType,
    lines: lines,
  );
}

Map<String, dynamic> _deepJsonMap(Map<String, dynamic> m) =>
    Map<String, dynamic>.from(jsonMapDeepCopy(m));

dynamic jsonMapDeepCopy(dynamic v) {
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), jsonMapDeepCopy(val)));
  }
  if (v is List) {
    return v.map(jsonMapDeepCopy).toList();
  }
  return v;
}

Map<String, dynamic> _matchMapFromDraft({
  required Map<String, dynamic>? preserve,
  required String? id,
  required String? name,
  required String fallbackRaw,
}) {
  final p = preserve != null
      ? Map<String, dynamic>.from(preserve)
      : <String, dynamic>{
          'raw_text': fallbackRaw,
          'matched_id': null,
          'matched_name': null,
          'confidence': 0.0,
          'match_state': 'unresolved',
          'candidates': <dynamic>[],
        };
  final nid = id?.trim();
  if (nid != null && nid.isNotEmpty) {
    p['matched_id'] = nid;
    final label = (name ?? '').trim();
    if (label.isNotEmpty) p['matched_name'] = label;
    p['match_state'] = 'auto';
    p['confidence'] = 0.99;
  } else {
    p['matched_id'] = null;
    p['matched_name'] = null;
    p['match_state'] = 'unresolved';
    p['confidence'] = 0.0;
  }
  if (p['raw_text'] == null ||
      (p['raw_text'] is String && (p['raw_text'] as String).trim().isEmpty)) {
    p['raw_text'] = fallbackRaw;
  }
  return p;
}

Map<String, dynamic> _itemRowFromDraftLine(
  PurchaseLineDraft line,
  Map<String, dynamic> preserve,
) {
  final ut = _scanUnitTypeFromDraftUnit(line.unit);
  final out = Map<String, dynamic>.from(preserve);

  out['raw_name'] = preserve['raw_name']?.toString().trim().isNotEmpty == true
      ? preserve['raw_name']
      : line.itemName;
  out['matched_name'] = line.itemName;
  if (line.catalogItemId != null && line.catalogItemId!.trim().isNotEmpty) {
    out['matched_catalog_item_id'] = line.catalogItemId;
    out['match_state'] = 'auto';
    out['confidence'] = 0.99;
  } else {
    out['matched_catalog_item_id'] = null;
    out['match_state'] = 'unresolved';
    out['confidence'] = preserve['confidence'] ?? 0.0;
  }

  out['unit_type'] = ut;

  if (ut == 'BAG') {
    final wpu = line.kgPerUnit;
    out['bags'] = line.qty;
    out['qty'] = line.qty;
    if (wpu != null && wpu > 0) {
      out['weight_per_unit_kg'] = wpu;
    } else {
      out['weight_per_unit_kg'] = preserve['weight_per_unit_kg'];
    }
    out['purchase_rate'] = line.landingCost;
    if (line.sellingPrice != null) {
      out['selling_rate'] = line.sellingPrice;
    } else {
      out.remove('selling_rate');
    }
    out['total_kg'] = null;
  } else if (ut == 'KG') {
    out['qty'] = line.qty;
    out['total_kg'] = line.qty;
    out['bags'] = null;
    out['weight_per_unit_kg'] = null;
    out['purchase_rate'] = line.landingCost;
    if (line.sellingPrice != null) {
      out['selling_rate'] = line.sellingPrice;
    } else {
      out.remove('selling_rate');
    }
  } else {
    out['qty'] = line.qty;
    out['bags'] = null;
    out['total_kg'] = null;
    out['weight_per_unit_kg'] = null;
    out['purchase_rate'] = line.landingCost;
    if (line.sellingPrice != null) {
      out['selling_rate'] = line.sellingPrice;
    } else {
      out.remove('selling_rate');
    }
  }

  if (line.taxPercent != null) {
    out['tax_percent'] = line.taxPercent;
  }

  return out;
}

/// Merges [draft] into a copy of [baseScan] so `/scan-purchase-v2/update` accepts it.
/// Preserves warnings, scan_meta, totals, broker_commission, bill_date, scan_token, etc.
Map<String, dynamic> scanResultJsonMergePurchaseDraft(
  Map<String, dynamic> baseScan,
  PurchaseDraft draft,
) {
  final out = _deepJsonMap(baseScan);

  final oldSup = out['supplier'] is Map ? Map<String, dynamic>.from(out['supplier'] as Map) : null;
  out['supplier'] = _matchMapFromDraft(
    preserve: oldSup,
    id: draft.supplierId,
    name: draft.supplierName,
    fallbackRaw: draft.supplierName ?? oldSup?['raw_text']?.toString() ?? '',
  );

  if (draft.brokerId != null && draft.brokerId!.trim().isNotEmpty ||
      (draft.brokerName != null && draft.brokerName!.trim().isNotEmpty)) {
    final oldBr =
        out['broker'] is Map ? Map<String, dynamic>.from(out['broker'] as Map) : null;
    out['broker'] = _matchMapFromDraft(
      preserve: oldBr,
      id: draft.brokerId,
      name: draft.brokerName,
      fallbackRaw: draft.brokerName ?? oldBr?['raw_text']?.toString() ?? '',
    );
  } else {
    out['broker'] = null;
  }

  final oldItems = (out['items'] as List?) ?? [];
  final newItems = <dynamic>[];
  for (var i = 0; i < draft.lines.length; i++) {
    final line = draft.lines[i];
    final old = i < oldItems.length && oldItems[i] is Map
        ? Map<String, dynamic>.from(oldItems[i] as Map)
        : <String, dynamic>{};
    newItems.add(_itemRowFromDraftLine(line, old));
  }
  out['items'] = newItems;

  final ch = out['charges'];
  final chargesOut =
      ch is Map ? Map<String, dynamic>.from(ch) : <String, dynamic>{};
  chargesOut['delivered_rate'] = draft.deliveredRate;
  chargesOut['billty_rate'] = draft.billtyRate;
  chargesOut['freight_amount'] = draft.freightAmount;
  chargesOut['freight_type'] = draft.freightType;
  chargesOut['discount_percent'] = draft.headerDiscountPercent;
  out['charges'] = chargesOut;

  out['payment_days'] = draft.paymentDays;

  if (draft.invoiceNumber != null && draft.invoiceNumber!.trim().isNotEmpty) {
    out['invoice_number'] = draft.invoiceNumber!.trim();
  }

  return out;
}
