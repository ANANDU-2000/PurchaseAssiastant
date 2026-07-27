import '../../../core/services/prefs_helper.dart';

/// Remembers last supplier/broker/type on catalog item create (per business).
class CatalogCreatePrefs {
  static String _supplierKey(String businessId) =>
      'catalog_create_supplier_$businessId';
  static String _brokerKey(String businessId) =>
      'catalog_create_broker_$businessId';
  static String _typeKey(String businessId) => 'catalog_create_type_$businessId';

  static Future<
      ({
        String? supplierId,
        String? brokerId,
        String? typeId,
      })> load(String businessId) async {
    final sp = PrefsHelper.prefs;
    return (
      supplierId: sp.getString(_supplierKey(businessId)),
      brokerId: sp.getString(_brokerKey(businessId)),
      typeId: sp.getString(_typeKey(businessId)),
    );
  }

  static Future<void> save({
    required String businessId,
    String? supplierId,
    String? brokerId,
    String? typeId,
  }) async {
    final sp = PrefsHelper.prefs;
    final sup = supplierId?.trim();
    final bro = brokerId?.trim();
    final typ = typeId?.trim();
    final futures = <Future<void>>[];
    if (sup == null || sup.isEmpty) {
      futures.add(sp.remove(_supplierKey(businessId)));
    } else {
      futures.add(sp.setString(_supplierKey(businessId), sup));
    }
    if (bro == null || bro.isEmpty) {
      futures.add(sp.remove(_brokerKey(businessId)));
    } else {
      futures.add(sp.setString(_brokerKey(businessId), bro));
    }
    if (typ == null || typ.isEmpty) {
      futures.add(sp.remove(_typeKey(businessId)));
    } else {
      futures.add(sp.setString(_typeKey(businessId), typ));
    }
    await Future.wait(futures);
  }
}
