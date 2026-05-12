import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/auth/wallet_operation_auth.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';

void main() {
  test(
    'authorizes unlocked local signing through backend-compatible contract',
    () {
      const authorizer = WalletOperationAuthorizer();
      const walletMaterial = WalletMaterial(
        address: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
        mnemonic: 'test test test test test test test test test test test junk',
        privateKeyHex:
            'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
      );

      final operation = authorizer.authorizeUnlockedLocalSigning(
        backend: _FakeUnlockedBackend(),
        walletMaterial: walletMaterial,
        authMethod: WalletAuthMethod.biometric,
      );

      expect(operation.backendId, 'phone_secure_vault');
      expect(operation.address, walletMaterial.address);
      expect(operation.authMethod, WalletAuthMethod.biometric);
      expect(operation.signer, isA<LocalKeyMaterialTransactionSigner>());
    },
  );

  test('rejects signing authorization when backend is locked', () {
    const authorizer = WalletOperationAuthorizer();

    expect(
      () => authorizer.authorizeUnlockedLocalSigning(
        backend: _FakeLockedBackend(),
        walletMaterial: null,
        authMethod: WalletAuthMethod.pin,
      ),
      throwsA(isA<VaultFailure>()),
    );
  });
}

class _FakeUnlockedBackend implements KeyStorageBackend {
  @override
  String get backendId => 'phone_secure_vault';

  @override
  bool get isUnlocked => true;

  @override
  Future<void> clear() async {}

  @override
  Future<WalletMaterial> createWallet({required String pin}) {
    throw UnimplementedError();
  }

  @override
  Future<StoredWalletSummary?> getWalletSummary() async => null;

  @override
  Future<bool> hasWallet() async => false;

  @override
  Future<WalletMaterial> importWallet({
    required String mnemonic,
    required String pin,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<bool> isBiometricUnlockAvailable() async => false;

  @override
  Future<bool> isBiometricUnlockEnabled() async => false;

  @override
  void lock() {}

  @override
  Future<void> setBiometricUnlockEnabled({
    required bool enabled,
    required String pin,
  }) async {}

  @override
  Future<WalletMaterial> unlock({required String pin}) {
    throw UnimplementedError();
  }

  @override
  Future<WalletMaterial> unlockWithBiometrics() {
    throw UnimplementedError();
  }
}

class _FakeLockedBackend extends _FakeUnlockedBackend {
  @override
  bool get isUnlocked => false;
}
