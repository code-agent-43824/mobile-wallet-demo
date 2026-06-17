import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/key_storage/phone_secure_vault.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';
import 'package:mobile_wallet_demo/src/wallet_flow_screen.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_service.dart';

/// Drives the wallet state machine straight through [WalletFlowController],
/// without pumping a widget — the unit-test seam the orchestrator refactor
/// unlocked.
void main() {
  // Shrink PBKDF2 (and run it inline, not on a background isolate) so
  // create/unlock are instant in tests.
  setUp(() => PhoneSecureVault.debugIterationsOverride = 2);
  tearDown(() => PhoneSecureVault.debugIterationsOverride = null);

  WalletFlowController buildController() => WalletFlowController(
    store: InMemorySecureKeyValueStore(),
    biometricAuthGateway: const SimulatedBiometricAuthGateway(),
  );

  test('fresh store lands on welcome after loadInitialState', () async {
    final controller = buildController();
    expect(controller.stage, WalletFlowStage.loading);

    await controller.loadInitialState();

    expect(controller.stage, WalletFlowStage.welcome);
    expect(controller.summary, isNull);
    controller.dispose();
  });

  test(
    'create → seed → biometric prompt → read-only dashboard (no unlock)',
    () async {
      final controller = buildController();
      await controller.loadInitialState();

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.goToCreateWallet();
      expect(controller.stage, WalletFlowStage.createWallet);

      await controller.createWallet(pin: '1234');
      expect(controller.stage, WalletFlowStage.showSeed);
      expect(controller.seedPhraseToShow, isNotNull);
      expect(controller.summary, isNotNull);

      controller.finishSeedBackup();
      expect(controller.stage, WalletFlowStage.biometricPrompt);

      // Onboarding now ends straight on the read-only dashboard — no separate
      // unlock step, and no key material is held.
      await controller.completeBiometricChoice(false);
      expect(controller.stage, WalletFlowStage.unlocked);
      expect(controller.material, isNull);

      expect(notifications, greaterThan(0));
      controller.dispose();
    },
  );

  test(
    'a wrong PIN on a per-op sign surfaces an error and holds no key',
    () async {
      final service = FakeWalletConnectService();
      final controller = WalletFlowController(
        store: InMemorySecureKeyValueStore(),
        biometricAuthGateway: const SimulatedBiometricAuthGateway(),
        walletConnectService: service,
        transactionService: const LocalTransactionService(),
      );
      await controller.loadInitialState();
      controller.goToCreateWallet();
      await controller.createWallet(pin: '1234');
      controller.finishSeedBackup();
      await controller.completeBiometricChoice(false);
      expect(controller.stage, WalletFlowStage.unlocked);

      final request = service.simulateRequest(
        topic: 'topic-1',
        method: 'personal_sign',
        chainId: 'eip155:1',
        params: <Object?>['0x48656c6c6f', controller.summary!.address],
      );
      await pumpEventQueue();
      expect(controller.pendingRequest, isNotNull);

      // Wrong PIN: the op fails, the request stays visible (cleared only on
      // success), the dashboard stays put, and no key material lingers.
      await controller.approvePendingRequest(pin: '9999');

      expect(controller.errorMessage, isNotNull);
      expect(controller.stage, WalletFlowStage.unlocked);
      expect(controller.pendingRequest, isNotNull);
      expect(controller.material, isNull);
      expect(service.respondedResults, isEmpty);

      // The correct PIN then signs and clears the request.
      await controller.approvePendingRequest(pin: '1234');
      expect(controller.errorMessage, isNull);
      expect(controller.pendingRequest, isNull);
      expect(controller.material, isNull);
      expect(service.respondedResults.single.id, request.id);

      controller.dispose();
      await service.dispose();
    },
  );
}
