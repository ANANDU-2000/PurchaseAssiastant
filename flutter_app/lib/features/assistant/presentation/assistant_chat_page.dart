import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/health_provider.dart';
import '../../../core/theme/hexa_colors.dart';

/// In-app assistant — preview → YES → save; health dot shows AI config status.
class AssistantChatPage extends ConsumerStatefulWidget {
  const AssistantChatPage({super.key});

  @override
  ConsumerState<AssistantChatPage> createState() => _AssistantChatPageState();
}

class _AssistantChatPageState extends ConsumerState<AssistantChatPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_Bubble>[];
  bool _loading = false;

  String? _pendingPreviewToken;
  Map<String, dynamic>? _pendingEntryDraft;

  stt.SpeechToText? _speech;
  bool _speechOn = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _msgs.add(
      const _Bubble(
        text:
            'Describe a purchase or say e.g. “create supplier Ravi”. '
            'You’ll get a preview first — reply YES to save, NO to cancel.\n'
            'Hold the mic to dictate (Malayalam / English on device).',
        user: false,
      ),
    );
    if (!kIsWeb) {
      _speech = stt.SpeechToText();
      _initSpeech();
    }
  }

  Future<void> _initSpeech() async {
    final s = _speech;
    if (s == null) return;
    try {
      final ok = await s.initialize(
        onStatus: (st) {
          if (st == 'done' || st == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (mounted) setState(() => _speechOn = ok);
    } catch (_) {
      if (mounted) setState(() => _speechOn = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;

    setState(() {
      _loading = true;
      _msgs.add(_Bubble(text: text, user: true));
      _ctrl.clear();
    });
    _scrollEnd();
    HapticFeedback.lightImpact();

    final api = ref.read(hexaApiProvider);
    final bid = session.primaryBusiness.id;

    try {
      final lower = text.toLowerCase().trim();
      final confirming = _pendingPreviewToken != null &&
          _pendingEntryDraft != null &&
          ['yes', 'y', 'no', 'n', 'cancel'].contains(lower);

      final data = await api.aiChat(
        businessId: bid,
        messages: [
          {'role': 'user', 'content': text},
        ],
        previewToken: confirming ? _pendingPreviewToken : null,
        entryDraft: confirming ? _pendingEntryDraft : null,
      );

      final reply = data['reply'] as String? ?? '';
      final intent = data['intent'] as String? ?? '';

      setState(() {
        _msgs.add(_Bubble(text: reply, user: false));
        if (intent == 'add_purchase_preview' || intent == 'entity_preview') {
          _pendingPreviewToken = data['preview_token'] as String?;
          final draft = data['entry_draft'];
          _pendingEntryDraft =
              draft is Map ? Map<String, dynamic>.from(draft) : null;
        } else if (intent == 'confirm_saved' ||
            intent == 'entity_saved' ||
            intent == 'cancelled' ||
            intent == 'clarify') {
          if (intent != 'clarify' ||
              (_pendingPreviewToken != null && text.toLowerCase() == 'no')) {
            _pendingPreviewToken = null;
            _pendingEntryDraft = null;
          }
        } else {
          _pendingPreviewToken = null;
          _pendingEntryDraft = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.add(_Bubble(text: friendlyApiError(e), user: false));
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
      _scrollEnd();
    }
  }

  Future<void> _startListen() async {
    if (kIsWeb || _speech == null || !_speechOn) return;
    setState(() => _listening = true);
    HapticFeedback.mediumImpact();
    await _speech!.listen(
      onResult: (r) {
        if (r.finalResult) {
          final t = r.recognizedWords.trim();
          if (t.isNotEmpty) {
            _ctrl.text = t;
            _ctrl.selection = TextSelection.collapsed(offset: t.length);
          }
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
    );
  }

  Future<void> _stopListen() async {
    if (_speech == null) return;
    await _speech!.stop();
    if (mounted) setState(() => _listening = false);
  }

  Widget _aiStatusDot() {
    final h = ref.watch(healthProvider);
    return h.when(
      loading: () => Tooltip(
        message: 'Checking AI…',
        child: Icon(Icons.circle, size: 10, color: Colors.grey.shade500),
      ),
      error: (_, __) => Tooltip(
        message: 'Server unreachable',
        child: Icon(Icons.circle, size: 10, color: Colors.red.shade700),
      ),
      data: (m) {
        final ok = m['ai_ready'] == true;
        return Tooltip(
          message: ok ? 'AI ready' : 'AI not configured (add API keys on server)',
          child: Icon(
            Icons.circle,
            size: 10,
            color: ok ? const Color(0xFF16A34A) : Colors.red.shade700,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    ref.watch(healthProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: HexaColors.primaryNavy,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            _aiStatusDot(),
            const SizedBox(width: 8),
            const Text('Assistant'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              itemCount: _msgs.length + (_loading ? 1 : 0),
              itemBuilder: (context, i) {
                if (_loading && i == _msgs.length) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final m = _msgs[i];
                return _BubbleTile(bubble: m);
              },
            ),
          ),
          Material(
            elevation: 6,
            color: Colors.white,
            shadowColor: Colors.black12,
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, 6, 8, 6 + bottom),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!kIsWeb && _speechOn)
                    Listener(
                      onPointerDown: (_) => unawaited(_startListen()),
                      onPointerUp: (_) => unawaited(_stopListen()),
                      onPointerCancel: (_) => unawaited(_stopListen()),
                      child: Tooltip(
                        message: 'Hold to speak',
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Material(
                            color: _listening
                                ? HexaColors.accentInfo.withValues(alpha: 0.2)
                                : HexaColors.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                            child: Icon(
                              Icons.mic_rounded,
                              color: _listening
                                  ? HexaColors.accentInfo
                                  : HexaColors.primaryNavy,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: HexaColors.primaryNavy,
                            fontSize: 14,
                          ),
                      decoration: InputDecoration(
                        hintText: 'Type a purchase or question…',
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: _loading ? null : _send,
                    style: FilledButton.styleFrom(
                      backgroundColor: HexaColors.accentInfo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      minimumSize: const Size(44, 44),
                    ),
                    child: const Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble {
  const _Bubble({required this.text, required this.user});
  final String text;
  final bool user;
}

class _BubbleTile extends StatelessWidget {
  const _BubbleTile({required this.bubble});

  final _Bubble bubble;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: bubble.user ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.88,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bubble.user
                  ? HexaColors.accentInfo.withValues(alpha: 0.12)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(bubble.user ? 14 : 4),
                bottomRight: Radius.circular(bubble.user ? 4 : 14),
              ),
              border: Border.all(
                color: bubble.user
                    ? HexaColors.accentInfo.withValues(alpha: 0.35)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SelectableText(
                bubble.text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.35,
                      fontSize: 14,
                      color: HexaColors.primaryNavy,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
