import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/key_storage/phone_secure_vault.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/wallet_flow_screen.dart';

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

  test('create → seed → biometric prompt → locked → unlock', () async {
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

    await controller.completeBiometricChoice(false);
    expect(controller.stage, WalletFlowStage.locked);
    expect(controller.material, isNull);

    await controller.unlockWallet('1234');
    expect(controller.stage, WalletFlowStage.unlocked);
    expect(controller.material, isNotNull);

    expect(notifications, greaterThan(0));
    controller.dispose();
  });

  test('wrong PIN surfaces an error and stays locked', () async {
    final controller = buildController();
    await controller.loadInitialState();
    controller.goToCreateWallet();
    await controller.createWallet(pin: '1234');
    controller.finishSeedBackup();
    await controller.completeBiometricChoice(false);
    expect(controller.stage, WalletFlowStage.locked);

    await controller.unlockWallet('9999');

    expect(controller.stage, WalletFlowStage.locked);
    expect(controller.errorMessage, isNotNull);
    controller.dispose();
  });
}
