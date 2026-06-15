import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/app.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_service.dart';

/// 9.4b: the Connections screen end-to-end through the real widget tree, driven
/// by the injected [FakeWalletConnectService].
class _FakeBlockchainProvider implements BlockchainProvider {
  @override
  Future<WalletChainSnapshot> loadSnapshot({
    required EvmNetwork network,
    required String address,
  }) async {
    return WalletChainSnapshot(
      network: network,
      address: address,
      nativeBalanceWei: BigInt.from(1000000000000000000),
      nativeBalanceFormatted: '1.0',
      baseFeeGwei: 10,
      providerLabel: 'fake-rpc',
      fetchedAtUtc: DateTime.utc(2026, 6, 15),
      tokenBalances: const <TokenBalanceSnapshot>[],
      recentTransactions: const <RecentTransactionSnapshot>[],
    );
  }
}

Future<void> _createUnlock(WidgetTester tester) async {
  await tester.tap(find.text('Создать новый кошелёк'));
  await tester.pumpAndSettle();
  final setupFields = find.byType(TextField);
  await tester.enterText(setupFields.at(0), '1234');
  await tester.enterText(setupFields.at(1), '1234');
  await tester.tap(find.text('Создать кошелёк'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Я сохранил seed-фразу'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Пока без биометрии'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, '1234');
  await tester.tap(find.text('Разблокировать'));
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _openConnections(WidgetTester tester) async {
  final entry = find.text('Подключения (WalletConnect)');
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('connections screen: pair, approve, disconnect on the fake', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
        walletConnectService: FakeWalletConnectService(),
      ),
    );
    await tester.pumpAndSettle();
    await _createUnlock(tester);
    await _openConnections(tester);

    expect(find.text('Новое подключение'), findsOneWidget);
    expect(find.text('Нет активных подключений.'), findsOneWidget);

    // Pair → a proposal arrives from the fake.
    await tester.enterText(find.byType(TextField).first, 'wc:demo@2');
    final pairButton = find.text('Подключить');
    await tester.ensureVisible(pairButton);
    await tester.tap(pairButton);
    await tester.pumpAndSettle();

    expect(find.text('Запрос на подключение'), findsOneWidget);
    expect(find.text('Demo dApp'), findsOneWidget);

    // Approve → the proposal becomes an active session.
    final approve = find.text('Одобрить');
    await tester.ensureVisible(approve);
    await tester.tap(approve);
    await tester.pumpAndSettle();

    expect(find.text('Запрос на подключение'), findsNothing);
    expect(find.text('Активных сессий: 1'), findsOneWidget);
    expect(find.text('Demo dApp'), findsOneWidget);

    // Disconnect → back to no sessions.
    final disconnect = find.text('Отключить');
    await tester.ensureVisible(disconnect);
    await tester.tap(disconnect);
    await tester.pumpAndSettle();

    expect(find.text('Нет активных подключений.'), findsOneWidget);
    expect(find.text('Активных сессий: 0'), findsOneWidget);
  });

  testWidgets('connections screen: back returns to the dashboard', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
        walletConnectService: FakeWalletConnectService(),
      ),
    );
    await tester.pumpAndSettle();
    await _createUnlock(tester);
    await _openConnections(tester);

    expect(find.text('Новое подключение'), findsOneWidget);

    final back = find.text('Назад к кошельку');
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();

    expect(find.text('Подготовка и отправка перевода'), findsOneWidget);
  });
}
