import 'dart:ui' show FrameTiming;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'agent_debug_log.dart';

/// Logs frames slower than ~2× 60fps budget when agent debug ingest is on.
class HexaPerfFrameMonitor extends StatefulWidget {
  const HexaPerfFrameMonitor({super.key, required this.child});

  final Widget child;

  @override
  State<HexaPerfFrameMonitor> createState() => _HexaPerfFrameMonitorState();
}

class _HexaPerfFrameMonitorState extends State<HexaPerfFrameMonitor> {
  int _jankFrames = 0;

  @override
  void initState() {
    super.initState();
    if (!agentDebugLogEnabled) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final ms = t.totalSpan.inMicroseconds / 1000.0;
      if (ms < 32) continue;
      _jankFrames++;
      if (_jankFrames <= 40) {
        // #region agent log
        agentDebugLog(
          hypothesisId: 'H5',
          location: 'hexa_perf_frame_monitor.dart',
          message: 'jank_frame',
          data: {
            'totalMs': ms.round(),
            'buildMs': (t.buildDuration.inMicroseconds / 1000).round(),
            'rasterMs': (t.rasterDuration.inMicroseconds / 1000).round(),
            'frame': _jankFrames,
          },
        );
        // #endregion
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
