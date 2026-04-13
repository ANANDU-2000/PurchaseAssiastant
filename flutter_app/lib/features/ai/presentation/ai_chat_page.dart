import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/theme/hexa_colors.dart';

/// Renders `**bold**` segments (same lite markdown as voice preview).
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

class _BubbleMsg {
  const _BubbleMsg({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}

/// In-app purchase assistant — server enforces limits; entries still require preview in the form.
class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _textCtrl = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_BubbleMsg>[];
  bool _busy = false;

  static const _maxTurns = 36;

  @override
  void dispose() {
    _textCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  List<Map<String, dynamic>> _payloadMessages() {
    final out = <Map<String, dynamic>>[];
    for (final m in _msgs) {
      out.add({
        'role': m.isUser ? 'user' : 'assistant',
        'content': m.text,
      });
    }
    return out;
  }

  Future<void> _send() async {
    final raw = _textCtrl.text.trim();
    if (raw.isEmpty || _busy) return;
    HapticFeedback.lightImpact();

    final session = ref.read(sessionProvider);
    if (session == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in again to use the assistant.')),
        );
      }
      return;
    }

    setState(() {
      _msgs.add(_BubbleMsg(text: raw, isUser: true));
      while (_msgs.length > _maxTurns) {
        _msgs.removeAt(0);
      }
      _textCtrl.clear();
      _busy = true;
    });
    _scrollBottom();

    try {
      final api = ref.read(hexaApiProvider);
      final r = await api.aiChat(
        businessId: session.primaryBusiness.id,
        messages: _payloadMessages(),
      );
      final reply = r['reply']?.toString().trim();
      if (!mounted) return;
      setState(() {
        _msgs.add(_BubbleMsg(
          text: (reply == null || reply.isEmpty)
              ? 'No reply from the server. Try again.'
              : reply,
          isUser: false,
        ));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.add(_BubbleMsg(text: friendlyApiError(e), isUser: false));
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
      _scrollBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Assistant',
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            HapticFeedback.selectionClick();
            context.pop();
          },
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Tips: ask about purchases or paste a line like “rice 50kg 42”. '
              'Saving to your books still happens only after Preview → Confirm in Entries.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: _msgs.isEmpty && !_busy
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Ask about your purchases, margins, or paste a quick line to interpret.',
                        textAlign: TextAlign.center,
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
              controller: _scroll,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              itemCount: _msgs.length + (_busy ? 1 : 0),
              itemBuilder: (context, i) {
                if (_busy && i == _msgs.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Thinking…',
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final m = _msgs[i];
                final align =
                    m.isUser ? Alignment.centerRight : Alignment.centerLeft;
                final bg = m.isUser
                    ? HexaColors.primaryMid.withValues(alpha: 0.18)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.85);
                final fg = cs.onSurface;
                final base = tt.bodyMedium?.copyWith(color: fg, height: 1.35);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Align(
                    alignment: align,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.88,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: m.isUser
                              ? SelectableText(
                                  m.text,
                                  style: base,
                                )
                              : SelectableText.rich(
                                  TextSpan(
                                    children: _boldMarkdownSpans(
                                      m.text,
                                      base ?? const TextStyle(),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Message…',
                        filled: true,
                        fillColor: cs.surfaceContainerHighest
                            .withValues(alpha: 0.65),
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
                    onPressed: _busy ? null : _send,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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
