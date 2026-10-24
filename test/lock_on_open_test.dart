import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/key_storage/custody_backend.dart';
import 'package:mobile_wallet_demo/src/key_storage/phone_secure_vault.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/wallet_flow_screen.dart';

void main() {
  setUp(() => PhoneSecureVault.debugIterationsOverride = 2);
  tearDown(() => PhoneSecureVault.debugIterationsOverride = null);

  Future<WalletFlowController> phoneWallet(
    SecureKeyValueStore store, {
    DateTime Function()? now,
  }) async {
    final controller = WalletFlowController(
      store: store,
      biometricAuthGateway: const SimulatedBiometricAuthGateway(),
      now: now,
    );
    await controller.loadInitialState();
    await controller.createWallet(pin: '1234');
    controller.finishSeedBackup();
    await controller.completeBiometricChoice(false);
    expect(controller.stage, WalletFlowStage.unlocked);
    return controller;
  }

  test('off by default; when on, the next start opens locked', () async {
    final store = InMemorySecureKeyValueStore();
    final first = await phoneWallet(store);
    expect(first.lockOnOpenEnabled, isFalse);

    await first.setLockOnOpen(true);
    expect(first.lockOnOpenEnabled, isTrue);
    first.dispose();

    final restarted = WalletFlowController(
      store: store,
      biometricAuthGateway: const SimulatedBiometricAuthGateway(),
    );
    await restarted.loadInitialState();
    expect(restarted.stage, WalletFlowStage.locked);
    expect(restarted.lockOnOpenEnabled, isTrue);

    // A wrong PIN keeps the screen locked; the right one opens the read-only
    // dashboard and keeps no key material.
    await restarted.unlockWallet('0000');
    expect(restarted.stage, WalletFlowStage.locked);
    expect(restarted.errorMessage, isNotNull);
    await restarted.unlockWallet('1234');
    expect(restarted.stage, WalletFlowStage.unlocked);
    expect(restarted.material, isNull);
    restarted.dispose();
  });

  test('re-locks only after a minute in the background', () async {
    var now = DateTime.utc(2026, 10, 24, 12);
    final controller = await phoneWallet(
      InMemorySecureKeyValueStore(),
      now: () => now,
    );
    await controller.setLockOnOpen(true);

    // A file picker or the biometric dialog backgrounds the app briefly.
    controller.appBackgrounded();
    now = now.add(const Duration(seconds: 20));
    controller.appResumed();
    expect(controller.stage, WalletFlowStage.unlocked);

    controller.appBackgrounded();
    now = now.add(WalletFlowController.lockOnOpenGrace);
    controller.appResumed();
    expect(controller.stage, WalletFlowStage.locked);
    controller.dispose();
  });

  test('with lock-on-open off, time away changes nothing', () async {
    var now = DateTime.utc(2026, 10, 24, 12);
    final controller = await phoneWallet(
      InMemorySecureKeyValueStore(),
      now: () => now,
    );
    controller.appBackgrounded();
    now = now.add(const Duration(hours: 1));
    controller.appResumed();
    expect(controller.stage, WalletFlowStage.unlocked);
    controller.dispose();
  });

  test('a card unlocks with its PIN and a tap, then closes', () async {
    final adapter = _CardAdapter();
    final controller = WalletFlowController(
      store: InMemorySecureKeyValueStore(),
      biometricAuthGateway: const SimulatedBiometricAuthGateway(),
      rutokenNativeAdapter: adapter,
    );
    await controller.loadInitialState();
    await controller.adoptExistingRutoken(pin: '1234');
    expect(controller.stage, WalletFlowStage.unlocked);

    controller.lockWallet();
    expect(controller.stage, WalletFlowStage.locked);
    final opened = adapter.openCount;

    await controller.unlockWallet('1234');
    expect(controller.stage, WalletFlowStage.unlocked);
    expect(adapter.openCount, opened + 1);
    expect(adapter.closeCount, adapter.openCount, reason: 'nothing stays open');
    expect(adapter.signCount, 0, reason: 'unlocking signs nothing');

    // A different card is refused, exactly as for a signature.
    controller.lockWallet();
    adapter.address = '0x3333333333333333333333333333333333333333';
    await controller.unlockWallet('1234');
    expect(controller.stage, WalletFlowStage.locked);
    expect(controller.errorMessage, contains('другая карта'));
    controller.dispose();
  });
}

class _CardAdapter implements RutokenNativeAdapter {
  String address = '0x2222222222222222222222222222222222222222';
  int openCount = 0;
  int closeCount = 0;
  int signCount = 0;

  @override
  Future<void> cancelPendingOperation() async {}

  @override
  Future<void> closeSession(RutokenNativeSession session) async {
    closeCount++;
  }

  @override
  Future<WalletAccountDescriptor> importWallet({
    required RutokenNativeSession session,
    required Uint8List masterPrivateKey,
    required Uint8List chainCode,
  }) => throw UnimplementedError();

  @override
  Future<RutokenNativeSession> openSession({required String pin}) async {
    openCount++;
    return RutokenNativeSession(
      id: 'card-$openCount',
      openedAtUtc: DateTime.utc(2026, 10, 24),
    );
  }

  @override
  Future<WalletAccountDescriptor?> readAccountDescriptor(
    RutokenNativeSession session,
  ) async => WalletAccountDescriptor(
    backendId: 'rutoken_nfc',
    address: address,
    derivationPath: "m/44'/60'/0'/0/0",
  );

  @override
  Future<RawEcdsaSignature> signDigest({
    required RutokenNativeSession session,
    required String derivationPath,
    required Uint8List digest,
  }) {
    signCount++;
    throw UnimplementedError();
  }
}
