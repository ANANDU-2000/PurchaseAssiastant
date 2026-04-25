import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../providers/prefs_provider.dart';
import 'local_notifications_service.dart';

/// One-shot OS notification permission after sign-in (iOS; Android already requests in [LocalNotificationsService.init]).
class PostLoginNotificationPrompt extends ConsumerStatefulWidget {
  const PostLoginNotificationPrompt({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PostLoginNotificationPrompt> createState() =>
      _PostLoginNotificationPromptState();
}

class _PostLoginNotificationPromptState
    extends ConsumerState<PostLoginNotificationPrompt> {
  bool _queued = false;

  Future<void> _maybeRequest() async {
    if (kIsWeb) return;
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(kPostLoginNotifPermissionAskedKey) == true) return;
    if (ref.read(sessionProvider) == null) return;
    await LocalNotificationsService.instance.requestIosNotificationPermission();
    await prefs.setBool(kPostLoginNotifPermissionAskedKey, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    if (s != null && !_queued) {
      _queued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_maybeRequest());
      });
    }
    if (s == null) {
      _queued = false;
    }
    return widget.child;
  }
}
