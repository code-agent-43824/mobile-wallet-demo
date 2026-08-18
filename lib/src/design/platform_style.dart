import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';

import 'nocturne.dart';

/// Which platform pattern set the UI renders with.
///
/// The design package specifies two full pattern sets side by side — iOS
/// (Apple HIG: large titles, a blurred tab bar, 14px sheets) and Android
/// (Material 3: a top app bar, a navigation bar with a pill indicator, 28px
/// sheets) — and the owner chose to keep them fully separate rather than
/// converge on one look.
///
/// Desktop (Windows x64) is not covered by the design package; per the owner's
/// decision it reuses the same Nocturne theme and the mobile layout, centred
/// and width-limited, instead of getting a bespoke desktop design.
enum AppUiPlatform {
  ios,
  android,
  desktop;

  /// Resolves the pattern set from the current target platform.
  static AppUiPlatform resolve(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppUiPlatform.ios;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return AppUiPlatform.android;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return AppUiPlatform.desktop;
    }
  }
}

/// The platform-varying half of the design tokens.
///
/// Everything here is a value the handoff prototype exposed as a per-platform
/// prop (`uiIos` / `uiAndroid`). Values that do not vary live in
/// [NocturneColors] / [NocturneSpacing] / [NocturneRadius] instead.
@immutable
class PlatformStyle {
  const PlatformStyle({
    required this.platform,
    required this.headerHeight,
    required this.sheetRadius,
    required this.showBackLabel,
    required this.keypadKeyRadius,
    required this.keypadKeyFill,
    required this.activeTabColor,
    required this.activeTabPill,
    required this.fallbackBottomInset,
    required this.maxContentWidth,
  });

  /// iOS / Apple HIG: a 44pt navigation bar, circular keypad keys, a plain
  /// accent-tinted tab item and a text back label.
  factory PlatformStyle.ios() => const PlatformStyle(
    platform: AppUiPlatform.ios,
    headerHeight: 44,
    sheetRadius: 14,
    showBackLabel: true,
    keypadKeyRadius: 999,
    keypadKeyFill: NocturneColors.fillFaint,
    activeTabColor: NocturneColors.accent,
    activeTabPill: null,
    fallbackBottomInset: 34,
    maxContentWidth: double.infinity,
  );

  /// Android / Material 3: a 56dp top app bar, 16dp keypad keys and a filled
  /// pill behind the active navigation-bar item.
  factory PlatformStyle.android() => const PlatformStyle(
    platform: AppUiPlatform.android,
    headerHeight: 56,
    sheetRadius: 28,
    showBackLabel: false,
    keypadKeyRadius: 16,
    keypadKeyFill: NocturneColors.surface,
    activeTabColor: NocturneColors.accent100,
    activeTabPill: NocturneColors.accent800,
    fallbackBottomInset: 24,
    maxContentWidth: double.infinity,
  );

  /// Windows/Linux: the Android pattern set, centred and width-limited so the
  /// mobile layout stays legible on a wide window.
  factory PlatformStyle.desktop() => const PlatformStyle(
    platform: AppUiPlatform.desktop,
    headerHeight: 56,
    sheetRadius: 28,
    showBackLabel: false,
    keypadKeyRadius: 16,
    keypadKeyFill: NocturneColors.surface,
    activeTabColor: NocturneColors.accent100,
    activeTabPill: NocturneColors.accent800,
    fallbackBottomInset: 24,
    maxContentWidth: 460,
  );

  static PlatformStyle forPlatform(AppUiPlatform platform) {
    switch (platform) {
      case AppUiPlatform.ios:
        return PlatformStyle.ios();
      case AppUiPlatform.android:
        return PlatformStyle.android();
      case AppUiPlatform.desktop:
        return PlatformStyle.desktop();
    }
  }

  /// Resolves the style for [context]'s target platform.
  ///
  /// Uses `Theme.of(context).platform` so a widget test can pin the pattern
  /// set with `ThemeData(platform: TargetPlatform.iOS)` without touching a
  /// global override.
  static PlatformStyle of(BuildContext context) =>
      forPlatform(AppUiPlatform.resolve(Theme.of(context).platform));

  final AppUiPlatform platform;

  /// Height of the navigation/app bar.
  final double headerHeight;

  /// Top corner radius of modal sheets.
  final double sheetRadius;

  /// Whether the back affordance carries a text label ("Назад") next to the
  /// chevron, as on iOS, or is an icon alone, as on Android.
  final bool showBackLabel;

  /// Corner radius of a PIN keypad key. `999` means a circle.
  final double keypadKeyRadius;

  /// Fill behind a PIN keypad key.
  final Color keypadKeyFill;

  /// Foreground colour of the selected bottom-navigation item.
  final Color activeTabColor;

  /// Pill behind the selected navigation item, or `null` when the platform
  /// does not draw one.
  final Color? activeTabPill;

  /// Bottom inset to use when the view padding reports none (tests, desktop).
  final double fallbackBottomInset;

  /// Maximum width the app content is allowed to occupy.
  final double maxContentWidth;

  bool get isIos => platform == AppUiPlatform.ios;
  bool get isAndroid => platform == AppUiPlatform.android;
  bool get isDesktop => platform == AppUiPlatform.desktop;

  BorderRadius get sheetBorderRadius =>
      BorderRadius.vertical(top: Radius.circular(sheetRadius));
}
