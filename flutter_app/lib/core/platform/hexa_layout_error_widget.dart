import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../widgets/hexa_page_error_boundary.dart'
    show hexaAsyncErrorLikelyBenign, hexaErrorLikelyNonFatal;

/// Shown for widget build/layout failures ([ErrorWidget.builder]).
/// Compact so one bad section does not fill the whole screen.
///
/// This widget NEVER triggers a browser reload. Section recovery is handled
/// naturally by pull-to-refresh, tab switching, or provider invalidation.
Widget buildHexaLayoutErrorWidget(FlutterErrorDetails details) {
  if (kDebugMode) {
    debugPrint(
      'Hexa layout error:\n${details.exceptionAsString()}\n\n${details.stack ?? '(no stack)'}',
    );
  }

  // Reuse the same classification already used by FlutterError.onError and
  // PlatformDispatcher.onError. Benign / non-fatal errors (network blips,
  // render-flex overflows, disposed-provider races, etc.) should not show
  // the "section could not load" box — fail silently so the section simply
  // re-renders on the next frame or a pull-to-refresh.
  if (hexaErrorLikelyNonFatal(details) ||
      hexaAsyncErrorLikelyBenign(details.exception)) {
    return const SizedBox.shrink();
  }

  // Non-benign: show a compact inline warning. No reload button — the
  // section will recover on its own (provider invalidation, tab switch,
  // pull-to-refresh). A browser reload would destroy the entire session.
  return Material(
    color: const Color(0xFFF8FAFC),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: Colors.orange,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This section could not load. Pull to refresh or navigate away and back.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
