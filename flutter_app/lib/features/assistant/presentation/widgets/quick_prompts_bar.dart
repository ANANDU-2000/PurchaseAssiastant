import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../assistant_chat_theme.dart';
import '../providers/assistant_quick_prompts_provider.dart';

/// Horizontal smart chips (suggestion bar above the composer).
class QuickPromptsBar extends ConsumerWidget {
  const QuickPromptsBar({super.key, required this.onPrompt});

  final void Function(String message) onPrompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prompts = ref.watch(assistantQuickPromptsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (final p in prompts)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Material(
                  color: Colors.white.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(18),
                  elevation: 0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onPrompt(p.message),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        p.label,
                        style: AssistantChatTheme.inter(
                          12,
                          w: FontWeight.w600,
                          c: AssistantChatTheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
