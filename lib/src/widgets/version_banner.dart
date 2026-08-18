import 'package:flutter/material.dart';

import '../design/nocturne.dart';

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
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return Material(
      color: NocturneColors.neutral900,
      child: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: SizedBox(
          width: double.infinity,
          height: 18,
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: NocturneType.family,
                color: NocturneColors.textFaint,
                fontSize: 10,
                height: 1,
                fontWeight: NocturneType.medium,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
