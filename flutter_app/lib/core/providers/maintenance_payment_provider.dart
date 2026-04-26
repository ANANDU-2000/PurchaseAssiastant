import 'dart:async' show scheduleMicrotask, unawaited;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hexa_purchase_assistant/core/maintenance/maintenance_month_record.dart';
import 'package:hexa_purchase_assistant/core/maintenance/maintenance_payment_repository.dart';
import 'package:hexa_purchase_assistant/core/maintenance/maintenance_ui_status.dart';
import 'package:hexa_purchase_assistant/core/notifications/local_notifications_service.dart';
import 'package:hexa_purchase_assistant/core/providers/prefs_provider.dart'
    show sharedPreferencesProvider;

const _loadErr = 'Unable to load maintenance data';

class MaintenancePaymentView {
  const MaintenancePaymentView({
    required this.current,
    required this.remindersEnabled,
    required this.status,
    this.userVisibleError,
  });

  final MaintenanceMonthRecord? current;
  final bool remindersEnabled;
  final MaintenanceUiStatus? status;
  final String? userVisibleError;

  MaintenancePaymentView copyWithError(String? err) {
    return MaintenancePaymentView(
      current: current,
      remindersEnabled: remindersEnabled,
      status: status,
      userVisibleError: err,
    );
  }
}

class MaintenancePaymentNotifier
    extends Notifier<AsyncValue<MaintenancePaymentView?>> {
  MaintenancePaymentRepository get _repo =>
      MaintenancePaymentRepository(ref.read(sharedPreferencesProvider));

  @override
  AsyncValue<MaintenancePaymentView?> build() {
    ref.watch(sharedPreferencesProvider);
    return AsyncData(_syncView());
  }

  MaintenancePaymentView _syncView() {
    try {
      final now = DateTime.now();
      _repo.ensureOnAppOpen(now);
      final cur = _repo.currentFor(now);
      final re = _repo.remindersEnabled;
      final st =
          cur == null ? null : maintenanceUiStatus(now: now, record: cur);
      final out = MaintenancePaymentView(
        current: cur,
        remindersEnabled: re,
        status: st,
      );
      if (!kIsWeb) {
        scheduleMicrotask(() {
          unawaited(
            LocalNotificationsService.instance
                .scheduleMaintenanceRemindersIfNeeded(
              enabled: re,
              isPaid: cur?.isPaid ?? false,
              now: DateTime.now(),
            ),
          );
        });
      }
      return out;
    } catch (e, st) {
      assert(() {
        debugPrint('maintenance: $e\n$st');
        return true;
      }());
      return const MaintenancePaymentView(
        current: null,
        remindersEnabled: true,
        status: null,
        userVisibleError: _loadErr,
      );
    }
  }

  void load() {
    state = AsyncData(_syncView());
  }

  Future<void> markPaid() async {
    final v = state.valueOrNull;
    if (v?.current?.isPaid == true) return;
    try {
      final now = DateTime.now();
      await _repo.markCurrentMonthPaid(now);
      if (!kIsWeb) {
        await LocalNotificationsService.instance
            .scheduleMaintenanceRemindersIfNeeded(
          enabled: _repo.remindersEnabled,
          isPaid: true,
          now: now,
        );
      }
      state = AsyncData(_syncView());
    } catch (e, st) {
      assert(() {
        debugPrint('maintenance markPaid: $e\n$st');
        return true;
      }());
      final was = state.valueOrNull;
      state = AsyncData(
        (was ?? _syncView()).copyWithError(_loadErr),
      );
    }
  }

  Future<void> setRemindersEnabled(bool v) async {
    try {
      await _repo.setRemindersEnabled(v);
      final now = DateTime.now();
      if (!kIsWeb) {
        final paid = _repo.currentFor(now)?.isPaid ?? false;
        await LocalNotificationsService.instance
            .scheduleMaintenanceRemindersIfNeeded(
          enabled: v,
          isPaid: paid,
          now: now,
        );
      }
      state = AsyncData(_syncView());
    } catch (e, st) {
      assert(() {
        debugPrint('maintenance reminders: $e\n$st');
        return true;
      }());
      final was = state.valueOrNull;
      state = AsyncData(
        (was ?? _syncView()).copyWithError(_loadErr),
      );
    }
  }
}

final maintenancePaymentControllerProvider = NotifierProvider<
    MaintenancePaymentNotifier,
    AsyncValue<MaintenancePaymentView?>>(MaintenancePaymentNotifier.new);
