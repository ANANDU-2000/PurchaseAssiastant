import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hexa_purchase_assistant/core/cloud/cloud_payment_local_repository.dart';
import 'package:hexa_purchase_assistant/core/providers/prefs_provider.dart'
    show sharedPreferencesProvider;

class CloudPaymentLocalView {
  const CloudPaymentLocalView({this.paidAt});

  final DateTime? paidAt;

  bool get isPaid => paidAt != null;
}

class CloudPaymentLocalNotifier extends Notifier<CloudPaymentLocalView> {
  CloudPaymentLocalRepository get _repo =>
      CloudPaymentLocalRepository(ref.read(sharedPreferencesProvider));

  @override
  CloudPaymentLocalView build() {
    ref.watch(sharedPreferencesProvider);
    return _read();
  }

  CloudPaymentLocalView _read() {
    return CloudPaymentLocalView(
      paidAt: _repo.paidAtForMonth(DateTime.now()),
    );
  }

  void markCurrentMonthPaid() {
    _repo.markCurrentMonthPaid(DateTime.now());
    state = _read();
  }
}

final cloudPaymentLocalProvider =
    NotifierProvider<CloudPaymentLocalNotifier, CloudPaymentLocalView>(
  CloudPaymentLocalNotifier.new,
);
