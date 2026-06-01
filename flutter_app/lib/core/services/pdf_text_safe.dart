/// PDF default fonts (Helvetica / WinAnsi) cannot render rupee, en/em dash,
/// arrows, middle dots, or emoji — they show as black boxes (tofu).
///
/// Run **all** user-facing and template strings through [safePdfText] before
/// passing to `package:pdf` widgets.

/// Empty table cell / missing value in PDFs (ASCII hyphen only).
const String pdfEmpty = '-';

/// Separator for inline PDF lines (replaces middle dot).
const String pdfInlineSep = ' | ';

/// Date range line for PDF headers/footers.
String pdfPeriodRange(String fromLabel, String toLabel) =>
    '$fromLabel - $toLabel';

/// Sanitize strings for PDF output (ASCII-safe).
String safePdfText(String? raw) {
  if (raw == null) return '';
  var s = raw;
  s = s.replaceAll('₹', 'Rs.');
  s = s.replaceAll('—', '-');
  s = s.replaceAll('–', '-');
  s = s.replaceAll('\u2013', '-');
  s = s.replaceAll('\u2014', '-');
  s = s.replaceAll('→', ' to ');
  s = s.replaceAll('←', '<-');
  s = s.replaceAll('↔', '<->');
  s = s.replaceAll('·', pdfInlineSep);
  s = s.replaceAll('•', '-');
  s = s.replaceAll('…', '...');
  s = s.replaceAll('’', "'");
  s = s.replaceAll('‘', "'");
  s = s.replaceAll('“', '"');
  s = s.replaceAll('”', '"');
  s = s.replaceAll('\uFFFD', '');
  s = s.replaceAll('\u0000', '');
  // Strip emoji / symbols outside basic Latin + common punctuation.
  s = s.replaceAll(
    RegExp(
      r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
      unicode: true,
    ),
    '',
  );
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  return s;
}

/// Like [safePdfText] but returns [pdfEmpty] when blank after sanitize.
String safePdfCell(String? raw) {
  final t = safePdfText(raw);
  return t.isEmpty ? pdfEmpty : t;
}
