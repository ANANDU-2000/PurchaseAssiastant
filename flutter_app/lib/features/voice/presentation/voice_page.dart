import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';

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
  _AiPhase _phase = _AiPhase.idle;
  Timer? _maxListenTimer;
  late final AnimationController _pulse;

  static const _maxListenDuration = Duration(seconds: 18);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final timeFmt = DateFormat.jm();

    String phaseLabel;
    switch (_phase) {
      case _AiPhase.idle:
        phaseLabel = 'Tap mic or type — not always listening';
        break;
      case _AiPhase.listening:
        phaseLabel = 'Short listen session…';
        break;
      case _AiPhase.processing:
        phaseLabel = 'Processing…';
        break;
      case _AiPhase.preview:
        phaseLabel = 'Preview — confirm in Entries';
        break;
      case _AiPhase.error:
        phaseLabel = 'Try again';
        break;
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: cs.primary,
              child: const Text('H', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HEXA AI', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    phaseLabel,
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
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
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_phase == _AiPhase.processing) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Card(
              elevation: 0,
              color: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_outlined, color: cs.primary, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Controlled voice — listen only when you tap',
                            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'No always-on mic · lower API cost · less noise · you confirm before save.',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      icon: Icon(_recording ? Icons.graphic_eq_rounded : Icons.mic_rounded, size: 26),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          _recording ? 'Listening…' : 'Tap to speak (short session)',
                          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      onPressed: _recording || _phase == _AiPhase.processing ? null : () => unawaited(_sendVoicePreview()),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Add entry'),
                  onPressed: () => context.go('/entries'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.insights_outlined, size: 18),
                  label: const Text('Reports'),
                  onPressed: () => context.go('/analytics'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.home_outlined, size: 18),
                  label: const Text('Home'),
                  onPressed: () => context.go('/home'),
                ),
              ],
            ),
          ),
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
              color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                itemCount: _msgs.length,
                itemBuilder: (context, i) {
                  final m = _msgs[i];
                  final bubble = DecoratedBox(
                    decoration: BoxDecoration(
                      color: m.isUser ? cs.primary : cs.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(m.isUser ? 18 : 4),
                        bottomRight: Radius.circular(m.isUser ? 4 : 18),
                      ),
                      border: m.isUser ? null : Border.all(color: cs.outline.withValues(alpha: 0.25)),
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
                                Icon(Icons.mic_rounded, size: 18, color: cs.onPrimary),
                                const SizedBox(width: 6),
                                Text('Voice', style: tt.labelSmall?.copyWith(color: cs.onPrimary)),
                              ],
                            ),
                          if (m.isVoice && m.isUser) const SizedBox(height: 4),
                          Text(
                            m.text,
                            style: tt.bodyMedium?.copyWith(
                              color: m.isUser ? cs.onPrimary : cs.onSurface,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            timeFmt.format(m.time),
                            style: tt.labelSmall?.copyWith(
                              color: (m.isUser ? cs.onPrimary : cs.onSurface).withValues(alpha: 0.65),
                              fontSize: 11,
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
                          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
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
                          backgroundColor: cs.primary.withValues(alpha: 0.15),
                          child: Icon(Icons.smart_toy_rounded, color: cs.primary, size: 20),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
                              child: bubble,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          Material(
            elevation: 10,
            color: cs.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  children: [
                    ScaleTransition(
                      scale: Tween<double>(begin: 0.94, end: 1.0).animate(
                        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                      ),
                      child: IconButton.filledTonal(
                        tooltip: 'Push-to-talk (short session)',
                        icon: Icon(_recording ? Icons.graphic_eq_rounded : Icons.mic_rounded),
                        onPressed: _recording || _phase == _AiPhase.processing
                            ? null
                            : () => unawaited(_sendVoicePreview()),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _textCtrl,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => unawaited(_sendText()),
                        decoration: InputDecoration(
                          hintText: _phase == _AiPhase.processing
                              ? 'Working…'
                              : 'Type Malayalam or English…',
                          filled: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                    IconButton.filled(
                      onPressed: _phase == _AiPhase.processing ? null : () => unawaited(_sendText()),
                      icon: const Icon(Icons.send_rounded),
                    ),
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
