import 'package:flutter/material.dart';

/// Overlay suggestions anchored to the target field ([LayerLink]) so they paint
/// above wizard fields and the keyboard instead of behind sibling inputs.
class KeyboardAwareSuggestionOverlay extends StatefulWidget {
  const KeyboardAwareSuggestionOverlay({
    super.key,
    required this.controller,
    required this.child,
    required this.overlayChild,
    this.tapRegionGroupId,
  });

  final OverlayPortalController controller;
  final Widget child;
  final Widget overlayChild;
  final Object? tapRegionGroupId;

  @override
  State<KeyboardAwareSuggestionOverlay> createState() =>
      _KeyboardAwareSuggestionOverlayState();
}

class _KeyboardAwareSuggestionOverlayState
    extends State<KeyboardAwareSuggestionOverlay> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: widget.controller,
      overlayChildBuilder: (context) {
        return _RootOverlayHost(
          layerLink: _layerLink,
          fieldKey: _fieldKey,
          tapRegionGroupId: widget.tapRegionGroupId,
          controller: widget.controller,
          overlayChild: widget.overlayChild,
        );
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: KeyedSubtree(
          key: _fieldKey,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Inserts suggestion UI into [Overlay.of(context, rootOverlay: true)].
class _RootOverlayHost extends StatefulWidget {
  const _RootOverlayHost({
    required this.layerLink,
    required this.fieldKey,
    required this.tapRegionGroupId,
    required this.controller,
    required this.overlayChild,
  });

  final LayerLink layerLink;
  final GlobalKey fieldKey;
  final Object? tapRegionGroupId;
  final OverlayPortalController controller;
  final Widget overlayChild;

  @override
  State<_RootOverlayHost> createState() => _RootOverlayHostState();
}

class _RootOverlayHostState extends State<_RootOverlayHost> {
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncEntry());
  }

  @override
  void didUpdateWidget(covariant _RootOverlayHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncEntry());
  }

  @override
  void dispose() {
    _removeEntry();
    super.dispose();
  }

  void _syncEntry() {
    if (!mounted) return;
    if (widget.controller.isShowing) {
      _insertEntry();
    } else {
      _removeEntry();
    }
  }

  void _insertEntry() {
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(builder: _buildOverlay);
    overlay.insert(_entry!);
  }

  void _removeEntry() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  Widget _buildOverlay(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final screenHeight = media.size.height;
    final visibleHeight = screenHeight - keyboardInset;

    final box =
        widget.fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return const SizedBox.shrink();
    }

    final size = box.size;
    final fieldOffset = box.localToGlobal(Offset.zero);
    final fieldBottom = fieldOffset.dy + size.height;

    const overlayHeight = 240.0;
    const gap = 8.0;

    final showAbove = fieldBottom > visibleHeight * 0.55 ||
        (fieldBottom + gap + overlayHeight > visibleHeight - gap);

    return Stack(
      children: [
        Positioned.fill(
          child: TapRegion(
            groupId: widget.tapRegionGroupId,
            onTapOutside: (_) {
              if (!widget.controller.isShowing) return;
              widget.controller.hide();
            },
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        CompositedTransformFollower(
          link: widget.layerLink,
          showWhenUnlinked: false,
          targetAnchor: showAbove ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: showAbove ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(0, showAbove ? -gap : gap),
          child: Material(
            elevation: 12,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            color: Theme.of(context).colorScheme.surface,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: size.width,
                maxHeight: overlayHeight,
              ),
              child: TapRegion(
                groupId: widget.tapRegionGroupId,
                child: widget.overlayChild,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
