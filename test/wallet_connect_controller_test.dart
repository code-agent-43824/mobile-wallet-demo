import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/airgap/airgap_signing.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/qr/qr_scanner.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';
import 'package:mobile_wallet_demo/src/wallet_flow_screen.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_service.dart';

class _FakeBroadcaster implements TransactionBroadcaster {
  @override
  Future<SubmittedTransfer> submit({
    required SignedTransfer signedTransfer,
  }) async {
    return SubmittedTransfer(
      signedTransfer: signedTransfer,
      providerLabel: 'fake-rpc',
      networkTransactionHash: '0xBROADCASThash',
      submittedAtUtc: DateTime.utc(2026, 6, 15),
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
      nonce: 11,
      providerLabel: 'fake-nonce',
      loadedAtUtc: DateTime.utc(2026, 6, 15),
    );
  }
}

Map<String, Object?> _txObject({required String from}) => <String, Object?>{
  'from': from,
  'to': '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
  'value': '0x2386f26fc10000',
  'data': '0x',
  'nonce': '0x3',
  'gas': '0x5208',
  'maxFeePerGas': '0x77359400',
  'maxPriorityFeePerGas': '0x3b9aca00',
};

/// 9.4a/9.4c: the WalletConnect seam wired into [WalletFlowController] — pair →
/// proposal → approve/reject → sessions, plus incoming request → sign/respond,
/// driven on the in-memory fake.
void main() {
  Future<WalletFlowController> buildUnlocked(
    WalletConnectService service, {
    SecureKeyValueStore? store,
    TransactionService? transactionService,
    TransactionBroadcaster? transactionBroadcaster,
    NonceProvider? nonceProvider,
    QrScanner qrScanner = const UnavailableQrScanner(),
  }) async {
    final controller = WalletFlowController(
      store: store ?? InMemorySecureKeyValueStore(),
      biometricAuthGateway: const SimulatedBiometricAuthGateway(),
      walletConnectService: service,
      transactionService: transactionService,
      transactionBroadcaster: transactionBroadcaster,
      nonceProvider: nonceProvider,
      qrScanner: qrScanner,
    );
    await controller.loadInitialState();
    controller.goToCreateWallet();
    await controller.createWallet(pin: '1234');
    controller.finishSeedBackup();
    // Onboarding lands straight on the read-only dashboard; no unlock step.
    await controller.completeBiometricChoice(false);
    expect(controller.stage, WalletFlowStage.unlocked);
    return controller;
  }

  test('default service reports WalletConnect unavailable', () async {
    final controller = WalletFlowController(
      store: InMemorySecureKeyValueStore(),
      biometricAuthGateway: const SimulatedBiometricAuthGateway(),
    );
    await controller.loadInitialState();

    expect(controller.isWalletConnectAvailable, isFalse);
    expect(controller.walletConnectSessions, isEmpty);
    expect(controller.pendingProposal, isNull);
    controller.dispose();
  });

  test('pair surfaces a pending proposal', () async {
    final service = FakeWalletConnectService();
    final controller = await buildUnlocked(service);

    await controller.pairWalletConnect(uri: 'wc:demo@2');
    await pumpEventQueue();

    expect(controller.isWalletConnectAvailable, isTrue);
    expect(controller.pendingProposal, isNotNull);
    expect(controller.pendingProposal!.peer.name, 'Demo dApp');

    controller.dispose();
    await service.dispose();
  });

  test('approve binds the wallet account and lists the session', () async {
    final service = FakeWalletConnectService();
    final controller = await buildUnlocked(service);
    final address = controller.summary!.address;

    await controller.pairWalletConnect(uri: 'wc:demo@2');
    await pumpEventQueue();

    await controller.approvePendingProposal();

    expect(controller.pendingProposal, isNull);
    expect(controller.walletConnectSessions, hasLength(1));
    final session = controller.walletConnectSessions.single;
    expect(session.accounts, contains('eip155:1:$address'));

    await controller.disconnectWalletConnectSession(topic: session.topic);
    expect(controller.walletConnectSessions, isEmpty);

    controller.dispose();
    await service.dispose();
  });

  test('reject clears the pending proposal without a session', () async {
    final service = FakeWalletConnectService();
    final controller = await buildUnlocked(service);

    await controller.pairWalletConnect(uri: 'wc:demo@2');
    await pumpEventQueue();
    expect(controller.pendingProposal, isNotNull);

    await controller.rejectPendingProposal();

    expect(controller.pendingProposal, isNull);
    expect(controller.walletConnectSessions, isEmpty);

    controller.dispose();
    await service.dispose();
  });

  test('an invalid pairing URI surfaces an error', () async {
    final service = FakeWalletConnectService();
    final controller = await buildUnlocked(service);

    await controller.pairWalletConnect(uri: 'not-a-wc-uri');

    expect(controller.errorMessage, isNotNull);
    expect(controller.pendingProposal, isNull);

    controller.dispose();
    await service.dispose();
  });

  test('openConnections / closeConnections toggle the stage', () async {
    final service = FakeWalletConnectService();
    final controller = await buildUnlocked(service);

    controller.openConnections();
    expect(controller.stage, WalletFlowStage.connections);

    controller.closeConnections();
    expect(controller.stage, WalletFlowStage.unlocked);

    controller.dispose();
    await service.dispose();
  });

  test('approve incoming request signs and broadcasts', () async {
    final service = FakeWalletConnectService();
    final controller = await buildUnlocked(
      service,
      transactionService: const LocalTransactionService(),
      transactionBroadcaster: _FakeBroadcaster(),
      nonceProvider: _FakeNonceProvider(),
    );

    service.simulateRequest(
      topic: 'topic-1',
      method: 'eth_sendTransaction',
      chainId: 'eip155:1',
      params: <Object?>[_txObject(from: controller.summary!.address)],
    );
    await pumpEventQueue();
    expect(controller.pendingRequest, isNotNull);

    await controller.approvePendingRequest(pin: '1234');

    expect(controller.pendingRequest, isNull);
    expect(service.respondedErrors, isEmpty);
    expect(service.respondedResults.single.result, '0xBROADCASThash');

    controller.dispose();
    await service.dispose();
  });

  test(
    'queues concurrent incoming requests without overwriting either',
    () async {
      final service = FakeWalletConnectService();
      final controller = await buildUnlocked(
        service,
        transactionService: const LocalTransactionService(),
      );
      final address = controller.summary!.address;

      final first = service.simulateRequest(
        topic: 'topic-1',
        method: 'personal_sign',
        chainId: 'eip155:11155111',
        params: <Object?>['0x6669727374', address],
      );
      final second = service.simulateRequest(
        topic: 'topic-1',
        method: 'personal_sign',
        chainId: 'eip155:11155111',
        params: <Object?>['0x7365636f6e64', address],
      );
      await pumpEventQueue();

      expect(controller.pendingRequest!.id, first.id);
      expect(controller.pendingRequestCount, 2);

      await controller.approvePendingRequest(pin: '1234');
      expect(service.respondedResults.single.id, first.id);
      expect(controller.pendingRequest!.id, second.id);
      expect(controller.pendingRequestCount, 1);

      await controller.rejectPendingRequest();
      expect(service.respondedErrors.single.id, second.id);
      expect(controller.pendingRequest, isNull);

      controller.dispose();
      await service.dispose();
    },
  );

  test('chain switch does not unlock the vault or require a PIN', () async {
    final service = FakeWalletConnectService();
    final controller = await buildUnlocked(service);

    service.simulateRequest(
      topic: 'topic-1',
      method: 'wallet_switchEthereumChain',
      params: const <Object?>[
        <String, Object?>{'chainId': '0xaa36a7'},
      ],
    );
    await pumpEventQueue();

    await controller.approvePendingRequest();

    expect(controller.errorMessage, isNull);
    expect(controller.pendingRequest, isNull);
    expect(service.respondedErrors, isEmpty);
    expect(service.respondedResults.single.result, isNull);

    controller.dispose();
    await service.dispose();
  });

  test(
    'loaded wallet summary keeps signing bound to its own backend',
    () async {
      final service = FakeWalletConnectService();
      final controller = await buildUnlocked(
        service,
        transactionService: const LocalTransactionService(),
      );
      final address = controller.summary!.address;

      // Reproduce the stale mutable selection that previously redirected an
      // existing phone wallet to the empty external-device vault.
      await controller.selectBackend('external_nfc_demo_device');
      service.simulateRequest(
        topic: 'topic-1',
        method: 'personal_sign',
        params: <Object?>['0x48656c6c6f', address],
      );
      await pumpEventQueue();

      await controller.approvePendingRequest(pin: '1234');

      expect(controller.errorMessage, isNull);
      expect(service.respondedErrors, isEmpty);
      expect(service.respondedResults.single.result, isA<String>());

      controller.dispose();
      await service.dispose();
    },
  );

  test('wallet survives controller disposal and a cold reload', () async {
    final store = InMemorySecureKeyValueStore();
    final firstService = FakeWalletConnectService();
    final first = await buildUnlocked(firstService, store: store);
    final address = first.summary!.address;
    // Simulate a process death after a stale backend-selection write. Startup
    // must discover the persisted phone wallet instead of showing onboarding.
    await first.selectBackend('external_nfc_demo_device');
    first.dispose();
    await firstService.dispose();

    final secondService = FakeWalletConnectService();
    final second = WalletFlowController(
      store: store,
      biometricAuthGateway: const SimulatedBiometricAuthGateway(),
      walletConnectService: secondService,
      transactionService: const LocalTransactionService(),
    );
    await second.loadInitialState();

    expect(second.stage, WalletFlowStage.unlocked);
    expect(second.summary!.address, address);
    secondService.simulateRequest(
      topic: 'topic-2',
      method: 'personal_sign',
      params: <Object?>['0x636f6c642d7374617274', address],
    );
    await pumpEventQueue();
    await second.approvePendingRequest(pin: '1234');

    expect(second.errorMessage, isNull);
    expect(secondService.respondedResults.single.result, isA<String>());

    second.dispose();
    await secondService.dispose();
  });

  test('approve incoming personal_sign responds with a signature', () async {
    final service = FakeWalletConnectService();
    final controller = await buildUnlocked(
      service,
      transactionService: const LocalTransactionService(),
    );

    service.simulateRequest(
      topic: 'topic-1',
      method: 'personal_sign',
      chainId: 'eip155:1',
      params: <Object?>['0x48656c6c6f', controller.summary!.address],
    );
    await pumpEventQueue();
    expect(controller.pendingRequest, isNotNull);

    await controller.approvePendingRequest(pin: '1234');

    expect(controller.pendingRequest, isNull);
    expect(service.respondedErrors, isEmpty);
    expect(service.respondedResults.single.result, isA<String>());
    expect(service.respondedResults.single.result as String, startsWith('0x'));

    controller.dispose();
    await service.dispose();
  });

  test('reject incoming request responds with an error', () async {
    final service = FakeWalletConnectService();
    final controller = await buildUnlocked(service);

    final request = service.simulateRequest(
      topic: 'topic-1',
      method: 'eth_sendTransaction',
      chainId: 'eip155:1',
      params: <Object?>[_txObject(from: controller.summary!.address)],
    );
    await pumpEventQueue();
    expect(controller.pendingRequest, isNotNull);

    await controller.rejectPendingRequest();

    expect(controller.pendingRequest, isNull);
    expect(service.respondedResults, isEmpty);
    expect(service.respondedErrors.single.id, request.id);

    controller.dispose();
    await service.dispose();
  });

  test('signs an AirGap request payload from this account', () async {
    final service = FakeWalletConnectService();
    final controller = await buildUnlocked(
      service,
      transactionService: const LocalTransactionService(),
    );
    final payload = const AirGapPayloadCodec().encodeRequest(
      AirGapSigningRequest(
        requestId: 'req-air',
        chainId: 'eip155:1',
        fromAddress: controller.summary!.address,
        toAddress: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        valueWeiHex: '0x2386f26fc10000',
        dataHex: '0x',
        nonce: 1,
        gasLimit: 21000,
        maxFeePerGasWeiHex: '0x77359400',
        maxPriorityFeePerGasWeiHex: '0x3b9aca00',
      ),
    );

    await controller.signAirGapRequest(payload, pin: '1234');

    expect(controller.errorMessage, isNull);
    final responsePayload = controller.airGapResponsePayload;
    expect(responsePayload, isNotNull);
    final response = const AirGapPayloadCodec().decodeResponse(
      responsePayload!,
    );
    expect(response.requestId, 'req-air');
    expect(response.rawSignedTransactionHex, startsWith('0x02'));

    controller.clearAirGapResponse();
    expect(controller.airGapResponsePayload, isNull);

    controller.dispose();
    await service.dispose();
  });

  test('a malformed AirGap payload surfaces an error', () async {
    final service = FakeWalletConnectService();
    final controller = await buildUnlocked(service);

    await controller.signAirGapRequest('garbage', pin: '1234');

    expect(controller.airGapResponsePayload, isNull);
    expect(controller.errorMessage, isNotNull);

    controller.dispose();
    await service.dispose();
  });

  test('loadQrFromFile returns the decoded value', () async {
    final service = FakeWalletConnectService();
    final controller = await buildUnlocked(
      service,
      qrScanner: FakeQrScanner(nextResult: 'wc:scanned@2'),
    );

    expect(controller.isQrFileLoadAvailable, isTrue);
    final result = await controller.loadQrFromFile();

    expect(result, 'wc:scanned@2');
    expect(controller.errorMessage, isNull);

    controller.dispose();
    await service.dispose();
  });

  test('QR load surfaces an error when unavailable', () async {
    final service = FakeWalletConnectService();
    final controller = await buildUnlocked(service);

    expect(controller.isQrFileLoadAvailable, isFalse);
    expect(controller.isQrCameraAvailable, isFalse);
    final result = await controller.loadQrFromFile();

    expect(result, isNull);
    expect(controller.errorMessage, isNotNull);

    controller.dispose();
    await service.dispose();
  });

  test(
    'approve incoming eth_signTypedData_v4 responds with a signature',
    () async {
      final service = FakeWalletConnectService();
      final controller = await buildUnlocked(
        service,
        transactionService: const LocalTransactionService(),
      );

      service.simulateRequest(
        topic: 'topic-1',
        method: 'eth_signTypedData_v4',
        chainId: 'eip155:1',
        params: <Object?>[
          controller.summary!.address,
          <String, dynamic>{
            'types': <String, dynamic>{
              'EIP712Domain': <dynamic>[
                <String, String>{'name': 'name', 'type': 'string'},
              ],
              'Msg': <dynamic>[
                <String, String>{'name': 'contents', 'type': 'string'},
              ],
            },
            'primaryType': 'Msg',
            'domain': <String, dynamic>{'name': 'Demo'},
            'message': <String, dynamic>{'contents': 'gm'},
          },
        ],
      );
      await pumpEventQueue();
      expect(controller.pendingRequest, isNotNull);

      await controller.approvePendingRequest(pin: '1234');

      expect(controller.pendingRequest, isNull);
      expect(service.respondedErrors, isEmpty);
      expect(service.respondedResults.single.result, isA<String>());
      expect(
        service.respondedResults.single.result as String,
        startsWith('0x'),
      );

      controller.dispose();
      await service.dispose();
    },
  );
}
