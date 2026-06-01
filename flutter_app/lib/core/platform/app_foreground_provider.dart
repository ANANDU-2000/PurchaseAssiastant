import 'package:flutter_riverpod/flutter_riverpod.dart';

/// False when the app tab is hidden (web) or OS backgrounded — pauses API polling.
final appForegroundProvider = StateProvider<bool>((ref) => true);

/// Last time the app returned to foreground (resume / tab visible).
final appLastForegroundAtProvider = StateProvider<DateTime?>((ref) => null);
