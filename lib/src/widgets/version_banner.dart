// Flutter 3.50 deprecates the library in favour of package:material_ui;
// see docs/PLAN.md for the migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../design/nocturne.dart';
import '../design/nocturne_palette.dart';

/// The build indicator: a thin full-width strip directly under the status bar.
///
/// Deliberately **not** a floating badge. The design brief requires the build
/// marker to occupy layout space rather than hover over the UI, so it can never
/// cover an interactive element. It also absorbs the status-bar inset, so the
/// content below it starts without a second top padding.
class VersionBanner extends StatelessWidget {
  const VersionBanner({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    // iPhone Duo can put the status bar and camera on a side instead of the
    // top, so the label keeps clear of every edge's inset.
    final insets = MediaQuery.viewPaddingOf(context);
    final palette = context.nocturne;
    // The strip sits under the status bar, so the bar's icons take the
    // contrasting tone: dark on the light theme, light on the dark one.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: palette.brightness == Brightness.light
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Material(
        color: context.nocturne.neutral900,
        child: Padding(
          padding: EdgeInsets.only(
            top: insets.top,
            left: insets.left,
            right: insets.right,
          ),
          child: SizedBox(
            width: double.infinity,
            height: 18,
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: NocturneType.family,
                  color: context.nocturne.textFaint,
                  fontSize: 10,
                  height: 1,
                  fontWeight: NocturneType.medium,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
