import 'package:shared_preferences/shared_preferences.dart';

import '../domain/purchase_draft.dart' show RateTaxBasis;

const _kPurchaseGlobal = 'pref_gst_purchase_rate_basis_v1';
const _kSellingGlobal = 'pref_gst_selling_rate_basis_v1';

String _kPurchaseSupplier(String supplierId) =>
    'pref_gst_purchase_rate_basis_sup_${supplierId.trim()}';

RateTaxBasis? _basisFromPref(String? raw) {
  final s = raw?.trim().toLowerCase();
  if (s == 'included') return RateTaxBasis.includesTax;
  if (s == 'extra') return RateTaxBasis.taxExtra;
  return null;
}

String _basisToPref(RateTaxBasis b) =>
    b == RateTaxBasis.includesTax ? 'included' : 'extra';

/// Remember last GST rate entry mode (global + optional per-supplier for purchase).
class GstRateBasisPrefs {
  GstRateBasisPrefs._();

  static RateTaxBasis? readPurchase(
    SharedPreferences p, {
    String? supplierId,
  }) {
    if (supplierId != null && supplierId.isNotEmpty) {
      final s = _basisFromPref(p.getString(_kPurchaseSupplier(supplierId)));
      if (s != null) return s;
    }
    return _basisFromPref(p.getString(_kPurchaseGlobal));
  }

  static RateTaxBasis? readSelling(SharedPreferences p) =>
      _basisFromPref(p.getString(_kSellingGlobal));

  static Future<void> savePurchase(
    SharedPreferences p,
    RateTaxBasis basis, {
    String? supplierId,
  }) async {
    await p.setString(_kPurchaseGlobal, _basisToPref(basis));
    if (supplierId != null && supplierId.isNotEmpty) {
      await p.setString(_kPurchaseSupplier(supplierId), _basisToPref(basis));
    }
  }

  static Future<void> saveSelling(SharedPreferences p, RateTaxBasis basis) =>
      p.setString(_kSellingGlobal, _basisToPref(basis));
}
