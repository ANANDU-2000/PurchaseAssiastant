import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'keyboard_safe_form_viewport.dart';

/// Full-screen form with keyboard-safe scroll body and footer CTAs merged into the scroll lane.
class FullScreenFormScaffold extends StatelessWidget {
  const FullScreenFormScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    required this.bottom,
    this.actions,
    this.onBackPressed,
  });

  final String title;
  final String? subtitle;
  /// Form fields region (above the pinned scroll footer lane).
  final Widget body;
  /// Primary CTAs rendered above bottom safe area inside the scroll view.
  final Widget bottom;
  final List<Widget>? actions;

  /// When set, used for the leading control (e.g. intercept back for drafts).
  final VoidCallback? onBackPressed;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onBackPressed ??
              () {
                if (context.canPop()) context.pop();
              },
        ),
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        left: true,
        right: true,
        child: KeyboardSafeFormViewport(
          dismissKeyboardOnTap: true,
          fields: body,
          footer: Material(
            elevation: 8,
            color: surface,
            child: bottom,
          ),
        ),
      ),
    );
  }
}
