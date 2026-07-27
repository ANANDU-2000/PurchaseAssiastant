import '../api/hexa_api.dart';
import '../models/business_profile.dart';
import '../models/trade_purchase_models.dart';
import '../../features/notifications/data/notifications_repository.dart';
import 'pdf_actions.dart';
import 'pdf_locale.dart';
import 'purchase_pdf.dart';

/// Result of pre-export validation.
class PurchaseExportValidation {
  const PurchaseExportValidation({required this.ok, this.message});

  final bool ok;
  final String? message;

  static const _unableExport =
      'Unable to export PDF. Please try again.';
  static const _unablePrint = 'Unable to print PDF. Please try again.';
  static const _unableShare = 'Unable to share PDF. Please try again.';
}

PurchaseExportValidation validatePurchaseForExport(TradePurchase p) {
  if (p.lines.isEmpty) {
    return const PurchaseExportValidation(
      ok: false,
      message: 'This purchase has no line items to export.',
    );
  }
  if (!p.totalAmount.isFinite || p.totalAmount < 0) {
    return const PurchaseExportValidation(
      ok: false,
      message: PurchaseExportValidation._unableExport,
    );
  }
  for (final l in p.lines) {
    if (!l.qty.isFinite || l.qty < 0) {
      return const PurchaseExportValidation(
        ok: false,
        message: 'One or more line quantities are invalid.',
      );
    }
  }
  return const PurchaseExportValidation(ok: true);
}

Future<void> _reportExportFailure(
  TradePurchase p,
  String operation, {
  HexaApi? api,
  String? businessId,
}) async {
  if (api == null || businessId == null) return;
  try {
    await NotificationsRepository(api).reportExportFailed(
      businessId: businessId,
      purchaseId: p.id,
      humanId: p.humanId,
      operation: operation,
    );
  } catch (_) {}
}

final Set<String> _exportInFlightPurchaseIds = <String>{};

/// Serializes PDF/share/export for one purchase id (double-tap safe).
Future<PdfActionResult> runGuardedPurchasePdfAction({
  required String purchaseId,
  required Future<PdfActionResult> Function() action,
  String busyMessage = 'Export already in progress for this purchase.',
}) async {
  if (_exportInFlightPurchaseIds.contains(purchaseId)) {
    return PdfActionResult(ok: false, message: busyMessage);
  }
  _exportInFlightPurchaseIds.add(purchaseId);
  try {
    return await action();
  } finally {
    _exportInFlightPurchaseIds.remove(purchaseId);
  }
}

Future<PdfActionResult> _runExport({
  required TradePurchase p,
  required BusinessProfile biz,
  required Future<PdfActionResult> Function() action,
  required String failureMessage,
  required String operationLabel,
  HexaApi? api,
  String? businessId,
}) async {
  return runGuardedPurchasePdfAction(
    purchaseId: p.id,
    action: () => _runExportInner(
      p: p,
      biz: biz,
      action: action,
      failureMessage: failureMessage,
      operationLabel: operationLabel,
      api: api,
      businessId: businessId,
    ),
  );
}

Future<PdfActionResult> _runExportInner({
  required TradePurchase p,
  required BusinessProfile biz,
  required Future<PdfActionResult> Function() action,
  required String failureMessage,
  required String operationLabel,
  HexaApi? api,
  String? businessId,
}) async {
  await ensurePdfLocalesInitialized();
  final validation = validatePurchaseForExport(p);
  if (!validation.ok) {
    return PdfActionResult(ok: false, message: validation.message ?? failureMessage);
  }
  try {
    final result = await action();
    if (!result.ok) {
      await _reportExportFailure(p, operationLabel, api: api, businessId: businessId);
    }
    return result;
  } catch (_) {
    await _reportExportFailure(p, operationLabel, api: api, businessId: businessId);
    return PdfActionResult(ok: false, message: failureMessage);
  }
}

Future<PdfActionResult> exportSharePurchase(
  TradePurchase p,
  BusinessProfile biz, {
  HexaApi? api,
  String? businessId,
}) {
  return _runExport(
    p: p,
    biz: biz,
    failureMessage: PurchaseExportValidation._unableShare,
    operationLabel: 'share',
    api: api,
    businessId: businessId,
    action: () => sharePurchasePdf(p, biz),
  );
}

Future<PdfActionResult> exportPrintPurchase(
  TradePurchase p,
  BusinessProfile biz, {
  HexaApi? api,
  String? businessId,
}) {
  return _runExport(
    p: p,
    biz: biz,
    failureMessage: PurchaseExportValidation._unablePrint,
    operationLabel: 'print',
    api: api,
    businessId: businessId,
    action: () => printPurchasePdf(p, biz),
  );
}

Future<PdfActionResult> exportDownloadPurchase(
  TradePurchase p,
  BusinessProfile biz, {
  HexaApi? api,
  String? businessId,
}) {
  return _runExport(
    p: p,
    biz: biz,
    failureMessage: PurchaseExportValidation._unableExport,
    operationLabel: 'export',
    api: api,
    businessId: businessId,
    action: () => downloadPurchasePdf(p, biz),
  );
}
