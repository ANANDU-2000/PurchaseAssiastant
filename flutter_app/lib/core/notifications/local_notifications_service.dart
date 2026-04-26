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
  static const int _maintId0 = 92101;
  static const int _maintId1 = 92102;
  static const int _maintId2 = 92103;
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

  /// iOS: request alert/badge/sound (safe to call repeatedly; OS dedupes).
  Future<void> requestIosNotificationPermission() async {
    if (kIsWeb || !_inited) return;
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    final ios = _p.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
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
      body: 'If settled, mark paid in History. Ref: $label',
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

  /// Fixed ids for maintenance — always cancel all three before rescheduling.
  Future<void> cancelMaintenanceReminders() async {
    if (kIsWeb) return;
    await _p.cancel(id: _maintId0);
    await _p.cancel(id: _maintId1);
    await _p.cancel(id: _maintId2);
  }

  /// Up to 3 notifications, 24h apart: last day 09:00, +24h, +24h. If t0 is past,
  /// roll to [now+10s, +24h, +48h] so nothing stacks in the past.
  Future<void> scheduleMaintenanceRemindersIfNeeded({
    required bool enabled,
    required bool isPaid,
    required DateTime now,
  }) async {
    if (kIsWeb || !_inited) {
      if (!kIsWeb) {
        await cancelMaintenanceReminders();
      }
      return;
    }
    await cancelMaintenanceReminders();
    if (!enabled || isPaid) return;

    final loc = tz.local;
    final nowTz = tz.TZDateTime.from(now, loc);
    final y = nowTz.year;
    final m = nowTz.month;
    final lastD = DateTime(y, m + 1, 0).day;
    var t0 = tz.TZDateTime(loc, y, m, lastD, 9, 0);
    const spacing = Duration(hours: 24);
    const catchUpStart = Duration(seconds: 10);

    tz.TZDateTime t1;
    tz.TZDateTime t2;
    if (!t0.isAfter(nowTz)) {
      // First slot in the past: roll all three to future with 24h spacing.
      final s0 = nowTz.add(catchUpStart);
      t1 = s0.add(spacing);
      t2 = t1.add(spacing);
      await _zonedScheduleMaintenance(
        _maintId0,
        s0,
        'Monthly maintenance',
        '₹2500 due — last day of month. Pay via UPI from Home.',
      );
      await _zonedScheduleMaintenance(
        _maintId1,
        t1,
        'Maintenance reminder',
        '₹2500 still due this month. Open the app to pay or mark paid.',
      );
      await _zonedScheduleMaintenance(
        _maintId2,
        t2,
        'Final maintenance reminder',
        '₹2500 before month ends. Check Home to complete payment.',
      );
    } else {
      t1 = t0.add(spacing);
      t2 = t1.add(spacing);
      await _zonedScheduleMaintenance(
        _maintId0,
        t0,
        'Monthly maintenance',
        '₹2500 due — last day of month 9:00. Pay via UPI from Home.',
      );
      await _zonedScheduleMaintenance(
        _maintId1,
        t1,
        'Maintenance reminder',
        '₹2500 still due this month. Open the app to pay or mark paid.',
      );
      await _zonedScheduleMaintenance(
        _maintId2,
        t2,
        'Final maintenance reminder',
        '₹2500 before month ends. Check Home to complete payment.',
      );
    }
  }

  static const _maintDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'maintenance_payment',
      'Maintenance payment',
      channelDescription: 'Reminders for monthly app maintenance (₹2500).',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  Future<void> _zonedScheduleMaintenance(
    int id,
    tz.TZDateTime when,
    String title,
    String body,
  ) async {
    await _p.zonedSchedule(
      id: id,
      scheduledDate: when,
      notificationDetails: _maintDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
    );
  }
}
