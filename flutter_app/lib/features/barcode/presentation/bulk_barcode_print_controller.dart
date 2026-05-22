import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/barcode_operation_errors.dart';
import '../../../core/router/post_auth_route.dart';
import '../services/barcode_pdf_service.dart';
import '../services/bulk_label_batch.dart';

Future<BulkLabelBatchResult> fetchBulkLabels({
  required WidgetRef ref,
  required List<String> ids,
  void Function(int done, int total)? onProgress,
}) async {
  final session = ref.read(sessionProvider);
  if (session == null || ids.isEmpty) {
    return const BulkLabelBatchResult(labels: []);
  }
  const chunkSize = 200;
  final api = ref.read(hexaApiProvider);
  final labels = <BarcodeLabelData>[];
  final failedIds = <String>[];
  final failuresById = <String, String>{};

  for (var i = 0; i < ids.length; i += chunkSize) {
    final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
    final chunk = ids.sublist(i, end);
    onProgress?.call(end, ids.length);
    try {
      final rows = await api.barcodeLabelBatch(
        businessId: session.primaryBusiness.id,
        itemIds: chunk,
      );
      final returned = <String>{};
      for (final j in rows) {
        final id = j['id']?.toString() ?? j['item_id']?.toString() ?? '';
        final label = BarcodeLabelData.fromApiMap(j);
        if (label != null) {
          labels.add(label);
          if (id.isNotEmpty) returned.add(id);
        } else if (id.isNotEmpty) {
          failedIds.add(id);
          failuresById[id] = 'Missing barcode and item code';
        }
      }
      for (final id in chunk) {
        if (!returned.contains(id) && !failedIds.contains(id)) {
          failedIds.add(id);
          failuresById[id] ??= 'No label data returned';
        }
      }
    } on DioException catch (e) {
      for (final id in chunk) {
        failedIds.add(id);
        failuresById[id] = friendlyApiError(e);
      }
    } catch (e) {
      for (final id in chunk) {
        failedIds.add(id);
        failuresById[id] = barcodeMessageForUser(e);
      }
    }
  }
  return BulkLabelBatchResult(
    labels: labels,
    failedIds: failedIds,
    failuresById: failuresById,
  );
}

Future<Uint8List> generateBulkPdfBytes({
  required BuildContext context,
  required WidgetRef ref,
  required BulkLabelBatchResult batch,
  required bool denseA4,
  required int copies,
  required int perRow,
  required BarcodeSymbolMode symbol,
  required LabelSize thermalSize,
}) async {
  if (batch.labels.isEmpty) {
    throw BarcodeOperationException(
      'No printable labels in selection.',
      kind: BarcodeOperationKind.emptySelection,
    );
  }
  final session = ref.read(sessionProvider);
  final hideFinancials =
      session != null && !sessionCanSeeFinancials(session);
  try {
    if (denseA4) {
      final cols = MediaQuery.sizeOf(context).width >= 600 ? 4 : 2;
      return await BarcodePdfService.generateBatchA4Dense(
        items: batch.labels,
        size: thermalSize,
        copiesPerItem: copies,
        hideFinancials: hideFinancials,
        columns: cols,
      );
    }
    return await BarcodePdfService.generateBatch(
      items: batch.labels,
      size: thermalSize,
      copiesPerItem: copies,
      labelsPerRow: perRow,
      hideFinancials: hideFinancials,
      symbol: symbol,
    );
  } catch (e, st) {
    logBarcodeOperationError(e, st);
    if (e is BarcodeOperationException) rethrow;
    throw BarcodeOperationException(
      barcodeMessageForUser(e, ctx: BarcodeOperationContext.bulkPrint),
      kind: BarcodeOperationKind.pdfGeneration,
      cause: e,
    );
  }
}

Future<bool?> showPartialLabelFailureDialog(
  BuildContext context,
  BulkLabelBatchResult batch,
) {
  if (!batch.hasPartialFailure) return Future.value(true);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Some labels failed'),
      content: Text(
        '${batch.failedIds.length} labels failed.\n'
        '${batch.labels.length} labels generated successfully.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
}
