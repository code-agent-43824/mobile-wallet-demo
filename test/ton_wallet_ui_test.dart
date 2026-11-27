import 'dart:convert';

// Flutter 3.50 migration is tracked in docs/PLAN.md.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_wallet_demo/l10n/app_localizations.dart';
import 'package:mobile_wallet_demo/src/app.dart';
import 'package:mobile_wallet_demo/src/key_storage/custody_backend.dart';
import 'package:mobile_wallet_demo/src/key_storage/phone_secure_vault.dart';
import 'package:mobile_wallet_demo/src/key_storage/phone_ton_vault.dart';
import 'package:mobile_wallet_demo/src/key_storage/rutoken_ton_vault.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/ton/ton_center_client.dart';

import 'fixtures/ton_test_vectors.dart';
import 'package:convert/convert.dart';

const _address = '0QC2w3H-ofk4DSeQynfr5fUiDdiVjxYoi8PGzW9Zd7X-sz0t';

void main() {
  testWidgets(
    'TON card generation requires acknowledging custody on the card',
    (tester) async {
      final store = InMemorySecureKeyValueStore();
      final card = _TonCard();
      final client = TonCenterClient(
        requestInterval: Duration.zero,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'ok': true,
              'result': request.url.pathSegments.last == 'getAddressInformation'
                  ? {'state': 'nonexist', 'balance': '0'}
                  : [],
            }),
            200,
          ),
        ),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MobileWalletDemoApp(
          store: store,
          rutokenNativeAdapter: card,
          tonClient: client,
          locale: const Locale('ru'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('TON Testnet'));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.text('TON Testnet').first),
      );
      await tester.tap(find.text(l10n.tonCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.tonGenerateOnCard));
      await tester.pumpAndSettle();
      expect(find.text(l10n.authConfirmAction), findsNothing);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text(l10n.authConfirmAction));
      await tester.pumpAndSettle();
      expect(card.generations, 1);
      expect(card.closedSessions, 1);
      expect(await store.read(RutokenTonVault.storageKey), isNotNull);
      expect(await store.read(PhoneTonVault.storageKey), isNull);
      expect(find.text(l10n.tonCardOnlyBackup), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('TON welcome entry restores, receives, reviews and signs GRAM', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1100);
    PhoneSecureVault.debugIterationsOverride = 1;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      PhoneSecureVault.debugIterationsOverride = null;
    });
    final store = InMemorySecureKeyValueStore();
    var broadcasts = 0;
    final client = TonCenterClient(
      requestInterval: Duration.zero,
      client: MockClient((request) async {
        final Object result;
        switch (request.url.pathSegments.last) {
          case 'getAddressInformation':
            result = {'balance': '4000000000', 'state': 'active'};
          case 'getWalletInformation':
            result = {
              'balance': '4000000000',
              'seqno': 3,
              'account_state': 'active',
              'wallet_type': 'wallet v5 r1',
            };
          case 'getTransactions':
            result = [];
          case 'estimateFee':
            result = {
              'source_fees': {
                'in_fwd_fee': 500000,
                'storage_fee': 0,
                'gas_fee': 3500000,
                'fwd_fee': 1000000,
              },
            };
          case 'sendBoc':
            broadcasts++;
            expect((jsonDecode(request.body) as Map)['boc'], isA<String>());
            result = {'@type': 'ok'};
          default:
            throw StateError('Unexpected TON RPC request');
        }
        return http.Response(jsonEncode({'ok': true, 'result': result}), 200);
      }),
    );
    addTearDown(client.close);

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: store,
        tonClient: client,
        locale: const Locale('ru'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('TON Testnet'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.text('TON Testnet').first),
    );
    await tester.tap(find.text(l10n.tonImportPhone));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), tonTestMnemonic);
    await tester.enterText(find.byType(TextField).at(1), _address);
    await tester.enterText(find.byType(TextField).at(2), '123456');
    await tester.enterText(find.byType(TextField).at(3), '123456');
    await tester.tap(find.text(l10n.authConfirmAction));
    await _pumpUntil(
      tester,
      () async => await store.read(PhoneTonVault.storageKey) != null,
    );
    await tester.pumpAndSettle();
    expect(find.text('GRAM'), findsOneWidget);

    await tester.tap(find.text(l10n.actionReceive));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == _address,
      ),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.actionClose));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.actionSend));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '0:${'11' * 32}');
    await tester.enterText(find.byType(TextField).at(1), '1,25');
    await tester.tap(find.text(l10n.transferPreviewAction));
    await tester.pumpAndSettle();
    expect(find.text(l10n.wcAmountLine('1.25', 'GRAM')), findsOneWidget);
    expect(broadcasts, 0);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text(l10n.transferSignAndSend));
    await _pumpUntil(tester, () async => broadcasts == 1);
    await tester.pumpAndSettle();
    expect(find.text(l10n.tonSubmitted), findsOneWidget);
    expect(broadcasts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _TonCard implements RutokenTonAdapter {
  int generations = 0;
  int closedSessions = 0;

  @override
  Future<RutokenNativeSession> openSession({required String pin}) async =>
      RutokenNativeSession(
        id: 'ui-test',
        openedAtUtc: DateTime.utc(2026),
        serial: 'test-card',
      );

  @override
  Future<RutokenTonKey> generateTonKey(RutokenNativeSession session) async {
    generations++;
    return RutokenTonKey(
      id: List<int>.filled(16, 9),
      publicKey: hex.decode(
        'f6c450a16bb1c514e22f1977e390a3025599aa1e7b00068a6aacf2119484c1bd',
      ),
      generatedOnCard: true,
    );
  }

  @override
  Future<void> closeSession(RutokenNativeSession session) async =>
      closedSessions++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() ready,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!await ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('The TON wallet operation timed out');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}
