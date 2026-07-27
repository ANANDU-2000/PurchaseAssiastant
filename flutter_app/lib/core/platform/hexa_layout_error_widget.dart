import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'hexa_app_reload.dart';

/// Shown for widget build/layout failures ([ErrorWidget.builder]).
/// Compact so one bad section does not fill the whole screen.
Widget buildHexaLayoutErrorWidget(FlutterErrorDetails details) {
  final message = details.exceptionAsString().split('\n').first;
  return Material(
    color: const Color(0xFFF8FAFC),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 22,
                color: Colors.orange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'This section could not load.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap Reload or pull to refresh. If this repeats, sign out and sign in again.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        height: 1.3,
                      ),
                    ),
                    if (kDebugMode && message.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: reloadHexaApp,
              child: const Text('Reload'),
            ),
          ),
        ],
      ),
    ),
  );
}
