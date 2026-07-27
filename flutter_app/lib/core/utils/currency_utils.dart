import 'package:intl/intl.dart';
import '../strict_decimal.dart';

double decDouble(Object? value) {
  if (value == null) return 0;
  try {
    return StrictDecimal.fromObject(value).toDouble();
  } on FormatException {
    return 0;
  }
}

String formatRupee(num n, {bool decimals = false}) =>
    NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: decimals ? 2 : 0,
    ).format(n);
