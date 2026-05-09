import 'dart:math' as math;

/// Donut diameter for the Home breakdown ring: bounded by viewport height (~34% cap),
/// absolute max, and available width. Keeps the chart readable on tall phones.
double computeHomeSpendRingDiameter({
  required double screenHeight,
  required double layoutMaxWidth,
}) {
  final maxRing = math.min(screenHeight * 0.34, 220.0);
  return math.min(maxRing, math.min(200.0, layoutMaxWidth * 0.82));
}
