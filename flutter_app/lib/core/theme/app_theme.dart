import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// HEXA — premium fintech-style theme (teal + slate, high clarity).
ThemeData buildHexaTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  final baseScheme = isDark ? _darkScheme() : _lightScheme();

  final textTheme = GoogleFonts.plusJakartaSansTextTheme(
    isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
  ).apply(
    bodyColor: baseScheme.onSurface,
    displayColor: baseScheme.onSurface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: baseScheme,
    scaffoldBackgroundColor: baseScheme.surface,
    textTheme: textTheme.copyWith(
      titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.35),
      bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.35, color: baseScheme.onSurfaceVariant),
      labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: Colors.transparent,
      foregroundColor: baseScheme.onSurface,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: baseScheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: baseScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.35 : 1),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: baseScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.65)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: baseScheme.outline.withValues(alpha: 0.8)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: baseScheme.surfaceContainer,
      indicatorColor: baseScheme.primaryContainer.withValues(alpha: isDark ? 0.45 : 0.65),
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
          color: selected ? baseScheme.onPrimaryContainer : baseScheme.onSurfaceVariant,
        );
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? baseScheme.surfaceContainerHigh : const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: baseScheme.outlineVariant.withValues(alpha: 0.8)),
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
    dividerTheme: DividerThemeData(color: baseScheme.outlineVariant.withValues(alpha: 0.45)),
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
    primary: Color(0xFF0F766E),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFCCFBF1),
    onPrimaryContainer: Color(0xFF042F2E),
    secondary: Color(0xFF334155),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE2E8F0),
    onSecondaryContainer: Color(0xFF0F172A),
    tertiary: Color(0xFF6366F1),
    onTertiary: Colors.white,
    error: Color(0xFFDC2626),
    onError: Colors.white,
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF0F172A),
    surfaceContainerHighest: Color(0xFFF1F5F9),
    surfaceContainerHigh: Color(0xFFE8EEF4),
    surfaceContainer: Color(0xFFF8FAFC),
    onSurfaceVariant: Color(0xFF64748B),
    outline: Color(0xFFCBD5E1),
    outlineVariant: Color(0xFFE2E8F0),
  );
}

ColorScheme _darkScheme() {
  return const ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF2DD4BF),
    onPrimary: Color(0xFF04201C),
    primaryContainer: Color(0xFF134E4A),
    onPrimaryContainer: Color(0xFFCCFBF1),
    secondary: Color(0xFF94A3B8),
    onSecondary: Color(0xFF0F172A),
    secondaryContainer: Color(0xFF334155),
    onSecondaryContainer: Color(0xFFF1F5F9),
    tertiary: Color(0xFFA5B4FC),
    onTertiary: Color(0xFF1E1B4B),
    error: Color(0xFFF87171),
    onError: Color(0xFF450A0A),
    surface: Color(0xFF0C0F14),
    onSurface: Color(0xFFF8FAFC),
    surfaceContainerHighest: Color(0xFF1E293B),
    surfaceContainerHigh: Color(0xFF1A2230),
    surfaceContainer: Color(0xFF121826),
    onSurfaceVariant: Color(0xFF94A3B8),
    outline: Color(0xFF475569),
    outlineVariant: Color(0xFF2A3341),
  );
}
