import 'dart:math' as math;

/// Donut diameter for the Home breakdown ring: bounded by viewport height (~34% cap),
/// absolute max, and available width. Keeps the chart readable on tall phones.
double computeHomeSpendRingDiameter({
  required double screenHeight,
  required double layoutMaxWidth,
}) {
  // Web / device-toolbar can briefly report 0, NaN, or infinity — avoid a 0px
  // ring or invalid constraints that break the whole Home layout.
  final sh = (!screenHeight.isFinite || screenHeight <= 0)
      ? 800.0
      : screenHeight.clamp(320.0, 5000.0);
  final lw = (!layoutMaxWidth.isFinite || layoutMaxWidth <= 0)
      ? 360.0
      : layoutMaxWidth.clamp(120.0, 2000.0);
  final maxRing = math.min(sh * 0.34, 220.0);
  final raw = math.min(maxRing, math.min(200.0, lw * 0.82));
  return raw.clamp(96.0, 220.0);
}
