import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// WhatsApp-inspired palette + typography for the in-app assistant.
abstract final class AssistantChatTheme {
  static const Color primary = Color(0xFF075E54);
  static const Color primaryLight = Color(0xFF128C7E);
  static const Color accent = Color(0xFF25D366);
  static const Color background = Color(0xFFEFE5DD);
  static const Color bubbleAi = Color(0xFFFFFFFF);
  static const Color bubbleUser = Color(0xFFDCF8C6);
  static const Color bubbleAiBorder = Color(0x14075E54);
  static const Color previewHighlight = Color(0x3325D366);
  static const Color glassFill = Color(0xCCFFFFFF);
  static const Color onlineDot = Color(0xFF25D366);

  static TextStyle inter(double size, {FontWeight? w, Color? c, double? h}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: w ?? FontWeight.w400,
        color: c ?? const Color(0xFF111B21),
        height: h ?? 1.25,
      );

  static TextStyle jakarta(double size, {FontWeight? w, Color? c, double? h}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: w ?? FontWeight.w600,
        color: c ?? const Color(0xFF111B21),
        height: h ?? 1.2,
      );

  static const Curve motion = Curves.easeOutCubic;
  static const Duration shortAnim = Duration(milliseconds: 220);
  static const Duration mediumAnim = Duration(milliseconds: 340);
}
