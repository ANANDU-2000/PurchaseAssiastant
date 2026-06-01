import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/app_foreground_provider.dart';
import 'auth_failure_policy.dart';
import 'session_notifier.dart' show activeSessionProvider;

/// Skip network fetches when logged out or after terminal 401 (stops request storms).
/// Accepts provider [Ref] and widget [WidgetRef] (different types in Riverpod 2.6).
bool providerSkipApi(dynamic ref) {
  if (ref.read(authBlockApiRequestsProvider)) return true;
  if (!ref.read(appForegroundProvider)) return true;
  if (ref.read(activeSessionProvider) == null) return true;
  return false;
}
