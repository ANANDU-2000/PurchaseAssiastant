import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/app_config.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Daily summary at 09:00 (Asia/Kolkata when available). No-op on web.
class LocalNotificationsService {
  LocalNotificationsService._();
  static final LocalNotificationsService instance = LocalNotificationsService._();

  static const _dailyId = 91001;
  final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  Future<void> init() async {
    if (kIsWeb) return;
    if (_inited) return;
    await _p.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: const DarwinInitializationSettings(),
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
      final androidImpl = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
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
}
