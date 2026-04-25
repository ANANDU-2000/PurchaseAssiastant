// Amount-in-words for purchase PDFs (shared by receipt and full invoice).

String twoDigitsBelow100(int n) {
  const units = [
    '', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
    'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
    'seventeen', 'eighteen', 'nineteen',
  ];
  const tens = [
    '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety',
  ];
  if (n < 20) return units[n];
  final t = n ~/ 10;
  final u = n % 10;
  return u == 0 ? tens[t] : '${tens[t]} ${units[u]}';
}

String belowThousand(int n) {
  if (n < 100) return twoDigitsBelow100(n);
  final h = n ~/ 100;
  final rest = n % 100;
  final hs = '${twoDigitsBelow100(h)} hundred';
  if (rest == 0) return hs;
  return '$hs ${twoDigitsBelow100(rest)}';
}

String _cap(String s) {
  if (s.isEmpty) return s;
  return '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Indian numbering (lakh / crore) for invoice amount in words.
String amountInWordsInr(double amount) {
  var n = amount.floor();
  final paise = ((amount - n) * 100).round().clamp(0, 99);
  if (n == 0 && paise == 0) return 'Zero rupees only';

  final parts = <String>[];
  if (n >= 10000000) {
    parts.add('${belowThousand(n ~/ 10000000)} crore');
    n %= 10000000;
  }
  if (n >= 100000) {
    parts.add('${belowThousand(n ~/ 100000)} lakh');
    n %= 100000;
  }
  if (n >= 1000) {
    parts.add('${belowThousand(n ~/ 1000)} thousand');
    n %= 1000;
  }
  if (n > 0) {
    parts.add(belowThousand(n));
  }
  var rupees = parts.join(' ').trim();
  if (rupees.isEmpty) rupees = 'zero';
  rupees = '${rupees[0].toUpperCase()}${rupees.substring(1)} rupees';
  if (paise > 0) {
    final p = twoDigitsBelow100(paise);
    return '$rupees and ${_cap(p)} paise only';
  }
  return '$rupees only';
}
