import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/theme/hexa_colors.dart';

/// Renders `**bold**` segments with heavier weight (WhatsApp-style markdown lite).
List<InlineSpan> _boldMarkdownSpans(String text, TextStyle base) {
  final parts = text.split('**');
  final out = <InlineSpan>[];
  for (var i = 0; i < parts.length; i++) {
    out.add(
      TextSpan(
        text: parts[i],
        style: i.isOdd ? base.copyWith(fontWeight: FontWeight.w800) : base,
      ),
    );
  }
  return out;
}

class _ChatMsg {
  const _ChatMsg({
    required this.text,
    required this.isUser,
    this.isVoice = false,
    required this.time,
  });

  final String text;
  final bool isUser;
  final bool isVoice;
  final DateTime time;
}

/// AI tab: **push-to-talk only** — no always-on mic (battery, cost, privacy).
/// Flow: Tap mic → short session → STT (when server enabled) → intent → preview → confirm in Entries (never auto-save).
class VoicePage extends ConsumerStatefulWidget {
  const VoicePage({super.key});

  @override
  ConsumerState<VoicePage> createState() => _VoicePageState();
}

enum _AiPhase { idle, listening, processing, preview, error }

class _VoicePageState extends ConsumerState<VoicePage> with SingleTickerProviderStateMixin {
  final _msgs = <_ChatMsg>[];
  final _textCtrl = TextEditingController();
  final _scroll = ScrollController();
  bool _recording = false;
  bool _showVoiceBanner = true;
  _AiPhase _phase = _AiPhase.idle;
  Timer? _maxListenTimer;
  late final AnimationController _pulse;

  static const _maxListenDuration = Duration(seconds: 18);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _textCtrl.addListener(() => setState(() {}));
    _msgs.add(
      _ChatMsg(
        text:
            '👋 HEXA AI\n\n'
            '**How it works**\n'
            '• **Tap the mic** — we listen only during a short session (not always-on).\n'
            '• **Type** below — same intent pipeline, often lowest cost.\n'
            '• **Malayalam or English** — preview shows structured fields; **nothing saves** until you confirm in **Entries**.\n\n'
            '**Wake word “Hey Hexa”** can come later (needs OS/device integration). For now: **tap to speak**.',
        isUser: false,
        time: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _maxListenTimer?.cancel();
    _pulse.dispose();
    _textCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _stopListeningAnimation() {
    _pulse.stop();
    _pulse.reset();
  }

  void _startListeningAnimation() {
    _pulse.repeat(reverse: true);
  }

  /// One-shot voice session: starts on tap, ends when STT returns or max duration (safety).
  Future<void> _sendVoicePreview() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (_recording || _phase == _AiPhase.processing) return;

    _maxListenTimer?.cancel();
    setState(() {
      _recording = true;
      _phase = _AiPhase.listening;
      _msgs.add(_ChatMsg(text: '🎤 Listening… (tap mic only — short session)', isUser: true, isVoice: true, time: DateTime.now()));
    });
    _startListeningAnimation();
    _scrollToEnd();

    _maxListenTimer = Timer(_maxListenDuration, () {
      if (!mounted) return;
      if (_recording) {
        setState(() {
          _recording = false;
          _phase = _AiPhase.error;
          _stopListeningAnimation();
          if (_msgs.isNotEmpty && _msgs.last.isVoice) _msgs.removeLast();
          _msgs.add(
            _ChatMsg(
              text: '⏱️ Session timed out — tap the mic again. (We never keep the mic open in the background.)',
              isUser: false,
              time: DateTime.now(),
            ),
          );
        });
        _scrollToEnd();
      }
    });

    try {
      setState(() => _phase = _AiPhase.processing);
      final r = await ref.read(hexaApiProvider).mediaVoicePreview(businessId: session.primaryBusiness.id);
      if (!mounted) return;
      _maxListenTimer?.cancel();
      final note = r['note']?.toString() ?? 'Voice preview OK';
      setState(() {
        _recording = false;
        _stopListeningAnimation();
        _phase = _AiPhase.preview;
        _msgs.removeLast();
        _msgs.add(_ChatMsg(text: '🎤 Voice session ended', isUser: true, isVoice: true, time: DateTime.now()));
        _msgs.add(
          _ChatMsg(
            text:
                '✅ **Preview (draft)**\n'
                '• Transcript: (when STT is enabled on server)\n'
                '• $note\n\n'
                '**EN:** Review numbers, then **Entries → Add → Preview → Save**.\n'
                '**ML:** സംഖ്യകൾ പരിശോധിച്ച് എൻട്രികളിൽ സേവ് ചെയ്യുക — യാന്ത്രിക സേവ് ഇല്ല.\n\n'
                '❌ No auto-save. ✅ Confirm first.',
            isUser: false,
            time: DateTime.now(),
          ),
        );
      });
    } catch (e) {
      if (mounted) {
        _maxListenTimer?.cancel();
        setState(() {
          _recording = false;
          _stopListeningAnimation();
          _phase = _AiPhase.error;
          if (_msgs.isNotEmpty && _msgs.last.isVoice) _msgs.removeLast();
          _msgs.add(_ChatMsg(text: 'Voice error: $e', isUser: false, time: DateTime.now()));
        });
      }
    }
    _scrollToEnd();
  }

  /// Single intent call (lower cost than chat + intent).
  Future<void> _sendText() async {
    final t = _textCtrl.text.trim();
    if (t.isEmpty) return;
    final now = DateTime.now();
    setState(() {
      _msgs.add(_ChatMsg(text: t, isUser: true, time: now));
      _textCtrl.clear();
      _phase = _AiPhase.processing;
    });
    _scrollToEnd();
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final intent = await ref.read(hexaApiProvider).aiIntent(businessId: session.primaryBusiness.id, text: t);
      if (!mounted) return;
      final reply = intent['reply_text']?.toString() ?? '—';
      final data = intent['data'];
      final missing = (intent['missing_fields'] as List<dynamic>?) ?? [];
      final used = intent['tokens_used_month'];
      var block = '🧠 **Intent preview** (draft)\n\n$reply\n';
      if (data is Map) {
        block +=
            '\n```json\n${const JsonEncoder.withIndent('  ').convert(Map<String, dynamic>.from(Map<dynamic, dynamic>.from(data)))}\n```';
      }
      if (missing.isNotEmpty) {
        block += '\n\n⚠️ Missing: ${missing.join(', ')} — add in text or Entries.';
      }
      if (used != null) block += '\n\n📊 AI usage (month): $used';
      block += '\n\n**Did we get ₹ / qty wrong?** Edit and send again, or fix in Entries.';
      setState(() {
        _phase = _AiPhase.preview;
        _msgs.add(_ChatMsg(text: block, isUser: false, time: DateTime.now()));
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _AiPhase.error;
          _msgs.add(_ChatMsg(text: 'Request failed: $e', isUser: false, time: DateTime.now()));
        });
      }
    }
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _clearPreview() {
    setState(() => _phase = _AiPhase.idle);
  }

  Widget _botMessageBody(_ChatMsg m, int index, TextTheme tt, ColorScheme cs) {
    final baseBot = (tt.bodyMedium ?? const TextStyle(fontSize: 15)).copyWith(color: HexaColors.textPrimary, height: 1.35);
    if (index == 0 && !m.isUser) {
      final paras = m.text.split('\n\n').where((s) => s.trim().isNotEmpty).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var j = 0; j < paras.length; j++) ...[
            if (j > 0) const SizedBox(height: 10),
            Text.rich(TextSpan(children: _boldMarkdownSpans(paras[j], baseBot))),
          ],
        ],
      );
    }
    return Text.rich(TextSpan(children: _boldMarkdownSpans(m.text, baseBot)));
  }

  Widget _micControl() {
    final busy = _phase == _AiPhase.processing;
    if (busy && !_recording) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: HexaColors.primaryMid),
          ),
        ),
      );
    }
    if (_phase == _AiPhase.error && !_recording && !busy) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _recording || busy ? null : () => unawaited(_sendVoicePreview()),
            child: Icon(Icons.mic_rounded, color: HexaColors.loss, size: 28),
          ),
        ),
      );
    }
    final pulseChild = Material(
      color: HexaColors.primaryMid,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _recording || busy ? null : () => unawaited(_sendVoicePreview()),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            _recording ? Icons.stop_rounded : Icons.mic_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
    if (_recording) {
      return ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
        ),
        child: pulseChild,
      );
    }
    return pulseChild;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final timeFmt = DateFormat.jm();
    final hasText = _textCtrl.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: HexaColors.primaryMid,
              radius: 20,
              child: const Text('H', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HEXA Assistant', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    'Ask in Malayalam or English',
                    style: tt.labelSmall?.copyWith(color: HexaColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_phase == _AiPhase.preview)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _clearPreview,
                      child: const Text('Dismiss'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: HexaColors.primaryMid, foregroundColor: Colors.white),
                      onPressed: () {
                        context.go('/entries');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Entries → + → Preview → Save. No auto-save from AI.')),
                        );
                      },
                      child: const Text('Open Entries'),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Container(
              color: HexaColors.canvas.withValues(alpha: 0.5),
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                children: [
                  if (_showVoiceBanner)
                    Dismissible(
                      key: const ValueKey('voiceBanner'),
                      direction: DismissDirection.horizontal,
                      onDismissed: (_) => setState(() => _showVoiceBanner = false),
                      child: Material(
                        color: HexaColors.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, color: HexaColors.primaryMid, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '🎙 Tap mic only — short session, then confirm in Entries',
                                  style: tt.bodySmall?.copyWith(color: HexaColors.textPrimary, fontWeight: FontWeight.w600, height: 1.35),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_showVoiceBanner) const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ActionChip(
                          avatar: Icon(Icons.add_rounded, size: 18, color: HexaColors.primaryMid),
                          label: const Text('＋ Add Entry'),
                          onPressed: () => context.go('/entries'),
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: Icon(Icons.insights_outlined, size: 18, color: HexaColors.primaryMid),
                          label: const Text('Reports'),
                          onPressed: () => context.go('/analytics'),
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: Icon(Icons.home_outlined, size: 18, color: HexaColors.primaryMid),
                          label: const Text('Home'),
                          onPressed: () => context.go('/home'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(_msgs.length, (i) {
                    final m = _msgs[i];
                    final bubble = DecoratedBox(
                      decoration: BoxDecoration(
                        color: m.isUser ? HexaColors.primaryMid : cs.surface,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(m.isUser ? 18 : 4),
                          bottomRight: Radius.circular(m.isUser ? 4 : 18),
                        ),
                        border: m.isUser ? null : Border.all(color: HexaColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (m.isVoice && m.isUser)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.mic_rounded, size: 18, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text('Voice', style: tt.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
                                ],
                              ),
                            if (m.isVoice && m.isUser) const SizedBox(height: 4),
                            m.isUser
                                ? Text(
                                    m.text,
                                    style: tt.bodyMedium?.copyWith(color: Colors.white, height: 1.35),
                                  )
                                : _botMessageBody(m, i, tt, cs),
                            const SizedBox(height: 4),
                            Align(
                              alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                              child: Text(
                                timeFmt.format(m.time),
                                style: tt.labelSmall?.copyWith(
                                  color: m.isUser ? Colors.white.withValues(alpha: 0.65) : HexaColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );

                    if (m.isUser) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.80),
                            child: bubble,
                          ),
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: HexaColors.primaryMid,
                            child: const Text('H', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
                                child: bubble,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          Material(
            elevation: 8,
            shadowColor: Colors.black26,
            color: cs.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _micControl(),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _textCtrl,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => unawaited(_sendText()),
                        decoration: InputDecoration(
                          hintText: _phase == _AiPhase.processing && !_recording ? 'Working…' : 'Type in Malayalam or English…',
                          filled: true,
                          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(color: HexaColors.primaryMid, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                      ),
                    ),
                    if (hasText) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: Material(
                          color: HexaColors.primaryMid,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _phase == _AiPhase.processing ? null : () => unawaited(_sendText()),
                            child: const Icon(Icons.send_rounded, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
