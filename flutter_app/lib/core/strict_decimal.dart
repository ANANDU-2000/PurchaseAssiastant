import 'dart:math' as math;

/// Fixed-precision decimal for purchase accounting paths.
///
/// It stores a base-10 integer and scale, so calculations avoid binary floating
/// point drift. UI models still expose some doubles for compatibility, but all
/// purchase totals can be computed through this type before final display.
class StrictDecimal implements Comparable<StrictDecimal> {
  const StrictDecimal._(this._units, this.scale);

  factory StrictDecimal.zero() => StrictDecimal._(BigInt.zero, 0);

  factory StrictDecimal.fromObject(Object? value) {
    if (value == null) return StrictDecimal.zero();
    if (value is StrictDecimal) return value;
    return StrictDecimal.parse(value.toString());
  }

  factory StrictDecimal.parse(String raw, {bool allowNegative = false}) {
    final s = raw.trim().replaceAll(',', '');
    if (s.isEmpty) return StrictDecimal.zero();
    final re = allowNegative
        ? RegExp(r'^-?\d+(\.\d+)?$')
        : RegExp(r'^\d+(\.\d+)?$');
    if (!re.hasMatch(s)) {
      throw FormatException('Invalid decimal', raw);
    }
    final neg = s.startsWith('-');
    final body = neg ? s.substring(1) : s;
    final parts = body.split('.');
    final whole = parts[0].isEmpty ? '0' : parts[0];
    final frac = parts.length > 1 ? parts[1] : '';
    var units = BigInt.parse('$whole$frac');
    if (neg) units = -units;
    return StrictDecimal._(units, frac.length)._trim();
  }

  final BigInt _units;
  final int scale;

  bool get isZero => _units == BigInt.zero;
  bool get isNegative => _units < BigInt.zero;
  bool get isPositive => _units > BigInt.zero;

  static BigInt _pow10(int n) => BigInt.from(10).pow(n);

  StrictDecimal _trim() {
    if (_units == BigInt.zero) return StrictDecimal.zero();
    var u = _units;
    var s = scale;
    while (s > 0 && u % BigInt.from(10) == BigInt.zero) {
      u ~/= BigInt.from(10);
      s--;
    }
    return StrictDecimal._(u, s);
  }

  StrictDecimal toScale(int targetScale) {
    if (targetScale == scale) return this;
    if (targetScale > scale) {
      return StrictDecimal._(_units * _pow10(targetScale - scale), targetScale);
    }
    final factor = _pow10(scale - targetScale);
    final half = factor ~/ BigInt.from(2);
    final sign = _units < BigInt.zero ? -1 : 1;
    final abs = _units.abs();
    final rounded = (abs + half) ~/ factor;
    return StrictDecimal._(sign < 0 ? -rounded : rounded, targetScale);
  }

  BigInt _alignedUnits(int targetScale) {
    if (targetScale == scale) return _units;
    return _units * _pow10(targetScale - scale);
  }

  StrictDecimal operator +(StrictDecimal other) {
    final s = math.max(scale, other.scale);
    return StrictDecimal._(_alignedUnits(s) + other._alignedUnits(s), s)._trim();
  }

  StrictDecimal operator -(StrictDecimal other) {
    final s = math.max(scale, other.scale);
    return StrictDecimal._(_alignedUnits(s) - other._alignedUnits(s), s)._trim();
  }

  StrictDecimal operator *(StrictDecimal other) =>
      StrictDecimal._(_units * other._units, scale + other.scale)._trim();

  StrictDecimal divide(StrictDecimal other, {int scale = 6}) {
    if (other._units == BigInt.zero) return StrictDecimal.zero();
    final numerator = _units * _pow10(scale + other.scale);
    final denominator = other._units * _pow10(this.scale);
    final q = numerator ~/ denominator;
    final r = numerator.remainder(denominator).abs();
    final roundUp = r * BigInt.from(2) >= denominator.abs();
    return StrictDecimal._(roundUp ? q + BigInt.from(q < BigInt.zero ? -1 : 1) : q, scale)
        ._trim();
  }

  StrictDecimal percentOf(StrictDecimal percent) =>
      (this * percent).divide(StrictDecimal.parse('100'), scale: 6);

  StrictDecimal clamp({StrictDecimal? min, StrictDecimal? max}) {
    var v = this;
    if (min != null && v.compareTo(min) < 0) v = min;
    if (max != null && v.compareTo(max) > 0) v = max;
    return v;
  }

  double toDouble() => double.parse(toPlainString());

  String toPlainString() {
    final neg = _units < BigInt.zero;
    final abs = _units.abs().toString().padLeft(scale + 1, '0');
    if (scale == 0) return neg ? '-$abs' : abs;
    final split = abs.length - scale;
    final out = '${abs.substring(0, split)}.${abs.substring(split)}';
    return neg ? '-$out' : out;
  }

  String format(int decimals, {bool trim = false}) {
    final rounded = toScale(decimals);
    var s = rounded.toPlainString();
    if (decimals == 0) return s.split('.').first;
    if (!s.contains('.')) s = '$s.${''.padRight(decimals, '0')}';
    final parts = s.split('.');
    s = '${parts[0]}.${parts[1].padRight(decimals, '0')}';
    if (trim) {
      s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return s;
  }

  @override
  int compareTo(StrictDecimal other) {
    final s = math.max(scale, other.scale);
    return _alignedUnits(s).compareTo(other._alignedUnits(s));
  }

  @override
  String toString() => toPlainString();
}

bool isValidNonNegativeDecimalInput(String raw, {int maxDecimals = 3}) {
  final s = raw.trim();
  if (s.isEmpty) return true;
  return RegExp('^\\d+(\\.\\d{0,$maxDecimals})?\$').hasMatch(s);
}
