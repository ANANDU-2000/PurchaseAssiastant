import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'hexa_colors.dart';

/// Premium theme — navy surfaces, teal primary, purple accents.
ThemeData buildHexaTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  final baseScheme = isDark ? _darkScheme() : _lightScheme();

  final baseText = GoogleFonts.dmSansTextTheme(
    isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
  ).apply(
    bodyColor: baseScheme.onSurface,
    displayColor: baseScheme.onSurface,
  );
  final serif = GoogleFonts.dmSerifDisplayTextTheme(baseText);
  final textTheme = baseText.copyWith(
    displaySmall: serif.displaySmall,
    headlineLarge: serif.headlineLarge,
    headlineMedium: serif.headlineMedium,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: baseScheme,
    scaffoldBackgroundColor:
        isDark ? HexaColors.canvas : const Color(0xFFF4F7FB),
    textTheme: textTheme.copyWith(
      titleLarge: textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.35),
      bodyMedium: textTheme.bodyMedium
          ?.copyWith(height: 1.35, color: baseScheme.onSurfaceVariant),
      labelLarge: textTheme.labelLarge
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: HexaColors.accentPurple.withValues(alpha: 0.06),
      centerTitle: false,
      backgroundColor: isDark ? HexaColors.canvas : Colors.white,
      foregroundColor: baseScheme.onSurface,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: baseScheme.onSurface,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelColor: baseScheme.primary,
      unselectedLabelColor: HexaColors.textSecondary,
      indicator: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: baseScheme.primary.withValues(alpha: isDark ? 0.22 : 0.16),
      ),
      labelStyle: textTheme.labelLarge
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.2),
      unselectedLabelStyle:
          textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: isDark ? HexaColors.surfaceCard : Colors.white,
      elevation: isDark ? 0 : 1.5,
      shadowColor: isDark
          ? Colors.transparent
          : HexaColors.primaryDeep.withValues(alpha: 0.07),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
            color: baseScheme.outlineVariant
                .withValues(alpha: isDark ? 0.35 : 0.55)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        elevation: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.pressed)) return 0.0;
          return 1.0;
        }),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) {
            return baseScheme.primary.withValues(alpha: 0.38);
          }
          if (s.contains(WidgetState.pressed)) return HexaColors.brandHover;
          if (s.contains(WidgetState.hovered)) return HexaColors.brandHover;
          return baseScheme.primary;
        }),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        overlayColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.pressed)) {
            return Colors.white.withValues(alpha: 0.12);
          }
          return Colors.white.withValues(alpha: 0.08);
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        side: WidgetStateProperty.resolveWith((s) {
          final c = baseScheme.outline
              .withValues(alpha: s.contains(WidgetState.hovered) ? 1.0 : 0.85);
          return BorderSide(color: c);
        }),
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          final base = isDark ? baseScheme.surfaceContainerHigh : Colors.white;
          if (s.contains(WidgetState.pressed)) {
            return Color.alphaBlend(
                HexaColors.accentBlue.withValues(alpha: 0.14), base);
          }
          if (s.contains(WidgetState.hovered)) {
            return Color.alphaBlend(
                HexaColors.accentBlue.withValues(alpha: 0.10), base);
          }
          return base;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) {
            return baseScheme.onSurface.withValues(alpha: 0.38);
          }
          return HexaColors.accentBlue;
        }),
        overlayColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.pressed)) {
            return HexaColors.accentPurple.withValues(alpha: 0.16);
          }
          return HexaColors.accentPurple.withValues(alpha: 0.08);
        }),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor:
          isDark ? HexaColors.surfaceCard : baseScheme.surfaceContainer,
      indicatorColor:
          baseScheme.primaryContainer.withValues(alpha: isDark ? 0.45 : 0.65),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelMedium?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: 0.15,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected
              ? baseScheme.onPrimaryContainer
              : baseScheme.onSurfaceVariant,
        );
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? HexaColors.surfaceElevated : HexaColors.canvas,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            BorderSide(color: baseScheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: baseScheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    dividerTheme: DividerThemeData(
        color: baseScheme.outlineVariant.withValues(alpha: 0.45)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 2,
      highlightElevation: 4,
      backgroundColor: baseScheme.primary,
      foregroundColor: baseScheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

ColorScheme _lightScheme() {
  return const ColorScheme(
    brightness: Brightness.light,
    primary: HexaColors.primaryDeep,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFCCF4F3),
    onPrimaryContainer: Color(0xFF0A3D3C),
    secondary: HexaColors.accentPurple,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFF3E8FF),
    onSecondaryContainer: Color(0xFF581C87),
    tertiary: HexaColors.accentAmber,
    onTertiary: Colors.white,
    error: HexaColors.loss,
    onError: Colors.white,
    surface: Colors.white,
    onSurface: HexaColors.textOnLightSurface,
    surfaceContainerHighest: Color(0xFFF1F5F9),
    surfaceContainerHigh: Color(0xFFE8EEF4),
    surfaceContainer: Color(0xFFF4F7FB),
    onSurfaceVariant: Color(0xFF64748B),
    outline: Color(0xFFCBD5E1),
    outlineVariant: HexaColors.border,
  );
}

ColorScheme _darkScheme() {
  return const ColorScheme(
    brightness: Brightness.dark,
    primary: HexaColors.primaryMid,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF10302F),
    onPrimaryContainer: Color(0xFFB8F0EF),
    secondary: HexaColors.accentPurple,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFF3D2A6B),
    onSecondaryContainer: Color(0xFFE9D5FF),
    tertiary: Color(0xFF5EEAD4),
    onTertiary: Color(0xFF042A28),
    error: HexaColors.loss,
    onError: Color(0xFF450A0A),
    surface: HexaColors.canvas,
    onSurface: HexaColors.textPrimary,
    surfaceContainerHighest: HexaColors.surfaceElevated,
    surfaceContainerHigh: HexaColors.surfaceCard,
    surfaceContainer: HexaColors.surfaceMuted,
    onSurfaceVariant: HexaColors.textSecondary,
    outline: Color(0xFF475569),
    outlineVariant: Color(0xFF334155),
  );
}
