import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/app.dart';
import 'package:mobile_wallet_demo/src/airgap/airgap_signed_requests.dart';
import 'package:mobile_wallet_demo/src/airgap/eip4527.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/phone_secure_vault.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/qr/qr_scanner.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_service.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_preflight.dart';
import 'package:web3dart/web3dart.dart' show encode, hexToBytes;

String _airGapRequestUr() => const Eip4527Codec().encodeSignRequest(
  EthSignRequest(
    requestId: '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
    signData: Uint8List.fromList(
      hexToBytes(
        '02e80180843b9aca0085069db9ac0082520894'
        '11111111111111111111111111111111111111110180c0',
      ),
    ),
    dataType: EthSignDataType.typedTransaction,
    chainId: 1,
    derivationPath: CryptoKeypath.parse("M/44'/60'/0'/0/0"),
    origin: 'metamask',
  ),
);

/// A Sepolia EIP-1559 call to a token contract: transfer(recipient, 1.5e6).
String _airGapTokenTransferUr() => const Eip4527Codec().encodeSignRequest(
  EthSignRequest(
    requestId: '7b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
    signData: Uint8List.fromList(<int>[
      0x02,
      ...encode(<Object>[
        11155111,
        0,
        1000000000,
        28415994880,
        60000,
        hexToBytes('4444444444444444444444444444444444444444'),
        0,
        hexToBytes(
          'a9059cbb'
          '0000000000000000000000003333333333333333333333333333333333333333'
          '000000000000000000000000000000000000000000000000000000000016e360',
        ),
        <Object>[],
      ]),
    ]),
    dataType: EthSignDataType.typedTransaction,
    chainId: 11155111,
    derivationPath: CryptoKeypath.parse("M/44'/60'/0'/0/0"),
  ),
);

class _SuccessfulPreflight implements WalletConnectTransactionPreflight {
  const _SuccessfulPreflight({
    this.data = const <int>[0x12, 0x34, 0x56, 0x78, 0xaa],
  });

  final List<int> data;

  @override
  Future<WalletConnectTransactionPreview> inspect({
    required WalletConnectRequest request,
    required String walletAddress,
  }) async {
    return WalletConnectTransactionPreview(
      requestId: request.id,
      topic: request.topic,
      chainId: request.chainId,
      network: EvmNetwork.ethereumMainnet,
      fromAddress: walletAddress,
      toAddress: '0x2222222222222222222222222222222222222222',
      valueWei: BigInt.zero,
      data: Uint8List.fromList(data),
      gasLimit: 120000,
      maxFeePerGasWei: BigInt.from(5000000000),
      maxPriorityFeePerGasWei: BigInt.from(1000000000),
      providerLabel: 'fake-rpc',
      wasSimulated: true,
      gasWasEstimated: true,
      feesWereEstimated: true,
    );
  }
}

class _FailingPreflight implements WalletConnectTransactionPreflight {
  const _FailingPreflight();

  @override
  Future<WalletConnectTransactionPreview> inspect({
    required WalletConnectRequest request,
    required String walletAddress,
  }) {
    throw const WalletConnectPreflightFailure(
      'eth_call отклонён: execution reverted: expired',
    );
  }
}

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
  await tester.tap(find.text('Создать кошелёк'));
  await tester.pumpAndSettle();
  final setupFields = find.byType(TextField);
  await tester.enterText(setupFields.at(0), '1234');
  await tester.enterText(setupFields.at(1), '1234');
  await tester.tap(find.text('Создать кошелёк'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Я сохранил seed-фразу'));
  await tester.pumpAndSettle();
  // After "Пока без биометрии" the app now lands straight on the read-only
  // dashboard — there is no separate unlock step.
  await tester.tap(find.text('Пока без биометрии'));
  await tester.pumpAndSettle();
}

/// Reads the active wallet's address from the «Получить» sheet.
Future<String> _readWalletAddress(WidgetTester tester) async {
  await tester.tap(find.text('Получить'));
  await tester.pumpAndSettle();
  final address = tester
      .widget<SelectableText>(find.byType(SelectableText).last)
      .data!;
  await tester.tap(find.text('Закрыть'));
  await tester.pumpAndSettle();
  return address;
}

Future<void> _openConnections(WidgetTester tester) async {
  // The redesign reaches Connections through the shell's «Связи» tab; the old
  // dashboard entry button is gone.
  // The tab sits in the bottom navigation bar, which is not inside a
  // Scrollable, so ensureVisible would throw instead of scrolling.
  await tester.tap(find.text('Связи'));
  await tester.pumpAndSettle();
}

void main() {
  // Shrink PBKDF2 so create/unlock's off-isolate derivation is instant and
  // doesn't race pumpAndSettle against the progress overlay's spinner.
  setUp(() => PhoneSecureVault.debugIterationsOverride = 2);
  tearDown(() => PhoneSecureVault.debugIterationsOverride = null);

  testWidgets('connections screen: pair, approve, disconnect on the fake', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        // Copy assertions are language-specific: pin the locale so a change
        // of system language (or of the default) cannot silently break them.
        locale: const Locale('ru'),

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
        // Copy assertions are language-specific: pin the locale so a change
        // of system language (or of the default) cannot silently break them.
        locale: const Locale('ru'),

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

    await _openSendSheet(tester);
    expect(find.text('Подготовка и отправка перевода'), findsOneWidget);
  });

  testWidgets('connections screen: a token approval says it is unlimited', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final approve = hexToBytes(
      '095ea7b3'
      '0000000000000000000000003333333333333333333333333333333333333333'
      '${'f' * 64}',
    );
    final service = FakeWalletConnectService();
    await tester.pumpWidget(
      MobileWalletDemoApp(
        locale: const Locale('ru'),
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
        walletConnectService: service,
        walletConnectPreflight: _SuccessfulPreflight(data: approve),
      ),
    );
    await tester.pumpAndSettle();
    await _createUnlock(tester);
    await _openConnections(tester);

    service.simulateRequest(
      topic: 'topic-1',
      method: 'eth_sendTransaction',
      chainId: 'eip155:1',
      params: <Object?>[
        <String, Object?>{
          'from': '0x1111111111111111111111111111111111111111',
          'to': '0x2222222222222222222222222222222222222222',
          'data':
              '0x${approve.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
        },
      ],
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('функция 0x095ea7b3'), findsOneWidget);
    expect(
      find.text('Действие с токеном: Разрешение тратить токен ERC-20'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Кому разрешено тратить: '
        '0x3333333333333333333333333333333333333333',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Количество токенов: Без ограничения: все токены, сейчас и в будущем',
      ),
      findsOneWidget,
    );
  });

  for (final (name, chainId, blocked) in <(String, int, bool)>[
    ('on its own network', 1, false),
    ('for another network', 137, true),
  ]) {
    testWidgets('connections screen: a Permit request $name', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = FakeWalletConnectService();
      await tester.pumpWidget(
        MobileWalletDemoApp(
          locale: const Locale('ru'),
          store: InMemorySecureKeyValueStore(),
          blockchainProvider: _FakeBlockchainProvider(),
          walletConnectService: service,
        ),
      );
      await tester.pumpAndSettle();
      await _createUnlock(tester);
      await _openConnections(tester);

      service.simulateRequest(
        topic: 'topic-1',
        method: 'eth_signTypedData_v4',
        chainId: 'eip155:1',
        params: <Object?>[
          '0x1111111111111111111111111111111111111111',
          <String, dynamic>{
            'types': <String, dynamic>{
              'EIP712Domain': <dynamic>[
                <String, String>{'name': 'name', 'type': 'string'},
                <String, String>{'name': 'chainId', 'type': 'uint256'},
                <String, String>{
                  'name': 'verifyingContract',
                  'type': 'address',
                },
              ],
              'Permit': <dynamic>[
                <String, String>{'name': 'owner', 'type': 'address'},
                <String, String>{'name': 'spender', 'type': 'address'},
                <String, String>{'name': 'value', 'type': 'uint256'},
                <String, String>{'name': 'nonce', 'type': 'uint256'},
                <String, String>{'name': 'deadline', 'type': 'uint256'},
              ],
            },
            'primaryType': 'Permit',
            'domain': <String, dynamic>{
              'name': 'USD Coin',
              'chainId': chainId,
              'verifyingContract': '0x3333333333333333333333333333333333333333',
            },
            'message': <String, dynamic>{
              'owner': '0x1111111111111111111111111111111111111111',
              'spender': '0x2222222222222222222222222222222222222222',
              'value': '0x${'f' * 64}',
              'nonce': 0,
              'deadline': 1767225600,
            },
          },
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('позволит другому адресу тратить'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Кому разрешено тратить: 0x2222222222222222222222222222222222222222',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Количество токенов: Без ограничения: все токены, сейчас и в будущем',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Действует до (deadline): 2026-01-01 00:00 UTC'),
        findsOneWidget,
      );
      expect(find.text('Приложение: USD Coin'), findsOneWidget);
      expect(
        find.textContaining('Данные предназначены для сети'),
        blocked ? findsOneWidget : findsNothing,
      );
      final approve = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Одобрить и подписать'),
      );
      expect(approve.onPressed == null, blocked);
    });
  }

  testWidgets('connections screen: an incoming request can be rejected', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = FakeWalletConnectService();
    await tester.pumpWidget(
      MobileWalletDemoApp(
        // Copy assertions are language-specific: pin the locale so a change
        // of system language (or of the default) cannot silently break them.
        locale: const Locale('ru'),

        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
        walletConnectService: service,
        walletConnectPreflight: const _SuccessfulPreflight(),
      ),
    );
    await tester.pumpAndSettle();
    await _createUnlock(tester);
    await _openConnections(tester);

    service.simulateRequest(
      topic: 'topic-1',
      method: 'eth_sendTransaction',
      chainId: 'eip155:1',
      params: const <Object?>[
        <String, Object?>{
          'from': '0x1111111111111111111111111111111111111111',
          'to': '0x2222222222222222222222222222222222222222',
          'value': '0x0',
          'data': '0x',
        },
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Входящий запрос на подпись'), findsOneWidget);
    // The card states the request in plain language now; the raw method name is
    // developer detail and no longer shown.
    expect(find.text('Приложение просит подписать перевод.'), findsOneWidget);
    expect(find.text('Вызов смарт-контракта'), findsOneWidget);
    expect(find.textContaining('функция 0x12345678'), findsOneWidget);
    expect(find.textContaining('Лимит газа: 120000'), findsOneWidget);
    expect(find.text('Проверка в сети: пройдена (fake-rpc)'), findsOneWidget);

    final reject = find.text('Отклонить запрос');
    await tester.ensureVisible(reject);
    await tester.tap(reject);
    await tester.pumpAndSettle();

    expect(find.text('Входящий запрос на подпись'), findsNothing);
    expect(service.respondedErrors, hasLength(1));
  });

  testWidgets('connections screen: chain switch skips the PIN sheet', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = FakeWalletConnectService();
    await tester.pumpWidget(
      MobileWalletDemoApp(
        // Copy assertions are language-specific: pin the locale so a change
        // of system language (or of the default) cannot silently break them.
        locale: const Locale('ru'),

        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
        walletConnectService: service,
      ),
    );
    await tester.pumpAndSettle();
    await _createUnlock(tester);
    await _openConnections(tester);

    service.simulateRequest(
      topic: 'topic-1',
      method: 'wallet_switchEthereumChain',
      params: const <Object?>[
        <String, Object?>{'chainId': '0xaa36a7'},
      ],
    );
    await tester.pumpAndSettle();

    final switchButton = find.text('Переключить сеть');
    await tester.ensureVisible(switchButton);
    await tester.tap(switchButton);
    await tester.pumpAndSettle();

    expect(find.text('Подтвердите операцию'), findsNothing);
    expect(find.text('Входящий запрос на подпись'), findsNothing);
    expect(service.respondedErrors, isEmpty);
    expect(service.respondedResults.single.result, isTrue);
    // Success is said out loud instead of the card silently vanishing.
    expect(
      find.text('Приложение переключено на сеть Ethereum Sepolia.'),
      findsOneWidget,
    );
  });

  // A second tap — or a second sheet a double tap opened — used to act on
  // whichever request was at the head of the queue by then: the next one,
  // which the user never saw.
  for (final (name, label) in <(String, String)>[
    ('approve', 'Переключить сеть'),
    ('reject', 'Отклонить запрос'),
  ]) {
    testWidgets('connections screen: a double tap on $name answers only the '
        'request shown', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeWalletConnectService();
      await tester.pumpWidget(
        MobileWalletDemoApp(
          locale: const Locale('ru'),
          store: InMemorySecureKeyValueStore(),
          blockchainProvider: _FakeBlockchainProvider(),
          walletConnectService: service,
        ),
      );
      await tester.pumpAndSettle();
      await _createUnlock(tester);
      await _openConnections(tester);

      final shown = service.simulateRequest(
        topic: 'topic-1',
        method: 'wallet_switchEthereumChain',
        params: const <Object?>[
          <String, Object?>{'chainId': '0xaa36a7'},
        ],
      );
      final queued = service.simulateRequest(
        topic: 'topic-1',
        method: 'wallet_switchEthereumChain',
        params: const <Object?>[
          <String, Object?>{'chainId': '0x1'},
        ],
      );
      await tester.pumpAndSettle();

      final button = find.text(label);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await tester.pumpAndSettle();

      final answered = <int>[
        for (final result in service.respondedResults) result.id,
        for (final error in service.respondedErrors) error.id,
      ];
      expect(answered, <int>[shown.id]);
      expect(answered, isNot(contains(queued.id)));
      // The queued request is still waiting for its own decision.
      expect(find.text(label), findsOneWidget);
    });
  }

  testWidgets(
    'connections screen: approving a request walks PIN → result in one sheet',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeWalletConnectService();
      await tester.pumpWidget(
        MobileWalletDemoApp(
          locale: const Locale('ru'),
          store: InMemorySecureKeyValueStore(),
          blockchainProvider: _FakeBlockchainProvider(),
          walletConnectService: service,
        ),
      );
      await tester.pumpAndSettle();
      await _createUnlock(tester);
      final address = await _readWalletAddress(tester);
      await _openConnections(tester);

      service.simulateRequest(
        topic: 'topic-1',
        method: 'personal_sign',
        params: <Object?>['0x68656c6c6f', address],
      );
      await tester.pumpAndSettle();

      final approve = find.text('Одобрить и подписать');
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pumpAndSettle();

      // A wrong PIN fails inside the sheet and offers a retry there, rather
      // than closing it and raising the page banner.
      await _enterOperationPin(tester, '0000');
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(find.text('Не получилось'), findsOneWidget);
      expect(find.text('Неверный PIN.'), findsOneWidget);
      expect(service.respondedResults, isEmpty);

      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      await _enterOperationPin(tester, '1234');
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();

      expect(find.text('Ответ отправлен приложению.'), findsOneWidget);
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();

      expect(service.respondedErrors, isEmpty);
      expect(service.respondedResults, hasLength(1));
      expect(find.text('Неверный PIN.'), findsNothing);
    },
  );

  testWidgets('connections screen: failed simulation blocks signing', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = FakeWalletConnectService();
    await tester.pumpWidget(
      MobileWalletDemoApp(
        // Copy assertions are language-specific: pin the locale so a change
        // of system language (or of the default) cannot silently break them.
        locale: const Locale('ru'),

        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
        walletConnectService: service,
        walletConnectPreflight: const _FailingPreflight(),
      ),
    );
    await tester.pumpAndSettle();
    await _createUnlock(tester);
    await _openConnections(tester);

    service.simulateRequest(
      topic: 'topic-1',
      method: 'eth_sendTransaction',
      chainId: 'eip155:11155111',
      params: const <Object?>[
        <String, Object?>{
          'from': '0x1111111111111111111111111111111111111111',
          'to': '0x2222222222222222222222222222222222222222',
          'data': '0x12345678',
        },
      ],
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Подписание недоступно:'), findsOneWidget);
    expect(find.textContaining('execution reverted: expired'), findsOneWidget);
    final approve = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Одобрить и подписать'),
    );
    expect(approve.onPressed, isNull);
    expect(find.text('Подтвердите операцию'), findsNothing);
  });

  testWidgets(
    'connections screen: malformed MetaMask AirGap QR shows an error',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MobileWalletDemoApp(
          // Copy assertions are language-specific: pin the locale so a change
          // of system language (or of the default) cannot silently break them.
          locale: const Locale('ru'),

          store: InMemorySecureKeyValueStore(),
          blockchainProvider: _FakeBlockchainProvider(),
          walletConnectService: FakeWalletConnectService(),
          qrScanner: FakeQrScanner(nextResult: 'not-a-valid-payload'),
        ),
      );
      await tester.pumpAndSettle();
      await _createUnlock(tester);
      await _openConnections(tester);

      final scan = find.text('Сканировать запрос');
      await tester.ensureVisible(scan);
      await tester.tap(scan);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'QR-код не похож на корректный запрос '
          '(expected a value starting with "ur:").',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('AirGap preview reads an ERC-20 transfer', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MobileWalletDemoApp(
        locale: const Locale('ru'),
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
        walletConnectService: FakeWalletConnectService(),
        qrScanner: FakeQrScanner(nextResult: _airGapTokenTransferUr()),
      ),
    );
    await tester.pumpAndSettle();
    await _createUnlock(tester);
    await _openConnections(tester);

    final scan = find.text('Сканировать запрос');
    await tester.ensureVisible(scan);
    await tester.tap(scan);
    await tester.pumpAndSettle();

    expect(find.text('Проверьте транзакцию'), findsOneWidget);
    expect(find.text('Перевод токена ERC-20'), findsOneWidget);
    expect(find.text('Получатель токенов'), findsOneWidget);
    expect(
      find.text('0x3333333333333333333333333333333333333333'),
      findsOneWidget,
    );
    expect(
      find.text(
        '1500000 в минимальных единицах токена '
        '(число знаков после запятой кошельку неизвестно)',
      ),
      findsOneWidget,
    );
  });

  for (final (name, message, shown, warned)
      in <(String, List<int>, String, bool)>[
        (
          'text',
          utf8.encode('Вход на example.org'),
          'Вход на example.org',
          false,
        ),
        ('bytes', List<int>.filled(32, 0xab), '0x${'ab' * 32}', true),
      ]) {
    testWidgets('AirGap personal_sign shows the message ($name)', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final payload = const Eip4527Codec().encodeSignRequest(
        EthSignRequest(
          requestId: '5b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
          signData: Uint8List.fromList(message),
          dataType: EthSignDataType.rawBytes,
          derivationPath: CryptoKeypath.parse("M/44'/60'/0'/0/0"),
        ),
      );

      await tester.pumpWidget(
        MobileWalletDemoApp(
          locale: const Locale('ru'),
          store: InMemorySecureKeyValueStore(),
          blockchainProvider: _FakeBlockchainProvider(),
          walletConnectService: FakeWalletConnectService(),
          qrScanner: FakeQrScanner(nextResult: payload),
        ),
      );
      await tester.pumpAndSettle();
      await _createUnlock(tester);
      await _openConnections(tester);

      final scan = find.text('Сканировать запрос');
      await tester.ensureVisible(scan);
      await tester.tap(scan);
      await tester.pumpAndSettle();

      expect(find.text('Проверьте сообщение'), findsOneWidget);
      expect(find.text(shown), findsOneWidget);
      expect(find.text('Подписать сообщение'), findsOneWidget);
      expect(find.text('Подписать транзакцию'), findsNothing);
      expect(
        find.textContaining('Это не читаемый текст'),
        warned ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('AirGap EIP-712 shows what the signature grants', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final payload = const Eip4527Codec().encodeSignRequest(
      EthSignRequest(
        requestId: '6b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
        signData: Uint8List.fromList(
          utf8.encode(
            jsonEncode(<String, dynamic>{
              'types': <String, dynamic>{
                'EIP712Domain': <dynamic>[
                  <String, String>{'name': 'name', 'type': 'string'},
                  <String, String>{'name': 'chainId', 'type': 'uint256'},
                ],
                'Permit': <dynamic>[
                  <String, String>{'name': 'spender', 'type': 'address'},
                  <String, String>{'name': 'value', 'type': 'uint256'},
                ],
              },
              'primaryType': 'Permit',
              'domain': <String, dynamic>{'name': 'USD Coin', 'chainId': 1},
              'message': <String, dynamic>{
                'spender': '0x2222222222222222222222222222222222222222',
                'value': '5',
              },
            }),
          ),
        ),
        dataType: EthSignDataType.typedData,
        derivationPath: CryptoKeypath.parse("M/44'/60'/0'/0/0"),
      ),
    );

    await tester.pumpWidget(
      MobileWalletDemoApp(
        locale: const Locale('ru'),
        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
        walletConnectService: FakeWalletConnectService(),
        qrScanner: FakeQrScanner(nextResult: payload),
      ),
    );
    await tester.pumpAndSettle();
    await _createUnlock(tester);
    await _openConnections(tester);

    final scan = find.text('Сканировать запрос');
    await tester.ensureVisible(scan);
    await tester.tap(scan);
    await tester.pumpAndSettle();

    expect(find.text('Проверьте данные EIP-712'), findsOneWidget);
    expect(
      find.textContaining('позволит другому адресу тратить'),
      findsOneWidget,
    );
    expect(find.text('Сеть: Ethereum Mainnet'), findsOneWidget);
    expect(find.text('Подписать данные'), findsOneWidget);
  });

  testWidgets('AirGap warns about a request it signed before', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = InMemorySecureKeyValueStore();
    final payload = _airGapRequestUr();
    await AirGapSignedRequestLog(store: store).record(
      const Eip4527Codec().decodeSignRequest(payload.toLowerCase()),
      DateTime.utc(2026, 11, 3, 12, 5),
    );

    await tester.pumpWidget(
      MobileWalletDemoApp(
        locale: const Locale('ru'),
        store: store,
        blockchainProvider: _FakeBlockchainProvider(),
        walletConnectService: FakeWalletConnectService(),
        qrScanner: FakeQrScanner(nextResult: payload),
      ),
    );
    await tester.pumpAndSettle();
    await _createUnlock(tester);
    await _openConnections(tester);

    final scan = find.text('Сканировать запрос');
    await tester.ensureVisible(scan);
    await tester.tap(scan);
    await tester.pumpAndSettle();

    expect(find.textContaining('Этот запрос уже был подписан'), findsOneWidget);
    // Not a block: the request can still be signed on purpose.
    expect(find.text('Подписать транзакцию'), findsOneWidget);
  });

  testWidgets('connections screen previews and signs MetaMask AirGap tx', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scanner = FakeQrScanner(nextResult: _airGapRequestUr());

    await tester.pumpWidget(
      MobileWalletDemoApp(
        // Copy assertions are language-specific: pin the locale so a change
        // of system language (or of the default) cannot silently break them.
        locale: const Locale('ru'),

        store: InMemorySecureKeyValueStore(),
        blockchainProvider: _FakeBlockchainProvider(),
        walletConnectService: FakeWalletConnectService(),
        qrScanner: scanner,
      ),
    );
    await tester.pumpAndSettle();
    await _createUnlock(tester);
    await _openConnections(tester);

    final scan = find.text('Сканировать запрос');
    await tester.ensureVisible(scan);
    await tester.tap(scan);
    await tester.pumpAndSettle();

    expect(find.text('Проверьте транзакцию'), findsOneWidget);
    expect(find.text('Ethereum Mainnet'), findsOneWidget);
    expect(find.text('0.000000000000000001 ETH'), findsOneWidget);
    expect(
      scanner.events,
      contains('camera-ur:MetaMask eth-sign-request:eth-sign-request'),
    );

    final sign = find.text('Подписать транзакцию');
    await tester.ensureVisible(sign);
    await tester.tap(sign);
    await tester.pumpAndSettle();
    await _enterOperationPin(tester, '1234');
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();

    // PIN → signing → result happen in one sheet; its last step says what to
    // do next and hands back to the wizard. The QR is drawn under the sheet,
    // so the text sends the user on rather than promising it here.
    expect(
      find.text(
        'Подпись готова. Нажмите «Продолжить» — QR для MetaMask будет в шаге 3.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(find.text('Подтвердите операцию'), findsNothing);

    // The step number moved into a badge, so the title is the title alone.
    expect(find.text('Верните подпись в MetaMask'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data == 'Один QR-код' ||
                (widget.data?.startsWith('Кадр ') ?? false)),
      ),
      findsWidgets,
    );
  });

  testWidgets(
    'connections screen: loading a QR from file fills the wc: field',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MobileWalletDemoApp(
          // Copy assertions are language-specific: pin the locale so a change
          // of system language (or of the default) cannot silently break them.
          locale: const Locale('ru'),

          store: InMemorySecureKeyValueStore(),
          blockchainProvider: _FakeBlockchainProvider(),
          walletConnectService: FakeWalletConnectService(),
          qrScanner: FakeQrScanner(nextResult: 'wc:scanned@2'),
        ),
      );
      await tester.pumpAndSettle();
      await _createUnlock(tester);
      await _openConnections(tester);

      final load = find.text('Загрузить wc: из файла');
      await tester.ensureVisible(load);
      await tester.tap(load);
      await tester.pumpAndSettle();

      expect(find.text('wc:scanned@2'), findsOneWidget);
    },
  );
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
