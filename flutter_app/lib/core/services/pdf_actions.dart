import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'pdf_download_io.dart' if (dart.library.html) 'pdf_download_web.dart'
    as platform_pdf;
import 'pdf_locale.dart';
import 'pdf_action_result.dart';

export 'pdf_action_result.dart' show PdfActionResult;

Future<pw.ImageProvider?> tryFetchPdfLogo(String? url) async {
  final u = url?.trim();
  if (u == null || u.isEmpty) return null;
  try {
    final r = await Dio().get<List<int>>(
      u,
      options: Options(
        responseType: ResponseType.bytes,
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 4),
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    );
    final data = r.data;
    if (data == null || data.isEmpty || data.length > 2 * 1024 * 1024) {
      return null;
    }
    return pw.MemoryImage(Uint8List.fromList(data));
  } catch (_) {
    return null;
  }
}

void logPdfFailure(String source, String op, Object e, StackTrace st) {
  debugPrint('PDF $source/$op failed: $e\n$st');
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: e,
      stack: st,
      library: source,
      context: ErrorDescription('PDF $op failed'),
      silent: true,
    ),
  );
}

Future<PdfActionResult> sharePdfBytes({
  required Future<Uint8List> Function() buildBytes,
  required String filename,
  required String subject,
  String source = 'pdf_actions',
}) async {
  try {
    await ensurePdfLocalesInitialized();
    final bytes = await buildBytes();
    try {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (_) {
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: filename,
          ),
        ],
        subject: subject,
      );
    }
    return const PdfActionResult(ok: true, message: 'PDF ready to share');
  } catch (e, st) {
    logPdfFailure(source, 'share', e, st);
    return const PdfActionResult(
      ok: false,
      message: 'Could not export PDF. Check connection and retry.',
    );
  }
}

Future<PdfActionResult> printPdfBytes({
  required Future<Uint8List> Function() buildBytes,
  required String filename,
  String source = 'pdf_actions',
}) async {
  try {
    await ensurePdfLocalesInitialized();
    await Printing.layoutPdf(
      name: filename,
      onLayout: (_) => buildBytes(),
    );
    return const PdfActionResult(ok: true, message: 'Print dialog opened');
  } catch (e, st) {
    logPdfFailure(source, 'print', e, st);
    return const PdfActionResult(
      ok: false,
      message: 'Could not print PDF. Try again.',
    );
  }
}

Future<PdfActionResult> savePdfBytes({
  required Future<Uint8List> Function() buildBytes,
  required String filename,
  required String subject,
  String source = 'pdf_actions',
}) async {
  try {
    await ensurePdfLocalesInitialized();
    final bytes = await buildBytes();
    final downloaded = await platform_pdf.downloadPdfBytes(bytes, filename);
    if (downloaded) {
      return const PdfActionResult(ok: true, message: 'PDF download started');
    }
    try {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (_) {
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: filename,
          ),
        ],
        subject: subject,
      );
    }
    return const PdfActionResult(
        ok: true, message: 'PDF ready to save or share');
  } catch (e, st) {
    logPdfFailure(source, 'save', e, st);
    return const PdfActionResult(
      ok: false,
      message: 'Could not save PDF. Try again.',
    );
  }
}
