import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/app.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
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
    await Future<void>.delayed(const Duration(milliseconds: 50));
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

    expect(find.text('Mobile Wallet Demo'), findsOneWidget);
    expect(find.text('v1.9.0+20'), findsOneWidget);
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

    expect(find.text('Внешнее устройство заблокировано'), findsOneWidget);
    expect(find.text('PIN устройства'), findsOneWidget);
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

    await tester.tap(find.text('Симулировать offline'));
    await tester.pumpAndSettle();
    expect(find.text('Device offline'), findsOneWidget);

    await tester.tap(find.text('Переподключить demo device'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '5678');
    await tester.tap(find.text('Подключить устройство'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Device online'), findsWidgets);
    expect(find.text('Разорвать device session'), findsOneWidget);

    final pingButton = find.text('Проверить PKCS#11 session');
    await tester.ensureVisible(pingButton);
    await tester.tap(pingButton);
    await tester.pumpAndSettle();
    expect(find.text('PKCS#11 operations'), findsOneWidget);
    expect(find.text('probeSession'), findsOneWidget);

    final readAddressButton = find.text('Прочитать адрес через PKCS#11');
    await tester.ensureVisible(readAddressButton);
    await tester.tap(readAddressButton);
    await tester.pumpAndSettle();
    expect(find.text('Last PKCS#11 operation'), findsOneWidget);
    expect(find.text('readPublicAddress'), findsOneWidget);
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
    await tester.tap(find.text('Пока без биометрии'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.tap(find.text('Разблокировать'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Подготовка и отправка перевода'), findsOneWidget);

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

    expect(find.text('Итоговый debit'), findsOneWidget);
    expect(find.text('Получатель'), findsOneWidget);
    expect(find.textContaining('Preview валиден'), findsOneWidget);
  });

  testWidgets('allows biometric unlock when biometrics are enabled', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
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
    await tester.tap(find.textContaining('Включить биометрию'));
    await tester.pumpAndSettle();

    expect(find.text('Разблокировать биометрией'), findsOneWidget);
    await tester.tap(find.text('Разблокировать биометрией'));
    await tester.pumpAndSettle();

    expect(find.text('Подготовка и отправка перевода'), findsOneWidget);
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
    await tester.tap(find.text('Пока без биометрии'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.tap(find.text('Разблокировать'));
    await tester.pump();
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
    await tester.tap(find.text('Пока без биометрии'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.tap(find.text('Разблокировать'));
    await tester.pump();
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
    await tester.pump();

    expect(find.text('Успешная отправка'), findsOneWidget);
    expect(
      find.textContaining('Транзакция отправлена. Идёт ожидание receipt'),
      findsOneWidget,
    );
    expect(find.text('Подписать и отправить'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 60));
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
    await tester.tap(find.text('Пока без биометрии'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.tap(find.text('Разблокировать'));
    await tester.pump();
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
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('execution reverted'), findsOneWidget);
    expect(find.text('Успешная отправка'), findsNothing);
  });
}
