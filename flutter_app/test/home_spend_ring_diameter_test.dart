import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/features/home/presentation/home_spend_ring_diameter.dart';

void main() {
  test('ring diameter never exceeds 200 (hard UI cap)', () {
    expect(
      computeHomeSpendRingDiameter(screenHeight: 1000, layoutMaxWidth: 500),
      200,
    );
  });

  test('tall narrow layout: height term caps before width', () {
    final d = computeHomeSpendRingDiameter(screenHeight: 900, layoutMaxWidth: 280);
    expect(d, lessThanOrEqualTo(220));
    expect(d, lessThanOrEqualTo(200));
    expect(d, closeTo(200.0, 0.01));
  });

  test('small phone: scales down below 200', () {
    final d = computeHomeSpendRingDiameter(screenHeight: 568, layoutMaxWidth: 320);
    final heightTerm = 568 * 0.34;
    expect(heightTerm, lessThan(200));
    expect(d, closeTo(heightTerm, 0.01));
  });

  test('medium Android height term min(34% screen, 220)', () {
    final d = computeHomeSpendRingDiameter(screenHeight: 640, layoutMaxWidth: 360);
    expect(640 * 0.34, closeTo(217.6, 1e-9));
    expect(d, 200.0);
  });
}
