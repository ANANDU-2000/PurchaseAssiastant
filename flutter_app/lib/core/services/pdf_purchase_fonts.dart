import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

/// Loads Noto Sans + Malayalam fallback for purchase PDFs (Unicode / Malayalam names).
Future<pw.ThemeData> loadPurchasePdfTheme() async {
  final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
  final malayalam = await rootBundle.load('assets/fonts/NotoSansMalayalam-Regular.ttf');
  final base = pw.Font.ttf(regular);
  final b = pw.Font.ttf(bold);
  final ml = pw.Font.ttf(malayalam);
  return pw.ThemeData.withFont(
    base: base,
    bold: b,
    fontFallback: [ml],
  );
}
