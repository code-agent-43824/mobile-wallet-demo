import 'package:flutter/material.dart';

import 'nocturne.dart';

/// Builds the app's Nocturne [ThemeData].
///
/// Dark only — the design package defines no light palette, and deriving one
/// would drift from the brand. Everything here reads from [NocturneColors] /
/// [NocturneSpacing] / [NocturneRadius]; no widget should hard-code a value
/// these tokens already carry.
ThemeData buildNocturneTheme({TargetPlatform? platform}) {
  const colorScheme = ColorScheme.dark(
    primary: NocturneColors.accent,
    onPrimary: NocturneColors.bg,
    primaryContainer: NocturneColors.accent800,
    onPrimaryContainer: NocturneColors.accent100,
    secondary: NocturneColors.accent2,
    onSecondary: NocturneColors.bg,
    surface: NocturneColors.surface,
    onSurface: NocturneColors.text,
    onSurfaceVariant: NocturneColors.textMuted,
    surfaceContainerHighest: NocturneColors.neutral900,
    error: NocturneColors.danger,
    onError: NocturneColors.bg,
    outline: NocturneColors.neutral800,
    outlineVariant: NocturneColors.neutral900,
  );

  final textTheme = _buildTextTheme();

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    platform: platform,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: NocturneColors.bg,
    canvasColor: NocturneColors.bg,
    fontFamily: NocturneType.family,
    textTheme: textTheme,
    dividerColor: NocturneColors.divider,
    dividerTheme: const DividerThemeData(
      color: NocturneColors.divider,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: NocturneColors.bg,
      foregroundColor: NocturneColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: const CardThemeData(
      color: NocturneColors.surface,
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
        foregroundColor: NocturneColors.accent,
        disabledForegroundColor: NocturneColors.text.withValues(alpha: 0.45),
        side: const BorderSide(color: NocturneColors.accent),
        shape: const RoundedRectangleBorder(borderRadius: NocturneRadius.mdAll),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        textStyle: textTheme.labelLarge,
        minimumSize: const Size(0, 48),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: NocturneColors.accent400,
        disabledForegroundColor: NocturneColors.text.withValues(alpha: 0.45),
        shape: const RoundedRectangleBorder(borderRadius: NocturneRadius.mdAll),
        textStyle: textTheme.labelLarge,
      ),
    ),
    iconTheme: const IconThemeData(color: NocturneColors.text, size: 20),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: NocturneColors.surface,
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: NocturneColors.textFaint,
      ),
      labelStyle: textTheme.bodySmall?.copyWith(
        color: NocturneColors.textSubtle,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: NocturneRadius.mdAll,
        borderSide: BorderSide(color: NocturneColors.neutral800),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: NocturneRadius.mdAll,
        borderSide: BorderSide(color: NocturneColors.neutral800),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: NocturneRadius.mdAll,
        borderSide: BorderSide(color: NocturneColors.accent),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: NocturneRadius.mdAll,
        borderSide: BorderSide(color: NocturneColors.danger),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: NocturneRadius.mdAll,
        borderSide: BorderSide(color: NocturneColors.danger),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: NocturneColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: NocturneColors.surface,
      showDragHandle: false,
      elevation: 0,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: NocturneColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: NocturneRadius.lgAll),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: NocturneColors.neutral900,
      contentTextStyle: textTheme.bodyMedium,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: NocturneRadius.mdAll),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? NocturneColors.accent100
            : NocturneColors.neutral500,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? NocturneColors.accent700
            : NocturneColors.neutral900,
      ),
      trackOutlineColor: WidgetStateProperty.all(NocturneColors.neutral800),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: NocturneColors.accent,
      linearTrackColor: NocturneColors.neutral900,
      circularTrackColor: NocturneColors.neutral900,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: NocturneColors.textSubtle,
      textColor: NocturneColors.text,
    ),
    splashFactory: InkSparkle.splashFactory,
  );
}

/// Type scale taken from the artboards. Hierarchy is size and space, so
/// nothing is bolder than [NocturneType.medium] except numeric balances, where
/// the design uses semibold for the figure itself.
TextTheme _buildTextTheme() {
  const base = TextStyle(
    color: NocturneColors.text,
    fontFamily: NocturneType.family,
  );
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
    bodySmall: base.copyWith(
      fontSize: 13,
      height: 1.45,
      color: NocturneColors.textMuted,
    ),
    labelLarge: base.copyWith(
      fontSize: 16,
      height: 1.25,
      fontWeight: NocturneType.medium,
    ),
    labelMedium: base.copyWith(
      fontSize: 13,
      height: 1.3,
      color: NocturneColors.textSubtle,
    ),
    labelSmall: base.copyWith(
      fontSize: 11,
      height: 1.3,
      letterSpacing: 0.4,
      color: NocturneColors.textFaint,
    ),
  );
}
