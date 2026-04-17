import 'package:flutter/material.dart';

import '../assistant_chat_theme.dart';
import 'waveform_widget.dart';

/// Floating recording HUD above the composer.
class RecordingOverlay extends StatelessWidget {
  const RecordingOverlay({
    super.key,
    required this.elapsed,
    this.onCancelTap,
    this.showSlideHint = true,
  });

  final Duration elapsed;
  final VoidCallback? onCancelTap;
  final bool showSlideHint;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 108),
        child: AnimatedContainer(
          duration: AssistantChatTheme.shortAnim,
          curve: AssistantChatTheme.motion,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F2F5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fiber_manual_record_rounded, color: Color(0xFFE53935), size: 14),
              const SizedBox(width: 6),
              Text(
                _fmt(elapsed),
                style: AssistantChatTheme.inter(13, w: FontWeight.w700, c: const Color(0xFFE53935)),
              ),
              const SizedBox(width: 10),
              const WaveformWidget(),
              if (showSlideHint) ...[
                const SizedBox(width: 10),
                Text(
                  'Slide left to cancel',
                  style: AssistantChatTheme.inter(12, w: FontWeight.w600, c: const Color(0xFF667781)),
                ),
              ],
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onCancelTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'Cancel',
                    style: AssistantChatTheme.inter(12.5, w: FontWeight.w700, c: const Color(0xFFDC2626)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
