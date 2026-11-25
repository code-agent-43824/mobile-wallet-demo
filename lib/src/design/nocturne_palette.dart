// Flutter 3.50 deprecates the library in favour of package:material_ui;
// see docs/PLAN.md for the migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'nocturne.dart';

/// Nocturne's colours for one brightness, carried by the theme so the UI
/// follows the system's light or dark setting.
///
/// [dark] is the design package's palette ([NocturneColors]). [light] is
/// derived from it (owner decision, docs/JOURNAL.md 2026-11-25): every colour
/// keeps its OKLCH hue and chroma, and its lightness is mirrored as
/// `L' = 1.185 − L` — the constant maps the dark ground onto the ramp's 100
/// step — so each pair keeps the contrast it has in the dark theme (text on
/// ground 14.8:1 against 14.5:1). Only [accent] is darkened a little further,
/// to 4.5:1 on [surface]. A ramp step therefore keeps its *role* in both
/// themes: `neutral900` is a fill just off the ground, `accent100` is text on
/// an `accent800` tint.
///
/// Widgets read it as `context.nocturne`, never [NocturneColors] directly.
@immutable
class NocturnePalette extends ThemeExtension<NocturnePalette> {
  const NocturnePalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.text,
    required this.accent,
    required this.accent2,
    required this.divider,
    required this.neutral100,
    required this.neutral200,
    required this.neutral300,
    required this.neutral400,
    required this.neutral500,
    required this.neutral600,
    required this.neutral700,
    required this.neutral800,
    required this.neutral900,
    required this.accent100,
    required this.accent200,
    required this.accent300,
    required this.accent400,
    required this.accent500,
    required this.accent600,
    required this.accent700,
    required this.accent800,
    required this.accent900,
    required this.textMuted,
    required this.textSubtle,
    required this.textFaint,
    required this.outlineFaint,
    required this.fillFaint,
    required this.success,
    required this.warning,
    required this.danger,
  });

  static const NocturnePalette dark = NocturnePalette(
    brightness: Brightness.dark,
    bg: NocturneColors.bg,
    surface: NocturneColors.surface,
    text: NocturneColors.text,
    accent: NocturneColors.accent,
    accent2: NocturneColors.accent2,
    divider: NocturneColors.divider,
    neutral100: NocturneColors.neutral100,
    neutral200: NocturneColors.neutral200,
    neutral300: NocturneColors.neutral300,
    neutral400: NocturneColors.neutral400,
    neutral500: NocturneColors.neutral500,
    neutral600: NocturneColors.neutral600,
    neutral700: NocturneColors.neutral700,
    neutral800: NocturneColors.neutral800,
    neutral900: NocturneColors.neutral900,
    accent100: NocturneColors.accent100,
    accent200: NocturneColors.accent200,
    accent300: NocturneColors.accent300,
    accent400: NocturneColors.accent400,
    accent500: NocturneColors.accent500,
    accent600: NocturneColors.accent600,
    accent700: NocturneColors.accent700,
    accent800: NocturneColors.accent800,
    accent900: NocturneColors.accent900,
    textMuted: NocturneColors.textMuted,
    textSubtle: NocturneColors.textSubtle,
    textFaint: NocturneColors.textFaint,
    outlineFaint: NocturneColors.outlineFaint,
    fillFaint: NocturneColors.fillFaint,
    success: NocturneColors.success,
    warning: NocturneColors.warning,
    danger: NocturneColors.danger,
  );

  /// Text tints keep the dark theme's alphas over the light [text].
  static const NocturnePalette light = NocturnePalette(
    brightness: Brightness.light,
    bg: Color(0xFFF3F5FF),
    surface: Color(0xFFDFE2F4),
    text: Color(0xFF212124),
    accent: Color(0xFF6859AA),
    accent2: Color(0xFF544D81),
    divider: Color(0x29212124),
    neutral100: Color(0xFF18191F),
    neutral200: Color(0xFF20222C),
    neutral300: Color(0xFF2E313F),
    neutral400: Color(0xFF454859),
    neutral500: Color(0xFF606476),
    neutral600: Color(0xFF7D8194),
    neutral700: Color(0xFF9B9FB0),
    neutral800: Color(0xFFBBBFCC),
    neutral900: Color(0xFFDADCE4),
    accent100: Color(0xFF191820),
    accent200: Color(0xFF222032),
    accent300: Color(0xFF312B50),
    accent400: Color(0xFF493B82),
    accent500: Color(0xFF6456A7),
    accent600: Color(0xFF8073C7),
    accent700: Color(0xFF9E95DD),
    accent800: Color(0xFFBEB7F0),
    accent900: Color(0xFFDBD8FA),
    textMuted: Color(0x9E212124),
    textSubtle: Color(0x8C212124),
    textFaint: Color(0x73212124),
    outlineFaint: Color(0x4D212124),
    fillFaint: Color(0x17212124),
    success: Color(0xFF2B6343),
    warning: Color(0xFF4F3D02),
    danger: Color(0xFF894244),
  );

  /// The palette of [context]'s theme; the dark one when a theme carries none.
  static NocturnePalette of(BuildContext context) =>
      Theme.of(context).extension<NocturnePalette>() ?? dark;

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color text;
  final Color accent;
  final Color accent2;
  final Color divider;
  final Color neutral100;
  final Color neutral200;
  final Color neutral300;
  final Color neutral400;
  final Color neutral500;
  final Color neutral600;
  final Color neutral700;
  final Color neutral800;
  final Color neutral900;
  final Color accent100;
  final Color accent200;
  final Color accent300;
  final Color accent400;
  final Color accent500;
  final Color accent600;
  final Color accent700;
  final Color accent800;
  final Color accent900;
  final Color textMuted;
  final Color textSubtle;
  final Color textFaint;
  final Color outlineFaint;
  final Color fillFaint;
  final Color success;
  final Color warning;
  final Color danger;

  List<Color> get _colors => <Color>[
    bg,
    surface,
    text,
    accent,
    accent2,
    divider,
    neutral100,
    neutral200,
    neutral300,
    neutral400,
    neutral500,
    neutral600,
    neutral700,
    neutral800,
    neutral900,
    accent100,
    accent200,
    accent300,
    accent400,
    accent500,
    accent600,
    accent700,
    accent800,
    accent900,
    textMuted,
    textSubtle,
    textFaint,
    outlineFaint,
    fillFaint,
    success,
    warning,
    danger,
  ];

  static NocturnePalette _fromColors(Brightness brightness, List<Color> c) =>
      NocturnePalette(
        brightness: brightness,
        bg: c[0],
        surface: c[1],
        text: c[2],
        accent: c[3],
        accent2: c[4],
        divider: c[5],
        neutral100: c[6],
        neutral200: c[7],
        neutral300: c[8],
        neutral400: c[9],
        neutral500: c[10],
        neutral600: c[11],
        neutral700: c[12],
        neutral800: c[13],
        neutral900: c[14],
        accent100: c[15],
        accent200: c[16],
        accent300: c[17],
        accent400: c[18],
        accent500: c[19],
        accent600: c[20],
        accent700: c[21],
        accent800: c[22],
        accent900: c[23],
        textMuted: c[24],
        textSubtle: c[25],
        textFaint: c[26],
        outlineFaint: c[27],
        fillFaint: c[28],
        success: c[29],
        warning: c[30],
        danger: c[31],
      );

  @override
  NocturnePalette copyWith() => this;

  @override
  NocturnePalette lerp(NocturnePalette? other, double t) {
    if (other == null) {
      return this;
    }
    final from = _colors;
    final to = other._colors;
    return _fromColors(t < 0.5 ? brightness : other.brightness, <Color>[
      for (var i = 0; i < from.length; i++) Color.lerp(from[i], to[i], t)!,
    ]);
  }
}

/// `context.nocturne` — the palette of the current theme.
extension NocturneContext on BuildContext {
  NocturnePalette get nocturne => NocturnePalette.of(this);
}
