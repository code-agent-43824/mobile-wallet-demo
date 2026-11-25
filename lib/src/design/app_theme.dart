// Flutter 3.50 deprecates the library in favour of package:material_ui;
// see docs/PLAN.md for the migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'nocturne.dart';
import 'nocturne_palette.dart';

/// Builds the app's Nocturne [ThemeData].
///
/// [brightness] picks the [NocturnePalette]: the design package's dark one, or
/// the light one derived from it (owner decision, docs/JOURNAL.md
/// 2026-11-25). The palette also rides on the theme as an extension, so
/// widgets read `context.nocturne`. Everything here reads from the palette /
/// [NocturneSpacing] / [NocturneRadius]; no widget should hard-code a value
/// these tokens already carry.
ThemeData buildNocturneTheme({
  TargetPlatform? platform,
  Brightness brightness = Brightness.dark,
}) {
  final p = brightness == Brightness.light
      ? NocturnePalette.light
      : NocturnePalette.dark;
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: p.bg,
    primaryContainer: p.accent800,
    onPrimaryContainer: p.accent100,
    secondary: p.accent2,
    onSecondary: p.bg,
    surface: p.surface,
    onSurface: p.text,
    onSurfaceVariant: p.textMuted,
    surfaceContainerHighest: p.neutral900,
    error: p.danger,
    onError: p.bg,
    outline: p.neutral800,
    outlineVariant: p.neutral900,
  );

  final textTheme = _buildTextTheme(p);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    extensions: <ThemeExtension<dynamic>>[p],
    platform: platform,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    fontFamily: NocturneType.family,
    textTheme: textTheme,
    dividerColor: p.divider,
    dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: NocturneRadius.mdAll),
    ),
    // The system's primary action is an accent OUTLINE on transparent, never a
    // filled block — so OutlinedButton, not FilledButton, is the default
    // emphasis. FilledButton is left unstyled on purpose to discourage floods.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.accent,
        disabledForegroundColor: p.text.withValues(alpha: 0.45),
        side: BorderSide(color: p.accent),
        shape: const RoundedRectangleBorder(borderRadius: NocturneRadius.mdAll),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        textStyle: textTheme.labelLarge,
        minimumSize: const Size(0, 48),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent400,
        disabledForegroundColor: p.text.withValues(alpha: 0.45),
        shape: const RoundedRectangleBorder(borderRadius: NocturneRadius.mdAll),
        textStyle: textTheme.labelLarge,
      ),
    ),
    iconTheme: IconThemeData(color: p.text, size: 20),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      hintStyle: textTheme.bodyMedium?.copyWith(color: p.textFaint),
      labelStyle: textTheme.bodySmall?.copyWith(color: p.textSubtle),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: NocturneRadius.mdAll,
        borderSide: BorderSide(color: p.neutral800),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: NocturneRadius.mdAll,
        borderSide: BorderSide(color: p.neutral800),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: NocturneRadius.mdAll,
        borderSide: BorderSide(color: p.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: NocturneRadius.mdAll,
        borderSide: BorderSide(color: p.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: NocturneRadius.mdAll,
        borderSide: BorderSide(color: p.danger),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: p.surface,
      showDragHandle: false,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: NocturneRadius.lgAll),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.neutral900,
      contentTextStyle: textTheme.bodyMedium,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: NocturneRadius.mdAll),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? p.accent100 : p.neutral500,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? p.accent700 : p.neutral900,
      ),
      trackOutlineColor: WidgetStateProperty.all(p.neutral800),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.neutral900,
      circularTrackColor: p.neutral900,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.textSubtle,
      textColor: p.text,
    ),
    splashFactory: InkSparkle.splashFactory,
  );
}

/// Type scale taken from the artboards. Hierarchy is size and space, so
/// nothing is bolder than [NocturneType.medium] except numeric balances, where
/// the design uses semibold for the figure itself.
TextTheme _buildTextTheme(NocturnePalette p) {
  final base = TextStyle(color: p.text, fontFamily: NocturneType.family);
  return TextTheme(
    // Balance figure / hero numerals.
    displaySmall: base.copyWith(
      fontSize: 34,
      height: 1.1,
      letterSpacing: -0.6,
      fontWeight: NocturneType.semibold,
    ),
    // Onboarding and sheet titles.
    headlineMedium: base.copyWith(
      fontSize: 28,
      height: 1.14,
      letterSpacing: -0.42,
      fontWeight: NocturneType.medium,
    ),
    headlineSmall: base.copyWith(
      fontSize: 22,
      height: 1.2,
      letterSpacing: -0.3,
      fontWeight: NocturneType.medium,
    ),
    titleLarge: base.copyWith(
      fontSize: 17,
      height: 1.3,
      letterSpacing: -0.2,
      fontWeight: NocturneType.medium,
    ),
    titleMedium: base.copyWith(
      fontSize: 16,
      height: 1.35,
      fontWeight: NocturneType.medium,
    ),
    bodyLarge: base.copyWith(fontSize: 16, height: 1.45),
    bodyMedium: base.copyWith(fontSize: 15, height: 1.55),
    bodySmall: base.copyWith(fontSize: 13, height: 1.45, color: p.textMuted),
    labelLarge: base.copyWith(
      fontSize: 16,
      height: 1.25,
      fontWeight: NocturneType.medium,
    ),
    labelMedium: base.copyWith(fontSize: 13, height: 1.3, color: p.textSubtle),
    labelSmall: base.copyWith(
      fontSize: 11,
      height: 1.3,
      letterSpacing: 0.4,
      color: p.textFaint,
    ),
  );
}
