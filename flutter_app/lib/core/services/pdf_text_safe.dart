/// Sanitize strings for the PDF package default fonts (WinAnsi): avoid rupee
/// glyph, en/em dash, and other non-encodable characters in user-supplied text.
String safePdfText(String? raw) {
  if (raw == null) return '';
  return raw
      .replaceAll('₹', 'Rs. ')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('\u2013', '-')
      .replaceAll('\u2014', '-');
}
