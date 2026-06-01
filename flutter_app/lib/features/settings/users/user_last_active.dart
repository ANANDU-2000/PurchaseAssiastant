import 'package:intl/intl.dart';

/// Last-active copy for user list + profile (no "No recent activity").
abstract final class UserLastActive {
  static String label(String? lastActiveIso, {String? createdAtIso}) {
    final d = _parseUtc(lastActiveIso);
    if (d == null) {
      final created = _parseUtc(createdAtIso);
      if (created != null &&
          DateTime.now().difference(created.toLocal()) <
              const Duration(days: 14)) {
        return 'Created recently';
      }
      return 'Never active';
    }
    final local = d.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    if (day == today) {
      return 'Today ${DateFormat.jm().format(local)}';
    }
    if (day == today.subtract(const Duration(days: 1))) {
      return 'Yesterday ${DateFormat.jm().format(local)}';
    }
    if (now.difference(local) < const Duration(days: 7)) {
      return DateFormat('EEE h:mm a').format(local);
    }
    return DateFormat.yMMMd().add_jm().format(local);
  }

  static bool isOnlineNow(String? lastActiveIso) {
    final d = _parseUtc(lastActiveIso);
    if (d == null) return false;
    return DateTime.now().toUtc().difference(d) < const Duration(minutes: 5);
  }

  static DateTime? _parseUtc(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso)?.toUtc();
  }
}

abstract final class UserRoleStyle {
  static String displayRole(String? role) {
    final r = (role ?? '').toLowerCase();
    return switch (r) {
      'owner' => 'Owner',
      'admin' => 'Admin',
      'manager' => 'Manager',
      'staff' => 'Staff',
      _ => r.isEmpty ? '—' : r[0].toUpperCase() + r.substring(1),
    };
  }

  static String statusLabel({required bool blocked, required bool active}) {
    if (blocked) return 'Blocked';
    if (active) return 'Active';
    return 'Inactive';
  }
}
