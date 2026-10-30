// Release smoke scenario with real platform storage and network. The create
// and verify phases run in separate app processes on an isolated CI runner.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_wallet_demo/src/app.dart';

/// PIN-derived key stretching (600k PBKDF2 rounds) and the first chain read
/// are real here, so each step may take a while on a slow emulator.
const Duration _stepTimeout = Duration(minutes: 2);
final RegExp _addressPattern = RegExp(r'^0x[0-9a-fA-F]{40}$');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a new wallet reaches the dashboard', (tester) async {
    // The copy below is Russian, the app's primary language.
    await tester.pumpWidget(const MobileWalletDemoApp(locale: Locale('ru')));

    await _tapWhenShown(tester, find.text('Создать кошелёк'));
    await _waitFor(tester, find.byType(TextField));
    final pinFields = find.byType(TextField);
    await tester.enterText(pinFields.at(0), '1234');
    await tester.enterText(pinFields.at(1), '1234');
    await tester.pump();
    await _tapWhenShown(tester, find.text('Создать кошелёк'));

    await _tapWhenShown(tester, find.text('Я сохранил seed-фразу'));
    await _tapWhenShown(tester, find.text('Пока без биометрии'));

    // The dashboard: the four tabs and the wallet's balance card.
    for (final label in <String>[
      'Кошелёк',
      'Активность',
      'Связи',
      'Настройки',
      'Баланс',
      'Получить',
    ]) {
      await _waitFor(tester, find.text(label));
    }

    // The address is public. The PIN and seed phrase never leave the app.
    final address = await _readAddress(tester);
    // ignore: avoid_print
    print('SMOKE_WALLET_ADDRESS=$address');
  });

  testWidgets('the stored wallet survives a separate app launch', (
    tester,
  ) async {
    await tester.pumpWidget(const MobileWalletDemoApp(locale: Locale('ru')));
    final restoredAddress = await _readAddress(tester);
    // The host compares this public address with the create phase's output.
    // ignore: avoid_print
    print('SMOKE_WALLET_RESTORED=$restoredAddress');
  });
}

Future<String> _readAddress(WidgetTester tester) async {
  await _tapWhenShown(tester, find.text('Настройки'));
  await _waitFor(tester, find.text('Активный адрес'));
  final addressFinder = find.byWidgetPredicate(
    (widget) =>
        widget is SelectableText && _addressPattern.hasMatch(widget.data ?? ''),
  );
  await _waitFor(tester, addressFinder);
  expect(addressFinder, findsOneWidget);
  return (addressFinder.evaluate().single.widget as SelectableText).data!;
}

/// Pumps frames until [finder] matches. `pumpAndSettle` cannot be used: the
/// dashboard keeps animating while it loads chain data.
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(_stepTimeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _tapWhenShown(WidgetTester tester, Finder finder) async {
  await _waitFor(tester, finder);
  final target = finder.last;
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
}
