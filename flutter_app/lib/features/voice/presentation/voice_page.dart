import 'dart:async';

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

/// WhatsApp-style AI assistant: voice preview + typed lines (full STT on server when enabled).
class VoicePage extends ConsumerStatefulWidget {
  const VoicePage({super.key});

  @override
  ConsumerState<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends ConsumerState<VoicePage> {
  final _msgs = <_ChatMsg>[];
  final _textCtrl = TextEditingController();
  final _scroll = ScrollController();
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _msgs.add(
      _ChatMsg(
        text:
            '👋 Hi! I\'m your HEXA purchase assistant.\nYou can talk to me in Malayalam or English.\n\n'
            'Try saying:\n'
            '• "Rice 50kg ₹42 Ravi"\n'
            '• "Overview this month"\n'
            '• "Is ₹1200 good for oil?"\n'
            '• "Best supplier for rice"\n\n'
            'After the AI agent is wired, confirmations (Save / Edit / Cancel) will show on parsed entries.',
        isUser: false,
        time: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _sendVoicePreview() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() {
      _recording = true;
      _msgs.add(_ChatMsg(text: '🎤 Listening…', isUser: true, isVoice: true, time: DateTime.now()));
    });
    _scrollToEnd();
    try {
      final r = await ref.read(hexaApiProvider).mediaVoicePreview(businessId: session.primaryBusiness.id);
      if (!mounted) return;
      final note = r['note']?.toString() ?? 'Voice preview OK';
      setState(() {
        _recording = false;
        _msgs.removeLast();
        _msgs.add(_ChatMsg(text: '🎤 Voice note sent', isUser: true, isVoice: true, time: DateTime.now()));
        _msgs.add(
          _ChatMsg(
            text:
                '✅ Got it!\n$note\n\n'
                '⚠️ Full STT → parse → save runs when the server pipeline is enabled.\n'
                '💡 Tip: type a line in the box for instant testing.',
            isUser: false,
            time: DateTime.now(),
          ),
        );
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _recording = false;
          if (_msgs.isNotEmpty && _msgs.last.isVoice) _msgs.removeLast();
          _msgs.add(_ChatMsg(text: 'Could not reach voice preview: $e', isUser: false, time: DateTime.now()));
        });
      }
    }
    _scrollToEnd();
  }

  Future<void> _sendText() async {
    final t = _textCtrl.text.trim();
    if (t.isEmpty) return;
    final now = DateTime.now();
    setState(() {
      _msgs.add(_ChatMsg(text: t, isUser: true, time: now));
      _textCtrl.clear();
    });
    _scrollToEnd();
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final r = await ref.read(hexaApiProvider).aiChat(
            businessId: session.primaryBusiness.id,
            messages: [
              {'role': 'user', 'content': t},
            ],
          );
      if (!mounted) return;
      final reply = r['reply']?.toString() ?? '—';
      setState(() {
        _msgs.add(_ChatMsg(text: reply, isUser: false, time: DateTime.now()));
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _msgs.add(_ChatMsg(text: 'Could not reach HEXA AI: $e', isUser: false, time: DateTime.now()));
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final timeFmt = DateFormat.jm();

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
                  Text('HEXA Assistant', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    'Online · Replies instantly',
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
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_recording)
            const LinearProgressIndicator(minHeight: 2),
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
                    IconButton.filledTonal(
                      tooltip: 'Voice note (preview)',
                      icon: Icon(_recording ? Icons.graphic_eq_rounded : Icons.mic_rounded),
                      onPressed: _recording ? null : () => unawaited(_sendVoicePreview()),
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
                          hintText: 'Ask anything…',
                          filled: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                    IconButton.filled(
                      onPressed: () => unawaited(_sendText()),
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
