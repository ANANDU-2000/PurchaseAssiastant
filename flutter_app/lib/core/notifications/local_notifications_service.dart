import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/app_config.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Daily summary at 09:00 (Asia/Kolkata when available). No-op on web.
class LocalNotificationsService {
  LocalNotificationsService._();
  static final LocalNotificationsService instance =
      LocalNotificationsService._();

  static const _dailyId = 91001;
  static int _purchaseDueId(String purchaseId) =>
      purchaseId.hashCode & 0x3fffffff;

  final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  Future<void> init() async {
    if (kIsWeb) return;
    if (_inited) return;
    await _p.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        windows: WindowsInitializationSettings(
          appName: AppConfig.appName,
          appUserModelId: 'MyPurchases.PurchaseAssistant.App',
          guid: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
        ),
      ),
    );
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImpl = _p.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
    }
    _inited = true;
  }

  Future<void> setOptIn(bool enabled) async {
    if (kIsWeb || !_inited) return;
    await _p.cancel(id: _dailyId);
    if (!enabled) return;

    final next = _nextNineAm();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'my_purchases_daily',
        'Daily summary',
        channelDescription: 'Reminder to review purchases and margins.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );

    await _p.zonedSchedule(
      id: _dailyId,
      scheduledDate: next,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: AppConfig.appName,
      body: 'Review purchases, margins, and alerts for today.',
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextNineAm() {
    final loc = tz.local;
    final now = tz.TZDateTime.now(loc);
    var scheduled = tz.TZDateTime(loc, now.year, now.month, now.day, 9);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// One shot at 09:00 on the **due** date (from API). No-op on web.
  /// Safe to call after every save — replaces any previous schedule for this purchase id.
  Future<void> scheduleTradePurchaseDueAtNineAmIfNeeded({
    required String purchaseId,
    String? dueDateIso,
    String? humanId,
  }) async {
    if (kIsWeb || !_inited) return;
    if (dueDateIso == null || dueDateIso.isEmpty) return;
    final p = _parseYmd(dueDateIso);
    if (p == null) return;
    final id = _purchaseDueId(purchaseId);
    await _p.cancel(id: id);
    final loc = tz.local;
    var when = tz.TZDateTime(loc, p.$1, p.$2, p.$3, 9, 0);
    final now = tz.TZDateTime.now(loc);
    // If 09:00 on the due date has already passed, still schedule a one-shot
    // reminder shortly (same-day saves after 9am were previously dropped).
    if (!when.isAfter(now)) {
      final dueEnd = tz.TZDateTime(loc, p.$1, p.$2, p.$3, 23, 59, 59);
      if (now.isAfter(dueEnd)) return;
      when = now.add(const Duration(seconds: 10));
    }
    final label = (humanId != null && humanId.isNotEmpty) ? humanId : purchaseId;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'my_purchases_due',
        'Payment due',
        channelDescription: 'Reminders for purchase payment due dates.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );
    await _p.zonedSchedule(
      id: id,
      scheduledDate: when,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Payment may be due',
      body: 'Review payment for $label.',
    );
  }

  (int, int, int)? _parseYmd(String s) {
    if (s.length >= 10) {
      final t = s.substring(0, 10).split('-');
      if (t.length == 3) {
        final y = int.tryParse(t[0]);
        final m = int.tryParse(t[1]);
        final d = int.tryParse(t[2]);
        if (y != null && m != null && d != null) {
          return (y, m, d);
        }
      }
    }
    final p = DateTime.tryParse(s);
    if (p == null) return null;
    return (p.year, p.month, p.day);
  }
}
