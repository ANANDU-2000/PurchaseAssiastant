import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/health_provider.dart';
import 'assistant_chat_theme.dart';
import 'models/chat_message.dart';
import 'widgets/chat_background_pattern.dart';
import 'widgets/audio_message_bubble.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/input_bar.dart';
import 'widgets/preview_card.dart';
import 'widgets/quick_prompts_bar.dart';
import 'widgets/recording_overlay.dart';
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
  final _recorder = AudioRecorder();
  final _rng = Random();

  bool _loading = false;
  bool _recording = false;
  bool _recordReady = false;
  bool _recordCanceled = false;
  Duration _recordElapsed = Duration.zero;
  Timer? _recordTicker;

  String? _pendingPreviewToken;
  Map<String, dynamic>? _pendingEntryDraft;

  String? _replySnippet;
  final Set<String> _typewriterActive = {};

  static const _maxHistoryMessages = 22;

  @override
  void initState() {
    super.initState();
    _msgs.add(
      ChatMessage(
        id: 'welcome',
        text: 'Describe a purchase or say e.g. “create supplier Ravi”. '
            'You’ll get a preview first — reply YES to save, NO to cancel.\n'
            'Hold the mic to record a voice note.',
        isUser: false,
        at: DateTime.now(),
      ),
    );
    unawaited(_initRecorder());
  }

  Future<void> _initRecorder() async {
    try {
      final ok = await _recorder.hasPermission();
      if (mounted) setState(() => _recordReady = ok);
    } catch (_) {
      if (mounted) setState(() => _recordReady = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    _recordTicker?.cancel();
    _recorder.dispose();
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
        if (b.type == MessageType.text)
          {
            'role': b.isUser ? 'user' : 'assistant',
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

  Future<void> _startRecording() async {
    if (_recording || _loading) return;
    final permitted = await _recorder.hasPermission();
    if (!permitted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required.')),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    _recordCanceled = false;
    _recordElapsed = Duration.zero;
    _recordTicker?.cancel();
    _recordTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_recording) return;
      setState(() => _recordElapsed += const Duration(seconds: 1));
    });
    final path = await _recordingPath();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: path,
    );
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _recordTicker?.cancel();
    final p = await _recorder.stop();
    final elapsed = _recordElapsed < const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : _recordElapsed;
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordElapsed = Duration.zero;
    });
    if (_recordCanceled || p == null || p.isEmpty) return;
    setState(() {
      _msgs.add(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          isUser: true,
          at: DateTime.now(),
          type: MessageType.audio,
          audioPath: p,
          audioDuration: elapsed,
          waveform: _staticWaveform(),
        ),
      );
    });
    _scrollEnd();
  }

  Future<void> _cancelRecording() async {
    _recordCanceled = true;
    await _stopRecording();
  }

  List<double> _staticWaveform() {
    return List.generate(24, (_) => 0.2 + (_rng.nextDouble() * 0.75));
  }

  Future<String> _recordingPath() async {
    final name = 'voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    if (kIsWeb) return name;
    final dir = await getTemporaryDirectory();
    return '${dir.path}/$name';
  }

  void _onMessageLongPress(ChatMessage m) {
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
            if (m.type == MessageType.text)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text('Copy', style: AssistantChatTheme.inter(16, w: FontWeight.w600)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: m.text));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied')),
                  );
                },
              ),
            if (m.isUser)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
                title: Text('Delete', style: AssistantChatTheme.inter(16, w: FontWeight.w600, c: Colors.red.shade800)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _msgs.removeWhere((x) => x.id == m.id);
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
      loading: () => Text('checking…', style: AssistantChatTheme.inter(12, c: Colors.white70)),
      error: (_, __) => Text('offline', style: AssistantChatTheme.inter(12, c: Colors.white70)),
      data: (m) {
        final llm = m['intent_llm_active'] == true;
        final prov = (m['ai_provider'] ?? 'stub').toString();
        final tail = llm ? ' · AI ready' : (prov == 'stub' ? ' · basic mode' : ' · setup');
        return Text(
          'online$tail',
          style: AssistantChatTheme.inter(12.5, w: FontWeight.w500, c: Colors.white.withValues(alpha: 0.92)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(healthProvider);
    return Scaffold(
      extendBodyBehindAppBar: false,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 88),
        child: FloatingActionButton.small(
          heroTag: 'assistant_jump',
          backgroundColor: AssistantChatTheme.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          onPressed: () {
            _scrollEnd();
            _inputFocus.requestFocus();
            HapticFeedback.lightImpact();
          },
          child: const Icon(Icons.bolt_rounded),
        ),
      ),
      body: ChatBackgroundPattern(
        child: Stack(
          children: [
            Column(
              children: [
                _GradientAppBar(
                  title: 'Purchase Assistant',
                  subtitle: _subtitleRow(),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
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
                          if (m.type == MessageType.audio)
                            AudioMessageBubble(
                              audioPath: m.audioPath!,
                              isUser: m.isUser,
                              time: m.at,
                              duration: m.audioDuration,
                              waveform: m.waveform,
                              showMeta: showMeta,
                              tightGroupTop: tightGroupTop,
                            )
                          else
                            ChatBubble(
                              text: m.text,
                              isUser: m.isUser,
                              time: m.at,
                              showMeta: showMeta,
                              tightGroupTop: tightGroupTop,
                              typewriter: !m.isUser && _typewriterActive.contains(m.id),
                              onLongPress: (_, __) => _onMessageLongPress(m),
                              onSwipeReply: () {
                                if (m.type != MessageType.text) return;
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
                QuickPromptsBar(onPrompt: (msg) => unawaited(_sendWithText(msg))),
                InputBar(
                  controller: _ctrl,
                  focusNode: _inputFocus,
                  onSend: _send,
                  loading: _loading,
                  speechReady: _recordReady,
                  listening: _recording,
                  onMicDown: _startRecording,
                  onMicUp: _stopRecording,
                  onMicCancel: _cancelRecording,
                  replySnippet: _replySnippet,
                  onDismissReply: () => setState(() => _replySnippet = null),
                ),
              ],
            ),
            if (_recording)
              RecordingOverlay(
                elapsed: _recordElapsed,
                onCancelTap: () => unawaited(_cancelRecording()),
              ),
          ],
        ),
      ),
    );
  }
}

class _GradientAppBar extends StatelessWidget {
  const _GradientAppBar({required this.title, required this.subtitle});

  final String title;
  final Widget subtitle;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, top + 8, 12, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AssistantChatTheme.primary, AssistantChatTheme.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x33075E54),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            color: Colors.transparent,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
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
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AssistantChatTheme.accent.withValues(alpha: 0.55),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'H',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AssistantChatTheme.onlineDot,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AssistantChatTheme.accent.withValues(alpha: 0.8),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AssistantChatTheme.jakarta(18, w: FontWeight.w700, c: Colors.white)),
                const SizedBox(height: 2),
                subtitle,
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: IconButton(
              icon: const Icon(Icons.mic_rounded, color: Colors.white, size: 20),
              tooltip: 'Voice chat',
              onPressed: () => context.push('/voice'),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: IconButton(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 20),
              tooltip: 'Voice chat',
              onPressed: () => context.push('/voice'),
            ),
          ),
        ],
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

