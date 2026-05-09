import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:quick_actions/quick_actions.dart';

/// Types for home-screen / launcher shortcuts (must match [ShortcutItem.type]).
const String qaLauncherScan = 'qa_scan';
const String qaLauncherNewPurchase = 'qa_new_purchase';
const String qaLauncherResumeDraft = 'qa_resume_draft';
const String qaLauncherVoice = 'qa_voice';
const String qaLauncherHistory = 'qa_history';

GoRouter? _launcherShortcutsRouter;

/// Keeps shortcut taps routed through the active app [GoRouter] (no [BuildContext]).
void bindLauncherShortcutsRouter(GoRouter router) {
  _launcherShortcutsRouter = router;
}

bool _quickActionsInitialized = false;

void _dispatchLauncherShortcut(String type) {
  final r = _launcherShortcutsRouter;
  if (r == null) return;
  switch (type) {
    case qaLauncherScan:
      r.pushNamed('purchase_scan');
      break;
    case qaLauncherNewPurchase:
      r.go('/purchase/new');
      break;
    case qaLauncherResumeDraft:
      r.go('/purchase/new?resumeDraft=true');
      break;
    case qaLauncherVoice:
      r.push('/voice');
      break;
    case qaLauncherHistory:
      r.go('/purchase');
      break;
    default:
      break;
  }
}

/// Registers iOS/Android launcher shortcuts. Safe to call on each shell mount;
/// [QuickActions.initialize] runs only once per process.
Future<void> setupLauncherQuickActions() async {
  if (kIsWeb) return;
  const qa = QuickActions();
  if (!_quickActionsInitialized) {
    await qa.initialize(_dispatchLauncherShortcut);
    _quickActionsInitialized = true;
  }
  await qa.setShortcutItems(const [
    ShortcutItem(
      type: qaLauncherScan,
      localizedTitle: 'Scan bill',
      localizedSubtitle: 'Camera or gallery',
    ),
    ShortcutItem(
      type: qaLauncherNewPurchase,
      localizedTitle: 'New purchase',
    ),
    ShortcutItem(
      type: qaLauncherResumeDraft,
      localizedTitle: 'Resume draft',
      localizedSubtitle: 'Continue saved entry',
    ),
    ShortcutItem(
      type: qaLauncherVoice,
      localizedTitle: 'Voice note',
    ),
    ShortcutItem(
      type: qaLauncherHistory,
      localizedTitle: 'Purchase history',
    ),
  ]);
}
