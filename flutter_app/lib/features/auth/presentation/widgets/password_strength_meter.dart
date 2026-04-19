import 'package:flutter/material.dart';

import 'package:hexa_purchase_assistant/core/design_system/design_system.dart';

/// Visual password strength (client-side hint only).
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password});

  final String password;

  static ({int score, String label, Color color}) evaluate(String p) {
    if (p.isEmpty) {
      return (score: 0, label: '', color: HexaDsColors.textMuted);
    }
    var score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (RegExp('[a-z]').hasMatch(p)) score++;
    if (RegExp('[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'\d').hasMatch(p)) score++;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(p)) score++;

    if (score <= 2) {
      return (score: score, label: 'Weak', color: HexaDsColors.error);
    }
    if (score <= 4) {
      return (score: score, label: 'Fair', color: const Color(0xFFF59E0B));
    }
    if (score <= 5) {
      return (score: score, label: 'Good', color: HexaDsColors.blue);
    }
    return (score: score, label: 'Strong', color: const Color(0xFF059669));
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final ev = evaluate(password);
    if (password.isEmpty) return const SizedBox.shrink();

    const cap = 6;
    final fill = (ev.score / cap).clamp(0.0, 1.0);

    return Semantics(
      label: 'Password strength: ${ev.label}',
      value: '${(fill * 100).round()} percent',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(HexaDsRadii.sm),
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey('${ev.label}-${(fill * 20).round()}'),
                    tween: Tween(begin: 0, end: fill),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) {
                      return LinearProgressIndicator(
                        value: v,
                        minHeight: 6,
                        backgroundColor: hx.borderSubtle,
                        color: ev.color,
                      );
                    },
                  ),
                ),
              ),
              SizedBox(width: HexaDsSpace.s1 + 2),
              Text(
                ev.label,
                style: HexaDsType.label(12, color: ev.color).copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          SizedBox(height: HexaDsSpace.s1 - 2),
          Text(
            'Use 8+ characters with mixed case, numbers, and symbols for best security.',
            style: HexaDsType.body(11, color: hx.textMuted),
          ),
        ],
      ),
    );
  }
}
