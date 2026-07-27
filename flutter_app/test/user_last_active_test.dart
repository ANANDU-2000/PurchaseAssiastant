import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/settings/users/user_last_active.dart';

void main() {
  test('Never active when no timestamps', () {
    expect(UserLastActive.label(null), 'Never active');
  });

  test('Created recently for new user without activity', () {
    final created = DateTime.now().toUtc().toIso8601String();
    expect(
      UserLastActive.label(null, createdAtIso: created),
      'Created recently',
    );
  });

  test('Online now within 5 minutes', () {
    final recent = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
    expect(UserLastActive.isOnlineNow(recent.toIso8601String()), isTrue);
  });
}
