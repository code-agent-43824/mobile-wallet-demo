import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/app.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/custody_backend.dart';
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

class _UnusedRutokenAdapter implements RutokenNativeAdapter {
  @override
  Future<void> cancelPendingOperation() async {}

  @override
  Future<void> closeSession(RutokenNativeSession session) =>
      throw UnimplementedError();

  @override
  Future<WalletAccountDescriptor> importWallet({
    required RutokenNativeSession session,
    required Uint8List masterPrivateKey,
    required Uint8List chainCode,
  }) => throw UnimplementedError();

  @override
  Future<RutokenNativeSession> openSession({required String pin}) =>
      throw UnimplementedError();

  @override
  Future<WalletAccountDescriptor?> readAccountDescriptor(
    RutokenNativeSession session,
  ) => throw UnimplementedError();

  @override
  Future<RawEcdsaSignature> signDigest({
    required RutokenNativeSession session,
    required String derivationPath,
    required Uint8List digest,
  }) => throw UnimplementedError();
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
    expect(find.text('v1.53.0+64'), findsOneWidget);
    // Onboarding variant B: no storage picker on the first screen — the
    // backend follows from which action is taken.
    expect(find.text('Кошелёк за минуту'), findsOneWidget);
    expect(find.text('Phone Secure Vault'), findsNothing);
    expect(find.text('Создать кошелёк'), findsOneWidget);
    expect(find.text('У меня есть карта'), findsOneWidget);
    expect(find.text('Импортировать seed-фразу'), findsOneWidget);
  });

  testWidgets('requires complete backup before Rutoken provisioning', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
        rutokenNativeAdapter: _UnusedRutokenAdapter(),
      ),
    );
    await tester.pumpAndSettle();

    // The card actions are behind «У меня есть карта» now.
    await tester.tap(find.text('У меня есть карта'));
    await tester.pumpAndSettle();

    expect(find.text('Создать на Рутокене'), findsOneWidget);
    expect(find.text('Импортировать в Рутокен'), findsOneWidget);
    expect(find.text('Подключить готовый Рутокен'), findsOneWidget);
    await tester.tap(find.text('Создать на Рутокене'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'offline secret');
    await tester.enterText(fields.at(1), 'offline secret');
    await tester.tap(find.text('Создать резервную фразу'));
    await tester.pumpAndSettle();

    expect(find.text('Сохрани backup до записи на Рутокен'), findsOneWidget);
    expect(find.text('Я сохранил все 24 слова офлайн'), findsOneWidget);
    expect(find.text('Я отдельно сохранил passphrase'), findsOneWidget);
    FilledButton provisionButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Записать ключ на Рутокен'),
    );
    expect(provisionButton().onPressed, isNull);

    await tester.tap(find.text('Я сохранил все 24 слова офлайн'));
    await tester.tap(find.text('Я отдельно сохранил passphrase'));
    await tester.pumpAndSettle();
    expect(provisionButton().onPressed, isNotNull);
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

    final createButton = find.text('Создать кошелёк');
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

    await tester.tap(find.text('Создать кошелёк'));
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

    await _openSendSheet(tester);
    expect(find.text('Подготовка и отправка перевода'), findsOneWidget);

    // Building the preview is read-only and must not prompt for auth.
    final sendFields = find.byType(TextField);
    await tester.enterText(
      sendFields.at(0),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.enterText(sendFields.at(1), '0.1');
    final previewButton = find.text('Проверить перевод');
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

    await tester.tap(find.text('Создать кошелёк'));
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

    // The balance hero renders the figure and the symbol as separate Texts.
    expect(find.text('ETH'), findsWidgets);
    await tester.tap(find.text('Ethereum Mainnet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ethereum Sepolia').last);
    await tester.pumpAndSettle();

    expect(find.text('SepoliaETH'), findsWidgets);

    await _openSendSheet(tester);
    // The available-balance line is part of the transfer form, so it is only on
    // screen once the sheet is open.
    expect(find.text('Доступно: 0.1 SepoliaETH'), findsOneWidget);
    final sendFields = find.byType(TextField);
    await tester.enterText(
      sendFields.at(0),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.enterText(sendFields.at(1), '0.05');
    final previewButton = find.text('Проверить перевод');
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

    await tester.tap(find.text('Создать кошелёк'));
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

    // The network picker is a modal sheet now, so let it finish opening before
    // tapping an entry. This does not weaken the race the test guards: the
    // mainnet request stays pending because pumpAndSettle never completes a
    // Completer.
    await tester.tap(find.text('Ethereum Mainnet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ethereum Sepolia').last);
    await tester.pumpAndSettle();
    expect(find.text('SepoliaETH'), findsWidgets);

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

    expect(find.text('SepoliaETH'), findsWidgets);
    expect(find.text('ETH'), findsNothing);
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

    await tester.tap(find.text('Создать кошелёк'));
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

    await _openSendSheet(tester);
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

    await tester.tap(find.text('Создать кошелёк'));
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

    await _openSendSheet(tester);
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
    await _enterOperationPin(tester, '1234');
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

    await tester.tap(find.text('Создать кошелёк'));
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

    await _openSendSheet(tester);
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
    await _enterOperationPin(tester, '1234');
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

    await tester.tap(find.text('Создать кошелёк'));
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

    await _openSendSheet(tester);
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
    await _enterOperationPin(tester, '1234');
    await tester.tap(find.text('Подтвердить'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('execution reverted'), findsOneWidget);
    expect(find.text('Успешная отправка'), findsNothing);
  });
}

/// Enters an operation PIN on the redesigned keypad. The per-op auth sheet no
/// longer uses a text field, so the digits are tapped.
Future<void> _enterOperationPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.byKey(ValueKey<String>('pin-key-$digit')));
    await tester.pump();
  }
}

/// Opens the transfer sheet. The redesign moved the form off the wallet screen,
/// so every send flow starts by tapping «Отправить».
Future<void> _openSendSheet(WidgetTester tester) async {
  await tester.tap(find.text('Отправить'));
  await tester.pumpAndSettle();
}
