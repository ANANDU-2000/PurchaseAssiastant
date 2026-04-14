import 'package:flutter/material.dart';

import 'hexa_colors.dart';

/// Premium theme — navy primary, semantic profit/loss, blue accent for info/links only.
ThemeData buildHexaTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  final baseScheme = isDark ? _darkScheme() : _lightScheme();
  final baseText =
      (isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme).apply(
    bodyColor: baseScheme.onSurface,
    displayColor: baseScheme.onSurface,
  );
  final textTheme = baseText.copyWith(
    displayLarge: baseText.displayLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.9,
    ),
    displayMedium: baseText.displayMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
    ),
    displaySmall: baseText.displaySmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.7,
    ),
    headlineLarge: baseText.headlineLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
    ),
    headlineMedium: baseText.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    headlineSmall: baseText.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: baseScheme,
    splashFactory: NoSplash.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      },
    ),
    scaffoldBackgroundColor:
        isDark ? HexaColors.canvas : const Color(0xFFFFFFFF),
    textTheme: textTheme.copyWith(
      titleLarge: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: baseScheme.onSurface,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: baseScheme.onSurface,
      ),
      titleSmall: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: baseScheme.onSurface,
      ),
      bodyLarge: textTheme.bodyLarge?.copyWith(
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: textTheme.bodyMedium?.copyWith(
        height: 1.35,
        color: baseScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
      labelLarge: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
      ),
      labelMedium: textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: baseScheme.onSurfaceVariant,
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      backgroundColor:
          isDark ? HexaColors.canvas : HexaColors.surfaceApp,
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
      unselectedLabelColor: baseScheme.onSurfaceVariant,
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
      color: isDark ? HexaColors.surfaceCard : HexaColors.surfaceCardLight,
      elevation: isDark ? 0 : 0,
      shadowColor: isDark
          ? Colors.transparent
          : HexaColors.primaryNavy.withValues(alpha: 0.06),
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
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        tapTargetSize: MaterialTapTargetSize.padded,
        elevation: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.pressed)) return 0.0;
          return 0.0;
        }),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) {
            return baseScheme.primary.withValues(alpha: 0.38);
          }
          if (s.contains(WidgetState.pressed)) {
            return HexaColors.brandHover;
          }
          if (s.contains(WidgetState.hovered)) {
            return HexaColors.brandHover;
          }
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
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        tapTargetSize: MaterialTapTargetSize.padded,
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
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
      fillColor: isDark
          ? HexaColors.surfaceElevated
          : HexaColors.surfaceCardLight,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide:
            BorderSide(color: baseScheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: baseScheme.tertiary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: textTheme.bodyMedium?.copyWith(
        color: baseScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
      floatingLabelStyle: textTheme.bodySmall?.copyWith(
        color: baseScheme.tertiary,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: baseScheme.onSurfaceVariant.withValues(alpha: 0.92),
      ),
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(
          isDark ? HexaColors.surfaceElevated : HexaColors.surfaceCardLight),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStatePropertyAll(
        BorderSide(color: baseScheme.outlineVariant.withValues(alpha: 0.75)),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      hintStyle: WidgetStatePropertyAll(
        textTheme.bodyMedium?.copyWith(color: baseScheme.onSurfaceVariant),
      ),
      textStyle: WidgetStatePropertyAll(
        textTheme.bodyMedium?.copyWith(color: baseScheme.onSurface),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    dividerTheme: DividerThemeData(
        color: baseScheme.outlineVariant.withValues(alpha: 0.45)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 0,
      highlightElevation: 0,
      backgroundColor: baseScheme.tertiary,
      foregroundColor: baseScheme.onTertiary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? HexaColors.surfaceCard : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? HexaColors.surfaceCard : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? HexaColors.surfaceElevated : Colors.white,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: baseScheme.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
    ),
    chipTheme: ChipThemeData(
      backgroundColor:
          isDark ? HexaColors.surfaceElevated : HexaColors.surfaceCardLight,
      selectedColor: baseScheme.primaryContainer,
      secondarySelectedColor: baseScheme.primaryContainer,
      disabledColor: baseScheme.surfaceContainer,
      side: BorderSide(color: baseScheme.outlineVariant.withValues(alpha: 0.75)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      labelStyle: textTheme.labelMedium?.copyWith(color: baseScheme.onSurface),
      secondaryLabelStyle:
          textTheme.labelMedium?.copyWith(color: baseScheme.onPrimaryContainer),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      brightness: brightness,
    ),
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(48, 48)),
        padding: WidgetStatePropertyAll(EdgeInsets.all(12)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    textButtonTheme: const TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(48, 40)),
        padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    // Slightly roomier than compact; still dense enough for business UIs.
    visualDensity: VisualDensity.standard,
  );
}

ColorScheme _lightScheme() {
  return const ColorScheme(
    brightness: Brightness.light,
    primary: HexaColors.primaryNavy,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFE2E8F0),
    onPrimaryContainer: HexaColors.primaryNavy,
    secondary: HexaColors.accentPurple,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFF3E8FF),
    onSecondaryContainer: const Color(0xFF581C87),
    tertiary: HexaColors.accentInfo,
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFDBEAFE),
    onTertiaryContainer: const Color(0xFF1E3A8A),
    error: HexaColors.loss,
    onError: Colors.white,
    surface: HexaColors.surfaceApp,
    onSurface: HexaColors.textOnLightSurface,
    surfaceContainerHighest: HexaColors.surfaceCardLight,
    surfaceContainerHigh: const Color(0xFFF1F5F9),
    surfaceContainer: const Color(0xFFF4F7FB),
    onSurfaceVariant: HexaColors.neutral,
    outline: const Color(0xFFCBD5E1),
    outlineVariant: const Color(0xFFE2E8F0),
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
