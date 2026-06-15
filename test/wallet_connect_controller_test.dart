import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/airgap/airgap_signing.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
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
    TransactionService? transactionService,
    TransactionBroadcaster? transactionBroadcaster,
    NonceProvider? nonceProvider,
  }) async {
    final controller = WalletFlowController(
      store: InMemorySecureKeyValueStore(),
      biometricAuthGateway: const SimulatedBiometricAuthGateway(),
      walletConnectService: service,
      transactionService: transactionService,
      transactionBroadcaster: transactionBroadcaster,
      nonceProvider: nonceProvider,
    );
    await controller.loadInitialState();
    controller.goToCreateWallet();
    await controller.createWallet(pin: '1234');
    controller.finishSeedBackup();
    await controller.completeBiometricChoice(false);
    await controller.unlockWallet('1234');
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

    await controller.approvePendingRequest();

    expect(controller.pendingRequest, isNull);
    expect(service.respondedErrors, isEmpty);
    expect(service.respondedResults.single.result, '0xBROADCASThash');

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

    await controller.signAirGapRequest(payload);

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

    await controller.signAirGapRequest('garbage');

    expect(controller.airGapResponsePayload, isNull);
    expect(controller.errorMessage, isNotNull);

    controller.dispose();
    await service.dispose();
  });
}
