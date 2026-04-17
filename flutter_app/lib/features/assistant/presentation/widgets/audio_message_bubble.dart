import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../assistant_chat_theme.dart';

class AudioMessageBubble extends StatefulWidget {
  const AudioMessageBubble({
    super.key,
    required this.audioPath,
    required this.isUser,
    required this.time,
    required this.duration,
    this.waveform = const [],
    this.showMeta = true,
    this.tightGroupTop = false,
  });

  final String audioPath;
  final bool isUser;
  final DateTime time;
  final Duration duration;
  final List<double> waveform;
  final bool showMeta;
  final bool tightGroupTop;

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  late final AudioPlayer _player;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;
  Duration _position = Duration.zero;
  bool _playing = false;
  Duration? _effectiveDuration;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _posSub = _player.positionStream.listen((d) {
      if (mounted) setState(() => _position = d);
    });
    _stateSub = _player.playerStateStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _playing = s.playing;
        if (s.processingState == ProcessingState.completed) {
          _position = Duration.zero;
          _playing = false;
          _player.seek(Duration.zero);
        }
      });
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final p = widget.audioPath;
    if (p.startsWith('http://') || p.startsWith('https://') || p.startsWith('blob:')) {
      _effectiveDuration = await _player.setUrl(p);
    } else {
      _effectiveDuration = await _player.setFilePath(File(p).path);
    }
    _loaded = true;
  }

  Future<void> _toggle() async {
    await _ensureLoaded();
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _timeLabel() {
    final t = TimeOfDay.fromDateTime(widget.time);
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'am' : 'pm';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    final d = (_effectiveDuration ?? widget.duration);
    final totalMs = d.inMilliseconds <= 0 ? 1 : d.inMilliseconds;
    final progress = (_position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final bars = widget.waveform.isEmpty
        ? const [0.4, 0.6, 0.3, 0.8, 0.55, 0.35, 0.72, 0.48, 0.62, 0.34, 0.7]
        : widget.waveform;

    return Align(
      alignment: widget.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(top: widget.tightGroupTop ? 2 : 4, bottom: 6),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: widget.isUser ? AssistantChatTheme.bubbleUser : AssistantChatTheme.bubbleAi,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(widget.isUser ? 18 : 5),
              bottomRight: Radius.circular(widget.isUser ? 5 : 18),
            ),
            border: Border.all(
              color: widget.isUser ? const Color(0x22075E54) : AssistantChatTheme.bubbleAiBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: _toggle,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.isUser
                            ? AssistantChatTheme.primary.withValues(alpha: 0.14)
                            : const Color(0xFFF0F2F5),
                      ),
                      child: Icon(
                        _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: AssistantChatTheme.primary,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: bars
                              .map(
                                (h) => Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 0.6),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      curve: AssistantChatTheme.motion,
                                      height: 5 + (12 * h),
                                      decoration: BoxDecoration(
                                        color: AssistantChatTheme.primary.withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            minHeight: 3.2,
                            value: progress,
                            backgroundColor: const Color(0xFFB0BEC5).withValues(alpha: 0.35),
                            valueColor: const AlwaysStoppedAnimation<Color>(AssistantChatTheme.accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _fmt(_playing ? _position : d),
                    style: AssistantChatTheme.inter(11.5, w: FontWeight.w700, c: const Color(0xFF667781)),
                  ),
                ],
              ),
              if (widget.showMeta) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _timeLabel(),
                        style: AssistantChatTheme.inter(11, w: FontWeight.w500, c: const Color(0xFF8696A0)),
                      ),
                      if (widget.isUser) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.done_all_rounded,
                          size: 16,
                          color: AssistantChatTheme.accent.withValues(alpha: 0.95),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
