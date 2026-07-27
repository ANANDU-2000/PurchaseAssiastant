import 'package:flutter/material.dart';

import '../../theme/hexa_colors.dart';
import '../../theme/hexa_outline_input_border.dart';
import '../hexa_ds_tokens.dart';
import '../hexa_glass_theme.dart';

/// Design-system text field: Inter, 8px-aligned padding, focus ring from tokens.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.errorText,
    this.showSuccess = false,
    this.successMessage,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autocorrect = true,
    this.textCapitalization = TextCapitalization.none,
    this.onSubmitted,
    this.enabled = true,
    this.autofillHints,
    this.onFocusChanged,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;

  /// Shown under the field; also used for semantics error announcement.
  final String? errorText;

  /// When true (and [errorText] is null), shows a calm success border + optional [successMessage].
  final bool showSuccess;
  final String? successMessage;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autocorrect;
  final TextCapitalization textCapitalization;
  final void Function(String)? onSubmitted;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final ValueChanged<bool>? onFocusChanged;

  /// When omitted, an internal node is created and disposed by this widget.
  final FocusNode? focusNode;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  FocusNode? _ownedFocus;

  FocusNode get _effectiveFocus => widget.focusNode ?? _ownedFocus!;

  bool get _ownsFocus => widget.focusNode == null;

  void _onControllerTick() => setState(() {});

  IconData? _defaultLeadingIcon() {
    if (widget.obscureText) return Icons.lock_outline_rounded;
    if (widget.keyboardType == TextInputType.emailAddress) {
      return Icons.mail_outline_rounded;
    }
    return null;
  }

  void _onFocusListen() {
    widget.onFocusChanged?.call(_effectiveFocus.hasFocus);
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerTick);
    if (widget.focusNode == null) {
      _ownedFocus = FocusNode();
    }
    _effectiveFocus.addListener(_onFocusListen);
  }

  @override
  void didUpdateWidget(covariant AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerTick);
      widget.controller.addListener(_onControllerTick);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      final oldNode = oldWidget.focusNode ?? _ownedFocus;
      oldNode?.removeListener(_onFocusListen);
      if (oldWidget.focusNode == null) {
        _ownedFocus?.dispose();
        _ownedFocus = null;
      }
      if (widget.focusNode == null) {
        _ownedFocus = FocusNode();
      }
      _effectiveFocus.addListener(_onFocusListen);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerTick);
    _effectiveFocus.removeListener(_onFocusListen);
    if (_ownsFocus) {
      _ownedFocus?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final focused = _effectiveFocus.hasFocus;
    final hasError =
        widget.errorText != null && widget.errorText!.trim().isNotEmpty;
    final success = widget.showSuccess && !hasError && widget.enabled;
    final shadow = !widget.enabled
        ? hx.inputRestShadow
        : hasError
            ? hx.inputRestShadow
            : focused
                ? hx.inputFocusShadow
                : hx.inputRestShadow;

    final borderColor = hasError
        ? HexaDsColors.error.withValues(alpha: 0.88)
        : success
            ? hx.success
            : hx.borderSubtle;

    final borderWidth = focused ? (hasError || success ? 2.0 : 2.0) : 1.0;

    final helperOrSuccess = hasError
        ? null
        : (success && (widget.successMessage?.trim().isNotEmpty ?? false))
            ? widget.successMessage!.trim()
            : widget.helper;

    final successMessageShown =
        success && (widget.successMessage?.trim().isNotEmpty ?? false);
    final helperStyle = hasError
        ? HexaDsType.body(12, color: HexaDsColors.error.withValues(alpha: 0.92))
        : successMessageShown
            ? HexaDsType.body(12, color: hx.successForeground)
            : HexaDsType.body(12, color: hx.textMuted);

    final normalBorder = OutlineInputBorder(
      borderRadius: HexaDsRadii.input,
      borderSide: BorderSide(color: hx.borderSubtle, width: 1),
    );
    final successBorder = OutlineInputBorder(
      borderRadius: HexaDsRadii.input,
      borderSide:
          BorderSide(color: borderColor, width: focused ? borderWidth : 1),
    );

    return AnimatedScale(
      scale: focused && widget.enabled ? 1.004 : 1.0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: HexaDsRadii.fieldShell,
          boxShadow: shadow,
        ),
        child: ClipRRect(
          borderRadius: HexaDsRadii.fieldShell,
          child: TextField(
            controller: widget.controller,
            focusNode: _effectiveFocus,
            enabled: widget.enabled,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            autocorrect: widget.autocorrect,
            textCapitalization: widget.textCapitalization,
            style: HexaDsType.body(
              15,
              color: widget.enabled ? HexaColors.inputText : hx.textMuted,
            ),
            onSubmitted: widget.onSubmitted,
            autofillHints: widget.autofillHints,
            decoration: InputDecoration(
              labelText: widget.label,
              helperText: hasError ? null : helperOrSuccess,
              errorText: hasError ? widget.errorText : null,
              errorMaxLines: 3,
              hintStyle: HexaDsType.body(
                15,
                color: Theme.of(context).brightness == Brightness.dark
                    ? hx.textMuted.withValues(alpha: 0.92)
                    : HexaColors.inputHint,
              ).copyWith(fontWeight: FontWeight.w400),
              prefixIcon: () {
                final icon = widget.prefixIcon ?? _defaultLeadingIcon();
                if (icon == null) return null;
                return Icon(
                  icon,
                  color: !widget.enabled
                      ? hx.textMuted.withValues(alpha: 0.55)
                      : hasError
                          ? HexaDsColors.error.withValues(alpha: 0.85)
                          : success
                              ? hx.success
                              : focused
                                  ? HexaColors.brandAccent
                                  : hx.textMuted,
                  size: 22,
                );
              }(),
              suffixIcon: widget.suffix,
              filled: true,
              fillColor: widget.enabled ? hx.inputFill : hx.surfaceCanvas,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 15,
              ),
              labelStyle: HexaDsType.label(14, color: hx.textMuted)
                  .copyWith(fontWeight: FontWeight.w500),
              floatingLabelStyle:
                  HexaDsType.label(13, color: hx.textPrimary).copyWith(
                fontWeight: FontWeight.w700,
                color: hasError
                    ? HexaDsColors.error
                    : success
                        ? hx.successForeground
                        : focused
                            ? HexaColors.brandAccent
                            : hx.textPrimary,
              ),
              helperStyle: helperStyle,
              errorStyle: HexaDsType.body(12,
                  color: HexaDsColors.error.withValues(alpha: 0.92)),
              floatingLabelBehavior: FloatingLabelBehavior.auto,
              border: success ? successBorder : normalBorder,
              enabledBorder: success ? successBorder : normalBorder,
              disabledBorder: OutlineInputBorder(
                borderRadius: HexaDsRadii.input,
                borderSide: BorderSide(
                  color: hx.borderSubtle.withValues(alpha: 0.65),
                ),
              ),
              focusedBorder: HexaOutlineInputBorder(
                borderRadius: HexaDsRadii.input,
                borderSide: BorderSide(
                  color: hasError
                      ? HexaDsColors.error.withValues(alpha: 0.95)
                      : success
                          ? hx.success
                          : HexaColors.brandAccent,
                  width: 2,
                ),
                focusRing: true,
                ringColor: hasError
                    ? HexaColors.inputErrorFocusRing
                    : HexaColors.inputFocusRing,
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: HexaDsRadii.input,
                borderSide: BorderSide(
                  color: HexaDsColors.error.withValues(alpha: 0.85),
                  width: 1.2,
                ),
              ),
              focusedErrorBorder: HexaOutlineInputBorder(
                borderRadius: HexaDsRadii.input,
                borderSide: BorderSide(
                  color: HexaDsColors.error.withValues(alpha: 0.95),
                  width: 2,
                ),
                focusRing: true,
                ringColor: HexaColors.inputErrorFocusRing,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
