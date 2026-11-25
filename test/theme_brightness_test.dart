// The app follows the system's light or dark setting (owner decision,
// docs/JOURNAL.md 2026-11-25): the theme, its Nocturne palette and the
// status-bar icons all switch with the platform brightness.
// Flutter 3.50 deprecates the library in favour of package:material_ui;
// see docs/PLAN.md for the migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/app.dart';
import 'package:mobile_wallet_demo/src/design/nocturne_palette.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('a ${brightness.name} system setting gives the '
        '${brightness.name} palette', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        MobileWalletDemoApp(
          locale: const Locale('ru'),
          store: InMemorySecureKeyValueStore(),
        ),
      );
      await tester.pumpAndSettle();

      final expected = brightness == Brightness.light
          ? NocturnePalette.light
          : NocturnePalette.dark;
      final context = tester.element(find.text('Создать кошелёк').first);
      final theme = Theme.of(context);
      expect(theme.brightness, brightness);
      expect(theme.extension<NocturnePalette>(), same(expected));
      expect(theme.scaffoldBackgroundColor, expected.bg);
      expect(theme.colorScheme.primary, expected.accent);

      // Dark status-bar icons over the light ground, light ones over the dark.
      final overlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
      );
      expect(
        overlay.value,
        brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
      );
    });
  }
}
