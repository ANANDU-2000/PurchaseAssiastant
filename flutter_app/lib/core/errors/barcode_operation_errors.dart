import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import '../auth/auth_error_messages.dart';

enum BarcodeOperationKind {
  pdfGeneration,
  barcodeRender,
  printUnavailable,
  batchPartial,
  cameraPermission,
  photoUnreadable,
  unreadableScan,
  emptyDecode,
  ambiguousBarcode,
  network,
  emptySelection,
  permissionDenied,
  unknown,
}

enum BarcodeOperationContext { bulkPrint, singlePrint, scanner, preview }

class BarcodeOperationException implements Exception {
  BarcodeOperationException(
    this.message, {
    this.kind = BarcodeOperationKind.unknown,
    this.cause,
    this.failedItemIds = const [],
  });

  final String message;
  final BarcodeOperationKind kind;
  final Object? cause;
  final List<String> failedItemIds;

  @override
  String toString() => message;
}

/// Stable scanner copy — keep UI panel + Dio 404 aligned.
const kBarcodeUnknownCatalogMessage =
    'Unknown barcode — not in your catalog. Assign it or create a new item.';

const kBarcodeUnreadableMessage =
    "Couldn't read that — try again or enter the code manually.";

const kBarcodeAmbiguousMessage =
    'Multiple items share this barcode. Fix duplicates in catalog, then scan again.';

const kBarcodeNetworkMessage =
    "Couldn't reach server. Retry or enter the code manually.";

const kBarcodePermissionDeniedMessage =
    "Your account doesn't have permission for this action.";

const kBarcodeEmptyDecodeMessage =
    "Couldn't read that — try again or enter the code manually.";

const kBarcodeCameraPermissionMessage =
    'Allow camera access to scan barcodes, or enter the code manually.';

/// Reject empty / control-heavy / absurd scanner library garbage before lookup.
bool isGarbageBarcodeDecode(String? raw) {
  final code = raw?.trim() ?? '';
  if (code.isEmpty) return true;
  if (code.length > 128) return true;
  // Mostly non-printable / control characters.
  final printable = code.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
  if (printable.isEmpty) return true;
  if (printable.length < code.length ~/ 2) return true;
  return false;
}

BarcodeOperationException barcodeEmptyDecodeError() => BarcodeOperationException(
      kBarcodeEmptyDecodeMessage,
      kind: BarcodeOperationKind.emptyDecode,
    );

BarcodeOperationException barcodeUnreadableError() => BarcodeOperationException(
      kBarcodeUnreadableMessage,
      kind: BarcodeOperationKind.unreadableScan,
    );

BarcodeOperationException barcodePhotoUnreadableError() =>
    BarcodeOperationException(
      kBarcodeUnreadableMessage,
      kind: BarcodeOperationKind.photoUnreadable,
    );

BarcodeOperationException barcodeNetworkError([Object? cause]) =>
    BarcodeOperationException(
      kBarcodeNetworkMessage,
      kind: BarcodeOperationKind.network,
      cause: cause,
    );

BarcodeOperationException barcodeCameraPermissionError([String? detail]) =>
    BarcodeOperationException(
      detail?.trim().isNotEmpty == true
          ? detail!.trim()
          : kBarcodeCameraPermissionMessage,
      kind: BarcodeOperationKind.cameraPermission,
    );

/// User-safe message for barcode/PDF/print/scanner flows (no generic "Something went wrong").
String barcodeMessageForUser(
  Object error, {
  BarcodeOperationContext ctx = BarcodeOperationContext.bulkPrint,
}) {
  if (error is BarcodeOperationException) return error.message;
  if (error is TimeoutException) {
    return kBarcodeNetworkMessage;
  }
  if (error is DioException) {
    final sc = error.response?.statusCode;
    if (ctx == BarcodeOperationContext.scanner) {
      if (sc == 404) return kBarcodeUnknownCatalogMessage;
      if (sc == 403) return kBarcodePermissionDeniedMessage;
      if (sc == 409) {
        final detail = error.response?.data;
        if (detail is Map &&
            (detail['detail']?.toString().toLowerCase().contains('ambiguous') ==
                    true ||
                detail['detail']?.toString().toLowerCase().contains('multiple') ==
                    true)) {
          return kBarcodeAmbiguousMessage;
        }
        if (detail is String &&
            (detail.toLowerCase().contains('ambiguous') ||
                detail.toLowerCase().contains('multiple'))) {
          return kBarcodeAmbiguousMessage;
        }
        // Scanner 409 default = ambiguous barcode data issue.
        return kBarcodeAmbiguousMessage;
      }
      if (sc == null ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.connectionError) {
        return kBarcodeNetworkMessage;
      }
    }
    return friendlyApiError(error);
  }
  final s = error.toString().toLowerCase();
  if (s.contains('printing') || s.contains('print')) {
    return 'Print is not available on this device. Download the PDF instead.';
  }
  if (s.contains('barcode') && (s.contains('empty') || s.contains('invalid'))) {
    return 'Barcode image could not be generated. Check item codes and barcodes.';
  }
  if (s.contains('pdf') || s.contains('document')) {
    return 'PDF generation failed. Try fewer items or switch label format.';
  }
  if (error is StateError || error is ArgumentError) {
    return error.toString().replaceFirst(RegExp(r'^[^:]*:\s*'), '');
  }
  switch (ctx) {
    case BarcodeOperationContext.scanner:
      return 'Scan could not complete. Try again or enter the code manually.';
    case BarcodeOperationContext.singlePrint:
      return 'Could not prepare this label. Check barcode and item code.';
    case BarcodeOperationContext.preview:
    case BarcodeOperationContext.bulkPrint:
      if (s.contains('infinity') ||
          s.contains('nan') ||
          s.contains('unsupported operation')) {
        return 'Some label numbers were invalid. Try A4 + Code128, or fewer items per batch.';
      }
      if (s.contains('too big') ||
          s.contains('memory') ||
          s.contains('overflow') ||
          s.contains('widget')) {
        return 'PDF too large for browser. Use A4 + Code128 and try 50 items.';
      }
      return 'Could not prepare labels. Use A4 + Code128, or fewer items per batch.';
  }
}

void logBarcodeOperationError(Object error, [StackTrace? stack]) {
  if (!kDebugMode) return;
  debugPrint('[BarcodeOp] $error');
  if (stack != null) debugPrint('$stack');
}

Future<void> guardWebPrint(Future<void> Function() printAction) async {
  final info = await Printing.info();
  if (!info.canPrint) {
    throw BarcodeOperationException(
      'Print is not available in this browser. Use PDF to download or share.',
      kind: BarcodeOperationKind.printUnavailable,
    );
  }
  await printAction();
}
