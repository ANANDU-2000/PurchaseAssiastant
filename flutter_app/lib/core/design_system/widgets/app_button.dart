import 'package:flutter/material.dart';

import '../hexa_ds_tokens.dart';
import '../hexa_glass_theme.dart';

/// Primary CTA — indigo / blue / violet gradient, soft shadow, hover / press micro-motion.
class AppPrimaryButton extends StatefulWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;

  @override
  State<AppPrimaryButton> createState() => _AppPrimaryButtonState();
}

class _AppPrimaryButtonState extends State<AppPrimaryButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.loading;
    final elevated = _hover && !disabled;
    // Subtle hover lift — kept minimal for a premium SaaS feel.
    final scale = _pressed ? 0.992 : (elevated ? 1.006 : 1.0);

    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Listener(
          onPointerDown: disabled ? null : (_) => setState(() => _pressed = true),
          onPointerUp: disabled ? null : (_) => setState(() => _pressed = false),
          onPointerCancel: disabled ? null : (_) => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: HexaDsRadii.button,
              gradient: HexaDsGradients.primaryCta,
              boxShadow: [
                BoxShadow(
                  color: HexaDsColors.indigo
                      .withValues(alpha: disabled ? 0.2 : (elevated ? 0.5 : 0.35)),
                  blurRadius: disabled ? 12 : (elevated ? 28 : 20),
                  offset: Offset(0, elevated ? 12 : 8),
                ),
                if (elevated && !disabled)
                  BoxShadow(
                    color: HexaDsColors.violet.withValues(alpha: 0.22),
                    blurRadius: 32,
                    offset: Offset.zero,
                  ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: disabled ? null : widget.onPressed,
                borderRadius: HexaDsRadii.button,
                splashColor: Colors.white.withValues(alpha: 0.14),
                highlightColor: Colors.white.withValues(alpha: 0.06),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: widget.loading
                          ? const SizedBox(
                              key: ValueKey('l'),
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              key: const ValueKey('t'),
                              widget.label,
                              style: HexaDsType.button(),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

/// Secondary action — outlined neutral surface (pairs with [AppPrimaryButton]).
class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.dense = false,
    this.enabled = true,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool dense;
  final bool enabled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final busy = loading;
    final effectiveOn = enabled && !busy ? onPressed : null;
    return Semantics(
      button: true,
      enabled: enabled && !busy,
      label: label,
      child: SizedBox(
        width: double.infinity,
        height: dense ? 44 : 48,
        child: OutlinedButton(
          onPressed: effectiveOn,
          style: OutlinedButton.styleFrom(
            foregroundColor: hx.textPrimary,
            backgroundColor: hx.inputFill,
            side: BorderSide(color: hx.borderSubtle),
            shape: RoundedRectangleBorder(borderRadius: HexaDsRadii.button),
            padding: EdgeInsets.symmetric(horizontal: HexaDsSpace.s2, vertical: dense ? 10 : 12),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: busy
                ? SizedBox(
                    key: const ValueKey('sec-loading'),
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: HexaDsColors.indigo.withValues(alpha: 0.9),
                    ),
                  )
                : Opacity(
                    key: const ValueKey('sec-idle'),
                    opacity: enabled ? 1 : 0.55,
                    child: icon == null
                        ? Text(
                            label,
                            style: HexaDsType.label(15).copyWith(color: hx.textPrimary),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              icon!,
                              SizedBox(width: HexaDsSpace.s1),
                              Text(
                                label,
                                style: HexaDsType.label(15).copyWith(color: hx.textPrimary),
                              ),
                            ],
                          ),
                  ),
          ),
        ),
      ),
    );
  }
}
