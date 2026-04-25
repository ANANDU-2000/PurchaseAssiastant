import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hexa_purchase_assistant/core/providers/analytics_kpi_provider.dart'
    show analyticsDateRangeProvider;
import 'package:hexa_purchase_assistant/core/providers/home_dashboard_provider.dart'
    show
        homeCustomDateRangeProvider,
        homePeriodProvider,
        homePeriodRange,
        HomePeriod;

void main() {
  test('month preset: home snapshot dates align with reports range for same "today"', () {
    final n = DateTime(2026, 4, 15, 14, 30);
    final today = DateTime(n.year, n.month, n.day);
    final container = ProviderContainer(overrides: [
      homePeriodProvider.overrideWith((ref) => HomePeriod.month),
      homeCustomDateRangeProvider.overrideWith((ref) => null),
      analyticsDateRangeProvider.overrideWith(
        (ref) => (
          from: DateTime(n.year, n.month, 1),
          to: today,
        ),
      ),
    ]);
    addTearDown(container.dispose);

    final h = homePeriodRange(
      HomePeriod.month,
      now: n,
      custom: null,
    );
    final lastInclusive = h.end.subtract(const Duration(milliseconds: 1));
    final homeToYmd = '${lastInclusive.year.toString().padLeft(4, '0')}-'
        '${lastInclusive.month.toString().padLeft(2, '0')}-'
        '${lastInclusive.day.toString().padLeft(2, '0')}';
    final homeFromYmd = '${h.start.year.toString().padLeft(4, '0')}-'
        '${h.start.month.toString().padLeft(2, '0')}-'
        '${h.start.day.toString().padLeft(2, '0')}';

    final reports = container.read(analyticsDateRangeProvider);
    final rFrom = '${reports.from.year.toString().padLeft(4, '0')}-'
        '${reports.from.month.toString().padLeft(2, '0')}-'
        '${reports.from.day.toString().padLeft(2, '0')}';
    final rTo = '${reports.to.year.toString().padLeft(4, '0')}-'
        '${reports.to.month.toString().padLeft(2, '0')}-'
        '${reports.to.day.toString().padLeft(2, '0')}';

    expect(rFrom, homeFromYmd);
    expect(rTo, homeToYmd);
  });
}
