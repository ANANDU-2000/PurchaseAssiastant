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

/// In-app assistant — preview → YES → save; health shows LLM vs rules mode.
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

  static const _maxHistoryMessages = 22;

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

  /// Last N turns for `POST .../ai/chat` (server uses tail for LLM context).
  List<Map<String, dynamic>> _conversationForApi() {
    final slice = _msgs.length > _maxHistoryMessages
        ? _msgs.sublist(_msgs.length - _maxHistoryMessages)
        : _msgs;
    return [
      for (final b in slice)
        {
          'role': b.user ? 'user' : 'assistant',
          'content': b.text,
        },
    ];
  }

  Future<void> _sendWithText(String text) async {
    final t = text.trim();
    if (t.isEmpty || _loading) return;
    _ctrl.text = t;
    await _send();
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
        messages: _conversationForApi(),
        previewToken: confirming ? _pendingPreviewToken : null,
        entryDraft: confirming ? _pendingEntryDraft : null,
      );

      final reply = data['reply'] as String? ?? '';
      final intent = data['intent'] as String? ?? '';
      final previewUi = intent == 'add_purchase_preview' || intent == 'entity_preview';

      setState(() {
        _msgs.add(_Bubble(
          text: reply,
          user: false,
          showPreviewActions: previewUi,
        ));
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
        _msgs.add(
          _Bubble(text: friendlyApiError(e, forAssistant: true), user: false),
        );
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

  Widget _aiStatusRow() {
    final h = ref.watch(healthProvider);
    return h.when(
      loading: () => Text(
        'Checking…',
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w600,
        ),
      ),
      error: (_, __) => Text(
        'Offline',
        style: TextStyle(
          fontSize: 11,
          color: Colors.red.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
      data: (m) {
        final llm = m['intent_llm_active'] == true;
        final prov = (m['ai_provider'] ?? 'stub').toString();
        final label = llm
            ? 'Assistant ready'
            : (prov == 'stub' ? 'Basic mode' : 'Setup required');
        final color = llm
            ? const Color(0xFF16A34A)
            : (prov == 'stub' ? const Color(0xFFF59E0B) : Colors.red.shade700);
        return Row(
          children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Assistant'),
            _aiStatusRow(),
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
                return _BubbleTile(
                  bubble: m,
                  onConfirm: m.showPreviewActions
                      ? () => unawaited(_sendWithText('YES'))
                      : null,
                  onCancel: m.showPreviewActions
                      ? () => unawaited(_sendWithText('NO'))
                      : null,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _QuickChip(
                    label: 'Profit this month',
                    onTap: () => unawaited(_sendWithText('Profit this month')),
                  ),
                  _QuickChip(
                    label: 'Add purchase',
                    onTap: () => unawaited(_sendWithText(
                        'Help me add a purchase: item, qty, buy price')),
                  ),
                  _QuickChip(
                    label: 'New supplier',
                    onTap: () =>
                        unawaited(_sendWithText('Create supplier ')),
                  ),
                  _QuickChip(
                    label: 'Today',
                    onTap: () => unawaited(_sendWithText('Summary today')),
                  ),
                ],
              ),
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

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      ),
    );
  }
}

class _Bubble {
  const _Bubble({
    required this.text,
    required this.user,
    this.showPreviewActions = false,
  });
  final String text;
  final bool user;
  final bool showPreviewActions;
}

class _BubbleTile extends StatelessWidget {
  const _BubbleTile({
    required this.bubble,
    this.onConfirm,
    this.onCancel,
  });

  final _Bubble bubble;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  String _normalizeAssistantText(String text, {required bool previewStyle}) {
    var out = text.replaceAll('\r\n', '\n').trim();
    if (previewStyle) {
      // Keep field previews scannable: one field per line.
      out = out.replaceAll(' · ', '\n');
    }
    out = out.replaceAllMapped(RegExp(r'[ \t]{2,}'), (_) => ' ');
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final previewStyle = bubble.showPreviewActions && !bubble.user;
    final shownText = _normalizeAssistantText(
      bubble.text,
      previewStyle: previewStyle,
    );
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
                  : previewStyle
                      ? const Color(0xFFF0F9FF)
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
                    : previewStyle
                        ? HexaColors.accentInfo.withValues(alpha: 0.55)
                        : const Color(0xFFE2E8F0),
                width: previewStyle ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (previewStyle)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Preview (not saved)',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: HexaColors.accentInfo,
                            ),
                      ),
                    ),
                  SelectableText(
                    shownText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.35,
                          fontSize: 14,
                          color: HexaColors.primaryNavy,
                        ),
                  ),
                  if (onConfirm != null && onCancel != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onCancel,
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: onConfirm,
                            style: FilledButton.styleFrom(
                              backgroundColor: HexaColors.accentInfo,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
