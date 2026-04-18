import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/health_provider.dart';
import 'assistant_chat_theme.dart';
import 'models/chat_message.dart';
import 'providers/assistant_quick_prompts_provider.dart';
import 'widgets/chat_background_pattern.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/input_bar.dart';
import 'widgets/preview_card.dart';
import 'widgets/quick_prompts_bar.dart';
import 'widgets/typing_indicator.dart';

/// In-app assistant — preview → YES → save; health shows LLM vs rules mode.
class AssistantChatPage extends ConsumerStatefulWidget {
  const AssistantChatPage({super.key});

  @override
  ConsumerState<AssistantChatPage> createState() => _AssistantChatPageState();
}

class _AssistantChatPageState extends ConsumerState<AssistantChatPage> {
  final _ctrl = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final _msgs = <ChatMessage>[];
  bool _loading = false;

  String? _pendingPreviewToken;
  Map<String, dynamic>? _pendingEntryDraft;

  stt.SpeechToText? _speech;
  bool _speechOn = false;
  bool _listening = false;

  String? _replySnippet;
  final Set<String> _typewriterActive = {};

  static const _maxHistoryMessages = 22;

  @override
  void initState() {
    super.initState();
    _msgs.add(
      ChatMessage(
        id: 'welcome',
        text: 'Ask in plain words, e.g. create supplier Ravi, or add a purchase. '
            'You will see a preview first. Reply YES to save or NO to cancel.\n'
            'Hold the mic in the bar below to dictate (Malayalam or English).',
        isUser: false,
        at: DateTime.now(),
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
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: AssistantChatTheme.shortAnim,
        curve: AssistantChatTheme.motion,
      );
    });
  }

  List<Map<String, dynamic>> _conversationForApi() {
    final slice = _msgs.length > _maxHistoryMessages
        ? _msgs.sublist(_msgs.length - _maxHistoryMessages)
        : _msgs;
    return [
      for (final b in slice)
        {
          'role': b.isUser ? 'user' : 'assistant',
          'content': b.text,
        },
    ];
  }

  void _onQuickPrompt(AssistantQuickPrompt p) {
    final loc = p.goLocation?.trim();
    if (loc != null && loc.isNotEmpty) {
      if (p.usePush) {
        context.push(loc);
      } else {
        context.go(loc);
      }
    }
    final msg = p.message?.trim();
    if (msg != null && msg.isNotEmpty) {
      unawaited(_sendWithText(msg));
    }
  }

  Future<void> _sendWithText(String text) async {
    final t = text.trim();
    if (t.isEmpty || _loading) return;
    _ctrl.text = t;
    await _send();
  }

  Future<void> _send() async {
    final display = _ctrl.text.trim();
    if (display.isEmpty || _loading) return;
    var text = display;
    if (_replySnippet != null && _replySnippet!.isNotEmpty) {
      text = '> ${_replySnippet!.replaceAll('\n', ' ')}\n\n$display';
    }
    final session = ref.read(sessionProvider);
    if (session == null) return;

    setState(() {
      _loading = true;
      _msgs.add(ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: text,
        isUser: true,
        at: DateTime.now(),
      ));
      _replySnippet = null;
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
      Map<String, dynamic>? snap;
      if (previewUi && data['entry_draft'] is Map) {
        snap = Map<String, dynamic>.from(data['entry_draft'] as Map);
      }

      final aid = '${DateTime.now().microsecondsSinceEpoch}a';
      setState(() {
        _typewriterActive.add(aid);
        _msgs.add(
          ChatMessage(
            id: aid,
            text: reply,
            isUser: false,
            at: DateTime.now(),
            showPreviewActions: previewUi,
            draftSnapshot: snap,
          ),
        );
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
      final eid = '${DateTime.now().microsecondsSinceEpoch}e';
      setState(() {
        _typewriterActive.add(eid);
        _msgs.add(
          ChatMessage(
            id: eid,
            text: friendlyApiError(e, forAssistant: true),
            isUser: false,
            at: DateTime.now(),
          ),
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

  void _onBubbleLongPress(String t, bool isUser) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text('Copy', style: AssistantChatTheme.inter(16, w: FontWeight.w600)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: t));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              },
            ),
            if (isUser)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
                title: Text('Delete', style: AssistantChatTheme.inter(16, w: FontWeight.w600, c: Colors.red.shade800)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _msgs.removeWhere((m) => m.isUser && m.text == t);
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _subtitleRow() {
    final h = ref.watch(healthProvider);
    return h.when(
      loading: () => Text('…', style: AssistantChatTheme.inter(11.5, c: Colors.white70)),
      error: (_, __) => Text('Offline', style: AssistantChatTheme.inter(11.5, c: Colors.white70)),
      data: (m) {
        final llm = m['intent_llm_active'] == true;
        final prov = (m['ai_provider'] ?? 'stub').toString();
        final tail = llm ? ' · Smart replies on' : (prov == 'stub' ? ' · Quick answers' : ' · Check setup');
        return Text(
          'Connected$tail',
          style: AssistantChatTheme.inter(11.5, w: FontWeight.w500, c: Colors.white.withValues(alpha: 0.9)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(healthProvider);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBodyBehindAppBar: false,
      body: ChatBackgroundPattern(
        child: Column(
          children: [
            _GradientAppBar(
              title: 'Assistant',
              subtitle: _subtitleRow(),
              onMenu: () => _showAssistantMenu(context),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: _msgs.length + (_loading ? 1 : 0),
                itemBuilder: (context, i) {
                  if (_loading && i == _msgs.length) {
                    return const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TypingIndicator(),
                      ),
                    );
                  }
                  final m = _msgs[i];
                  final prev = i > 0 ? _msgs[i - 1] : null;
                  final next = i < _msgs.length - 1 ? _msgs[i + 1] : null;
                  final tightGroupTop = prev != null && prev.isUser == m.isUser;
                  final showMeta = next == null || next.isUser != m.isUser;
                  final parsed = m.draftSnapshot != null
                      ? PreviewCard.parse(m.draftSnapshot!)
                      : null;
                  final showCard =
                      m.showPreviewActions && m.draftSnapshot != null && parsed != null;
                  return Column(
                    crossAxisAlignment:
                        m.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      if (i == 0) const _DayDivider(label: 'TODAY'),
                      ChatBubble(
                        text: m.text,
                        isUser: m.isUser,
                        time: m.at,
                        showMeta: showMeta,
                        tightGroupTop: tightGroupTop,
                        typewriter: !m.isUser && _typewriterActive.contains(m.id),
                        onLongPress: _onBubbleLongPress,
                        onSwipeReply: () {
                          setState(() {
                            _replySnippet = m.text.split('\n').first;
                          });
                          HapticFeedback.lightImpact();
                        },
                        replySnippet: null,
                        onTypewriterComplete: () {
                          if (_typewriterActive.remove(m.id)) {
                            setState(() {});
                          }
                        },
                      ),
                      if (showCard)
                        PreviewCard(
                          entryDraft: m.draftSnapshot!,
                          onCancel: () => unawaited(_sendWithText('NO')),
                          onSave: () => unawaited(_sendWithText('YES')),
                        )
                      else if (m.showPreviewActions)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, right: 48, bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => unawaited(_sendWithText('NO')),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFDC2626),
                                    side: const BorderSide(color: Color(0xFFDC2626)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text('Cancel',
                                      style: AssistantChatTheme.inter(14, w: FontWeight.w600)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => unawaited(_sendWithText('YES')),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AssistantChatTheme.accent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text('Save',
                                      style: AssistantChatTheme.inter(14, w: FontWeight.w700)),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QuickPromptsBar(onPrompt: _onQuickPrompt),
                  InputBar(
                    controller: _ctrl,
                    focusNode: _inputFocus,
                    onSend: _send,
                    loading: _loading,
                    speechReady: _speechOn,
                    listening: _listening,
                    onMicDown: _startListen,
                    onMicUp: _stopListen,
                    replySnippet: _replySnippet,
                    onDismissReply: () => setState(() => _replySnippet = null),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAssistantMenu(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.vertical_align_bottom_rounded),
              title: const Text('Jump to latest'),
              onTap: () {
                Navigator.pop(ctx);
                _scrollEnd();
                _inputFocus.requestFocus();
              },
            ),
            ListTile(
              leading: const Icon(Icons.mic_rounded),
              title: const Text('Voice mode'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/voice');
              },
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Home'),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/home');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientAppBar extends StatelessWidget {
  const _GradientAppBar({
    required this.title,
    required this.subtitle,
    required this.onMenu,
  });

  final String title;
  final Widget subtitle;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(4, top + 4, 8, 10),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AssistantChatTheme.primary, AssistantChatTheme.primaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x22075E54),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Material(
              color: Colors.transparent,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                    return;
                  }
                  context.go('/home');
                },
              ),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'H',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AssistantChatTheme.onlineDot,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AssistantChatTheme.jakarta(16, w: FontWeight.w700, c: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  subtitle,
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
                tooltip: 'Menu',
                onPressed: onMenu,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            label,
            style: AssistantChatTheme.inter(
              11,
              w: FontWeight.w700,
              c: const Color(0xFF667781),
            ),
          ),
        ),
      ),
    );
  }
}

