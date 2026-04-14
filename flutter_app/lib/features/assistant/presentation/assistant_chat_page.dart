import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/theme/hexa_colors.dart';

/// In-app purchase assistant — same backend flow as preview → YES → save.
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

  @override
  void initState() {
    super.initState();
    _msgs.add(
      const _Bubble(
        text:
            'Ask for reports (e.g. profit this month) or describe a purchase.\n'
            'You will see a preview first — reply YES to save or NO to cancel.',
        user: false,
      ),
    );
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
        if (intent == 'add_purchase_preview') {
          _pendingPreviewToken = data['preview_token'] as String?;
          final draft = data['entry_draft'];
          _pendingEntryDraft =
              draft is Map ? Map<String, dynamic>.from(draft as Map) : null;
        } else if (intent == 'confirm_saved' ||
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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant'),
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              itemCount: _msgs.length + (_loading ? 1 : 0),
              itemBuilder: (context, i) {
                if (_loading && i == _msgs.length) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 24,
                        height: 24,
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
            elevation: 8,
            shadowColor: Colors.black26,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottom),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Ask or describe a purchase…',
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _loading ? null : _send,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    child: const Icon(Icons.send_rounded, size: 22),
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(bubble.user ? 16 : 4),
                bottomRight: Radius.circular(bubble.user ? 4 : 16),
              ),
              border: Border.all(
                color: bubble.user
                    ? HexaColors.accentInfo.withValues(alpha: 0.35)
                    : cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: SelectableText(
                bubble.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.35,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
