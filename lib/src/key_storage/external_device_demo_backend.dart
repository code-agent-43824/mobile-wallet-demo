import '../auth/biometric_auth.dart';
import 'key_storage_backend.dart';
import 'phone_secure_vault.dart';
import 'secure_key_value_store.dart';

class PrefixedSecureKeyValueStore implements SecureKeyValueStore {
  PrefixedSecureKeyValueStore({
    required SecureKeyValueStore store,
    required String prefix,
  }) : _store = store,
       _prefix = prefix;

  final SecureKeyValueStore _store;
  final String _prefix;

  String _withPrefix(String key) => '$_prefix$key';

  @override
  Future<String?> read(String key) => _store.read(_withPrefix(key));

  @override
  Future<void> write(String key, String value) {
    return _store.write(_withPrefix(key), value);
  }

  @override
  Future<void> delete(String key) => _store.delete(_withPrefix(key));
}

class ExternalDeviceDemoBackend implements ExternalDeviceKeyStorageBackend {
  ExternalDeviceDemoBackend({required SecureKeyValueStore store})
    : _delegate = PhoneSecureVault(
        store: PrefixedSecureKeyValueStore(
          store: store,
          prefix: 'external_device_demo.',
        ),
        biometricAuth: const UnavailableBiometricAuthGateway(),
      );

  final PhoneSecureVault _delegate;

  @override
  String get backendId => 'external_nfc_demo_device';

  @override
  bool get isUnlocked => _delegate.isUnlocked;

  @override
  Future<void> clear() => _delegate.clear();

  @override
  Future<WalletMaterial> createWallet({required String pin}) {
    return _delegate.createWallet(pin: pin);
  }

  @override
  Future<StoredWalletSummary?> getWalletSummary() async {
    final summary = await _delegate.getWalletSummary();
    if (summary == null) {
      return null;
    }

    return StoredWalletSummary(
      address: summary.address,
      backendId: backendId,
      createdAtUtc: summary.createdAtUtc,
    );
  }

  @override
  Future<bool> hasWallet() => _delegate.hasWallet();

  @override
  Future<WalletMaterial> importWallet({
    required String mnemonic,
    required String pin,
  }) {
    return _delegate.importWallet(mnemonic: mnemonic, pin: pin);
  }

  @override
  Future<bool> isBiometricUnlockAvailable() async => false;

  @override
  Future<bool> isBiometricUnlockEnabled() async => false;

  @override
  Future<bool> isDeviceAvailable() async => true;

  @override
  void lock() => _delegate.lock();

  @override
  Future<void> setBiometricUnlockEnabled({
    required bool enabled,
    required String pin,
  }) async {
    if (enabled) {
      throw const BiometricUnavailableFailure();
    }
  }

  @override
  Future<WalletMaterial> unlock({required String pin}) {
    return _delegate.unlock(pin: pin);
  }

  @override
  Future<WalletMaterial> unlockWithBiometrics() {
    throw const BiometricUnavailableFailure();
  }
}
