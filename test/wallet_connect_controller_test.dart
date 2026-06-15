import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/wallet_flow_screen.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_service.dart';

/// 9.4a: the WalletConnect seam wired into [WalletFlowController] — pair →
/// proposal → approve/reject → sessions, driven on the in-memory fake. No screen
/// yet (that is 9.4b); this exercises the controller action API directly.
void main() {
  Future<WalletFlowController> buildUnlocked(
    WalletConnectService service,
  ) async {
    final controller = WalletFlowController(
      store: InMemorySecureKeyValueStore(),
      biometricAuthGateway: const SimulatedBiometricAuthGateway(),
      walletConnectService: service,
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
}
