import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/app.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/phone_secure_vault.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';

class _FakeBlockchainProvider implements BlockchainProvider {
  @override
  Future<WalletChainSnapshot> loadSnapshot({
    required EvmNetwork network,
    required String address,
  }) async {
    return WalletChainSnapshot(
      network: network,
      address: address,
      nativeBalanceWei: BigInt.parse('1230000000000000000'),
      nativeBalanceFormatted: '1.23',
      baseFeeGwei: 12.345,
      providerLabel: 'fake-rpc.local',
      fetchedAtUtc: DateTime.utc(2026, 4, 25, 15, 32),
      tokenBalances: <TokenBalanceSnapshot>[
        TokenBalanceSnapshot(
          symbol: 'USDC',
          name: 'USD Coin',
          balanceFormatted: '42.5',
          rawBalance: BigInt.from(42500000),
          decimals: 6,
          contractAddress: '0xToken',
        ),
      ],
      recentTransactions: const <RecentTransactionSnapshot>[
        RecentTransactionSnapshot(
          hash: '0xTx',
          timestampUtc: null,
          directionLabel: 'Входящая',
          counterparty: '0xCounterparty',
          valueFormatted: '0.25 ETH',
          statusLabel: 'Confirmed',
        ),
      ],
    );
  }
}

class _NetworkBalanceBlockchainProvider implements BlockchainProvider {
  @override
  Future<WalletChainSnapshot> loadSnapshot({
    required EvmNetwork network,
    required String address,
  }) async {
    final isSepolia = network == EvmNetwork.ethereumSepolia;
    return WalletChainSnapshot(
      network: network,
      address: address,
      nativeBalanceWei: isSepolia
          ? BigInt.parse('100000000000000000')
          : BigInt.zero,
      nativeBalanceFormatted: isSepolia ? '0.1' : '0',
      baseFeeGwei: 1,
      providerLabel: 'network-balance.fake',
      fetchedAtUtc: DateTime.utc(2026, 7, 21, 16, 20),
      tokenBalances: const <TokenBalanceSnapshot>[],
      recentTransactions: const <RecentTransactionSnapshot>[],
    );
  }
}

class _OutOfOrderBlockchainProvider implements BlockchainProvider {
  final Completer<WalletChainSnapshot> mainnetSnapshot =
      Completer<WalletChainSnapshot>();

  @override
  Future<WalletChainSnapshot> loadSnapshot({
    required EvmNetwork network,
    required String address,
  }) {
    if (network == EvmNetwork.ethereumMainnet) {
      return mainnetSnapshot.future;
    }
    return Future<WalletChainSnapshot>.value(
      WalletChainSnapshot(
        network: network,
        address: address,
        nativeBalanceWei: BigInt.parse('100000000000000000'),
        nativeBalanceFormatted: '0.1',
        baseFeeGwei: 1,
        providerLabel: 'sepolia-fast.fake',
        fetchedAtUtc: DateTime.utc(2026, 7, 21, 16, 20),
        tokenBalances: const <TokenBalanceSnapshot>[],
        recentTransactions: const <RecentTransactionSnapshot>[],
      ),
    );
  }
}

class _FakeNonceProvider implements NonceProvider {
  @override
  Future<LoadedNonce> loadNextNonce({
    required EvmNetworkConfig networkConfig,
    required String address,
  }) async {
    return LoadedNonce(
      network: networkConfig.network,
      address: address,
      nonce: 7,
      providerLabel: 'nonce.fake',
      loadedAtUtc: DateTime.utc(2026, 4, 26, 19, 40),
    );
  }
}

class _FakeBroadcaster implements TransactionBroadcaster {
  @override
  Future<SubmittedTransfer> submit({
    required SignedTransfer signedTransfer,
  }) async {
    return SubmittedTransfer(
      signedTransfer: signedTransfer,
      providerLabel: 'broadcast.fake',
      networkTransactionHash: '0xsubmittedhash',
      submittedAtUtc: DateTime.utc(2026, 4, 26, 19, 41),
    );
  }
}

class _FailingBroadcaster implements TransactionBroadcaster {
  @override
  Future<SubmittedTransfer> submit({
    required SignedTransfer signedTransfer,
  }) async {
    throw const TransactionFailure(
      'RPC отклонил транзакцию: execution reverted',
    );
  }
}

class _FakeTrackingTransport implements JsonRpcTransport {
  const _FakeTrackingTransport();

  @override
  Future<Map<String, dynamic>> post({
    required Uri uri,
    required Map<String, dynamic> payload,
  }) async {
    if (payload['method'] == 'eth_getTransactionReceipt') {
      return <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 1,
        'result': <String, dynamic>{
          'status': '0x1',
          'blockNumber': '0x10',
          'gasUsed': '0x5208',
        },
      };
    }

    throw const BlockchainFailure('unexpected RPC method in test');
  }
}

class _DelayedTrackingTransport implements JsonRpcTransport {
  const _DelayedTrackingTransport();

  @override
  Future<Map<String, dynamic>> post({
    required Uri uri,
    required Map<String, dynamic> payload,
  }) async {
    // Large delay so the receipt stays pending across a pumpAndSettle (which
    // settles the static success/pending UI without advancing this far), letting
    // the test observe the transient pending state deterministically.
    await Future<void>.delayed(const Duration(seconds: 4));
    return <String, dynamic>{
      'jsonrpc': '2.0',
      'id': 1,
      'result': <String, dynamic>{
        'status': '0x1',
        'blockNumber': '0x10',
        'gasUsed': '0x5208',
      },
    };
  }
}

void main() {
  // Create/unlock run through the real vault; shrink PBKDF2 so the off-isolate
  // derivation is instant (otherwise it races pumpAndSettle vs the progress
  // overlay's perpetual spinner). Reset after each test.
  setUp(() => PhoneSecureVault.debugIterationsOverride = 2);
  tearDown(() => PhoneSecureVault.debugIterationsOverride = null);

  testWidgets('renders onboarding welcome shell for uninitialized wallet', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wallet Demo'), findsOneWidget);
    expect(find.text('v1.38.0+49'), findsOneWidget);
    expect(find.text('Phone Secure Vault'), findsOneWidget);
    expect(find.text('External NFC demo device'), findsOneWidget);
    expect(find.text('Создать новый кошелёк'), findsOneWidget);
    expect(find.text('Импортировать seed-фразу'), findsOneWidget);
  });

  testWidgets('switches to external backend UX branch', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();

    expect(find.text('Подключить demo NFC-устройство'), findsOneWidget);
    expect(find.text('Импортировать seed в demo device'), findsOneWidget);

    await tester.tap(find.text('Подключить demo NFC-устройство').first);
    await tester.pumpAndSettle();

    final setupFields = find.byType(TextField);
    await tester.enterText(setupFields.at(0), '5678');
    await tester.enterText(setupFields.at(1), '5678');
    await tester.tap(find.text('Подключить устройство'));
    await tester.pumpAndSettle();

    // Connecting the device now lands straight on the read-only dashboard, not a
    // locked screen — the device "tap + PIN" path runs per private-key op.
    expect(find.text('Подготовка и отправка перевода'), findsOneWidget);
    expect(find.text('Только просмотр'), findsOneWidget);
    expect(find.text('External NFC demo device'), findsAtLeastNWidgets(1));
  });

  testWidgets('supports external device offline and reconnect states', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подключить demo NFC-устройство').first);
    await tester.pumpAndSettle();

    final setupFields = find.byType(TextField);
    await tester.enterText(setupFields.at(0), '5678');
    await tester.enterText(setupFields.at(1), '5678');
    await tester.tap(find.text('Подключить устройство'));
    await tester.pumpAndSettle();

    // Connecting lands on the read-only dashboard; the device controls live at
    // the bottom of a tall scroll view, so each must be scrolled into view
    // before tapping. Offline/reconnect now STAY on the dashboard and just
    // refresh the runtime tiles — there is no locked screen / re-enter-PIN step.
    final offlineButton = find.text('Симулировать offline');
    await tester.ensureVisible(offlineButton);
    await tester.tap(offlineButton);
    await tester.pumpAndSettle();
    // The offline state shows on the dashboard: the runtime availability chip
    // flips to "Device offline" and the device's offline note is surfaced.
    expect(find.text('Device offline'), findsOneWidget);
    expect(
      find.text('Demo device is offline. Reconnect it before signing.'),
      findsOneWidget,
    );

    final reconnectButton = find.text('Переподключить demo device');
    await tester.ensureVisible(reconnectButton);
    await tester.tap(reconnectButton);
    await tester.pumpAndSettle();

    // Reconnect just flips availability back online on the same dashboard; the
    // send section is still there and the device session control is offered.
    expect(find.text('Device online'), findsOneWidget);
    expect(find.text('Подготовка и отправка перевода'), findsOneWidget);
    expect(find.text('Разорвать device session'), findsOneWidget);

    // Post-refactor the device is locked at rest (no PKCS#11 session until the
    // next private-key op opens one via tap + PIN). Ping / read-address run the
    // PKCS#11 op directly (not through the per-op auth sheet), so with no active
    // session they surface the "no session" error instead of an operation tile.
    final pingButton = find.text('Проверить PKCS#11 session');
    await tester.ensureVisible(pingButton);
    await tester.tap(pingButton);
    await tester.pumpAndSettle();
    expect(
      find.text('No active device session. Connect the demo device first.'),
      findsOneWidget,
    );
    expect(find.text('PKCS#11 operations'), findsNothing);

    final readAddressButton = find.text('Прочитать адрес через PKCS#11');
    await tester.ensureVisible(readAddressButton);
    await tester.tap(readAddressButton);
    await tester.pumpAndSettle();
    expect(
      find.text('No active device session. Connect the demo device first.'),
      findsOneWidget,
    );
    expect(find.text('Last PKCS#11 operation'), findsNothing);
  });

  testWidgets('shows seed backup step after create wallet flow', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
      ),
    );
    await tester.pumpAndSettle();

    final createButton = find.text('Создать новый кошелёк');
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), '1234');
    await tester.enterText(textFields.at(1), '1234');
    await tester.tap(find.text('Создать кошелёк'));
    await tester.pumpAndSettle();

    expect(find.text('Сохраните seed-фразу'), findsOneWidget);
    expect(find.text('Я сохранил seed-фразу'), findsOneWidget);
  });

  testWidgets('shows transfer preparation preview for unlocked wallet', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Создать новый кошелёк'));
    await tester.pumpAndSettle();

    final setupFields = find.byType(TextField);
    await tester.enterText(setupFields.at(0), '1234');
    await tester.enterText(setupFields.at(1), '1234');
    await tester.tap(find.text('Создать кошелёк'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Я сохранил seed-фразу'));
    await tester.pumpAndSettle();
    // The dashboard appears straight after the biometric choice — no unlock.
    await tester.tap(find.text('Пока без биометрии'));
    await tester.pumpAndSettle();

    expect(find.text('Подготовка и отправка перевода'), findsOneWidget);

    // Building the preview is read-only and must not prompt for auth.
    final sendFields = find.byType(TextField);
    await tester.enterText(
      sendFields.at(0),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.enterText(sendFields.at(1), '0.1');
    final previewButton = find.text('Оценить и показать preview');
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(find.text('Подтвердите операцию'), findsNothing);
    expect(find.text('Итоговый debit'), findsOneWidget);
    expect(find.text('Получатель'), findsOneWidget);
    expect(find.textContaining('Preview валиден'), findsOneWidget);
  });

  testWidgets('uses funded balance after switching networks', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _NetworkBalanceBlockchainProvider(),
      ),
    );
    await tester.pumpAndSettle();

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

    expect(find.text('0 ETH'), findsOneWidget);
    await tester.tap(find.text('Ethereum Mainnet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ethereum Sepolia').last);
    await tester.pumpAndSettle();

    expect(find.text('0.1 SepoliaETH'), findsOneWidget);
    expect(find.text('Доступно: 0.1 SepoliaETH'), findsOneWidget);

    final sendFields = find.byType(TextField);
    await tester.enterText(
      sendFields.at(0),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.enterText(sendFields.at(1), '0.05');
    final previewButton = find.text('Оценить и показать preview');
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('Недостаточно'), findsNothing);
    expect(find.textContaining('Preview валиден'), findsOneWidget);
  });

  testWidgets('ignores a late snapshot from the previous network', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _OutOfOrderBlockchainProvider();

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: provider,
      ),
    );
    await tester.pumpAndSettle();

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
    await tester.pump();

    await tester.tap(find.text('Ethereum Mainnet'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Ethereum Sepolia').last);
    await tester.pumpAndSettle();
    expect(find.text('0.1 SepoliaETH'), findsOneWidget);

    provider.mainnetSnapshot.complete(
      WalletChainSnapshot(
        network: EvmNetwork.ethereumMainnet,
        address: '0x0000000000000000000000000000000000000000',
        nativeBalanceWei: BigInt.zero,
        nativeBalanceFormatted: '0',
        baseFeeGwei: 1,
        providerLabel: 'mainnet-late.fake',
        fetchedAtUtc: DateTime.utc(2026, 7, 21, 16, 21),
        tokenBalances: const <TokenBalanceSnapshot>[],
        recentTransactions: const <RecentTransactionSnapshot>[],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0.1 SepoliaETH'), findsOneWidget);
    expect(find.text('0 ETH'), findsNothing);
  });

  testWidgets('offers biometric as a per-op fast-path when enabled', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
        nonceProvider: _FakeNonceProvider(),
        transactionBroadcaster: _FakeBroadcaster(),
        trackingTransport: const _FakeTrackingTransport(),
        biometricAuthGateway: const SimulatedBiometricAuthGateway(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Создать новый кошелёк'));
    await tester.pumpAndSettle();

    final setupFields = find.byType(TextField);
    await tester.enterText(setupFields.at(0), '1234');
    await tester.enterText(setupFields.at(1), '1234');
    await tester.tap(find.text('Создать кошелёк'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Я сохранил seed-фразу'));
    await tester.pumpAndSettle();
    // Enabling biometrics now lands straight on the read-only dashboard; the
    // biometric path becomes a per-operation fast-path instead of an app unlock.
    await tester.tap(find.textContaining('Включить биометрию'));
    await tester.pumpAndSettle();

    expect(find.text('Подготовка и отправка перевода'), findsOneWidget);

    final sendFields = find.byType(TextField);
    await tester.enterText(
      sendFields.at(0),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.enterText(sendFields.at(1), '0.1');

    final sendButton = find.text('Подписать и отправить');
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    // The per-op auth sheet offers the biometric fast-path; use it to sign.
    expect(find.text('Подтвердите операцию'), findsOneWidget);
    final biometricButton = find.text('Разблокировать биометрией');
    expect(biometricButton, findsOneWidget);
    await tester.tap(biometricButton);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Успешная отправка'), findsOneWidget);
  });

  testWidgets('submits signed transfer and shows success state', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
        nonceProvider: _FakeNonceProvider(),
        transactionBroadcaster: _FakeBroadcaster(),
        trackingTransport: const _FakeTrackingTransport(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Создать новый кошелёк'));
    await tester.pumpAndSettle();

    final setupFields = find.byType(TextField);
    await tester.enterText(setupFields.at(0), '1234');
    await tester.enterText(setupFields.at(1), '1234');
    await tester.tap(find.text('Создать кошелёк'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Я сохранил seed-фразу'));
    await tester.pumpAndSettle();
    // Dashboard appears straight after the biometric choice — no unlock step.
    await tester.tap(find.text('Пока без биометрии'));
    await tester.pumpAndSettle();

    final sendFields = find.byType(TextField);
    await tester.enterText(
      sendFields.at(0),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.enterText(sendFields.at(1), '0.1');

    final sendButton = find.text('Подписать и отправить');
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    // Sending is a private-key op: confirm the per-op auth sheet with the PIN.
    expect(find.text('Подтвердите операцию'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Подтвердить'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Успешная отправка'), findsOneWidget);
    expect(find.textContaining('0xsubmittedhash'), findsOneWidget);
    expect(find.textContaining('broadcast.fake'), findsOneWidget);
    expect(find.textContaining('Loaded nonce'), findsOneWidget);
    expect(find.textContaining('Статус: Confirmed'), findsOneWidget);
    expect(find.textContaining('Block: 16'), findsOneWidget);
  });

  testWidgets('keeps tracking async after successful submission', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
        nonceProvider: _FakeNonceProvider(),
        transactionBroadcaster: _FakeBroadcaster(),
        trackingTransport: const _DelayedTrackingTransport(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Создать новый кошелёк'));
    await tester.pumpAndSettle();

    final setupFields = find.byType(TextField);
    await tester.enterText(setupFields.at(0), '1234');
    await tester.enterText(setupFields.at(1), '1234');
    await tester.tap(find.text('Создать кошелёк'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Я сохранил seed-фразу'));
    await tester.pumpAndSettle();
    // Dashboard appears straight after the biometric choice — no unlock step.
    await tester.tap(find.text('Пока без биометрии'));
    await tester.pumpAndSettle();

    final sendFields = find.byType(TextField);
    await tester.enterText(
      sendFields.at(0),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.enterText(sendFields.at(1), '0.1');

    final sendButton = find.text('Подписать и отправить');
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    // Confirm the per-op auth sheet; the unlock+submit then completes while
    // receipt tracking stays pending (delayed transport).
    expect(find.text('Подтвердите операцию'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Подтвердить'));

    // The auth sheet exit + the (microtask-fast, override=2) unlock+submit + the
    // busy overlay all settle here. The receipt transport is delayed 4s — far
    // beyond pumpAndSettle's settling window — and the pending UI has no
    // animation, so pumpAndSettle settles on the transient PENDING state without
    // firing the receipt timer.
    await tester.pumpAndSettle();

    expect(find.text('Успешная отправка'), findsOneWidget);
    expect(
      find.textContaining('Транзакция отправлена. Идёт ожидание receipt'),
      findsOneWidget,
    );
    expect(find.text('Подписать и отправить'), findsOneWidget);

    // Advance past the 4s delayed transport so the receipt resolves.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.textContaining('Статус: Confirmed'), findsOneWidget);
  });

  testWidgets('shows failure state when broadcast is rejected', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
        nonceProvider: _FakeNonceProvider(),
        transactionBroadcaster: _FailingBroadcaster(),
        trackingTransport: const _FakeTrackingTransport(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Создать новый кошелёк'));
    await tester.pumpAndSettle();

    final setupFields = find.byType(TextField);
    await tester.enterText(setupFields.at(0), '1234');
    await tester.enterText(setupFields.at(1), '1234');
    await tester.tap(find.text('Создать кошелёк'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Я сохранил seed-фразу'));
    await tester.pumpAndSettle();
    // Dashboard appears straight after the biometric choice — no unlock step.
    await tester.tap(find.text('Пока без биометрии'));
    await tester.pumpAndSettle();

    final sendFields = find.byType(TextField);
    await tester.enterText(
      sendFields.at(0),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.enterText(sendFields.at(1), '0.1');

    final sendButton = find.text('Подписать и отправить');
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    // Confirm the per-op auth sheet; the broadcast then fails downstream.
    expect(find.text('Подтвердите операцию'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Подтвердить'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('execution reverted'), findsOneWidget);
    expect(find.text('Успешная отправка'), findsNothing);
  });
}
