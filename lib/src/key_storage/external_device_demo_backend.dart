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

class ExternalDeviceDemoRuntimeState {
  const ExternalDeviceDemoRuntimeState({
    required this.isAvailable,
    required this.hasLinkedWallet,
    required this.hasActiveSession,
    this.connectedAtUtc,
    this.lastError,
  });

  final bool isAvailable;
  final bool hasLinkedWallet;
  final bool hasActiveSession;
  final DateTime? connectedAtUtc;
  final String? lastError;
}

class ExternalDeviceDemoBackend implements ExternalDeviceKeyStorageBackend {
  ExternalDeviceDemoBackend({required SecureKeyValueStore store})
    : _store = PrefixedSecureKeyValueStore(
        store: store,
        prefix: 'external_device_demo.',
      ),
      _delegate = PhoneSecureVault(
        store: PrefixedSecureKeyValueStore(
          store: store,
          prefix: 'external_device_demo.',
        ),
        biometricAuth: const UnavailableBiometricAuthGateway(),
      );

  static const String _availabilityKey = 'runtime.device_available';
  static const String _connectedAtKey = 'runtime.connected_at_utc';
  static const String _lastErrorKey = 'runtime.last_error';

  final SecureKeyValueStore _store;
  final PhoneSecureVault _delegate;

  @override
  String get backendId => 'external_nfc_demo_device';

  @override
  bool get isUnlocked => _delegate.isUnlocked;

  @override
  Future<void> clear() async {
    await _delegate.clear();
    await _store.delete(_connectedAtKey);
    await _store.delete(_lastErrorKey);
    await _store.delete(_availabilityKey);
  }

  @override
  Future<WalletMaterial> createWallet({required String pin}) async {
    await _requireDeviceAvailable();
    final material = await _delegate.createWallet(pin: pin);
    await _clearSessionState();
    return material;
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
  }) async {
    await _requireDeviceAvailable();
    final material = await _delegate.importWallet(mnemonic: mnemonic, pin: pin);
    await _clearSessionState();
    return material;
  }

  @override
  Future<bool> isBiometricUnlockAvailable() async => false;

  @override
  Future<bool> isBiometricUnlockEnabled() async => false;

  @override
  Future<bool> isDeviceAvailable() async {
    final raw = await _store.read(_availabilityKey);
    if (raw == null) {
      return true;
    }
    return raw == 'true';
  }

  Future<ExternalDeviceDemoRuntimeState> loadRuntimeState() async {
    final available = await isDeviceAvailable();
    final connectedAtRaw = await _store.read(_connectedAtKey);
    final lastError = await _store.read(_lastErrorKey);
    return ExternalDeviceDemoRuntimeState(
      isAvailable: available,
      hasLinkedWallet: await hasWallet(),
      hasActiveSession: isUnlocked,
      connectedAtUtc: connectedAtRaw == null
          ? null
          : DateTime.tryParse(connectedAtRaw),
      lastError: lastError,
    );
  }

  Future<void> simulateDeviceUnavailable() async {
    _delegate.lock();
    await _store.write(_availabilityKey, 'false');
    await _store.delete(_connectedAtKey);
    await _store.write(
      _lastErrorKey,
      'Demo device is offline. Reconnect it before signing.',
    );
  }

  Future<void> reconnectDevice() async {
    await _store.write(_availabilityKey, 'true');
    await _store.delete(_lastErrorKey);
  }

  Future<void> disconnectSession() async {
    _delegate.lock();
    await _store.delete(_connectedAtKey);
    await _store.write(
      _lastErrorKey,
      'Device session ended. Re-enter the device PIN to continue.',
    );
  }

  @override
  void lock() {
    _delegate.lock();
    _store.delete(_connectedAtKey);
  }

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
  Future<WalletMaterial> unlock({required String pin}) async {
    await _requireDeviceAvailable();
    try {
      final material = await _delegate.unlock(pin: pin);
      await _store.write(
        _connectedAtKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      await _store.delete(_lastErrorKey);
      return material;
    } on VaultFailure {
      await _store.write(
        _lastErrorKey,
        'Device PIN was rejected by the demo external signer.',
      );
      rethrow;
    }
  }

  @override
  Future<WalletMaterial> unlockWithBiometrics() {
    throw const BiometricUnavailableFailure();
  }

  Future<void> _requireDeviceAvailable() async {
    if (!await isDeviceAvailable()) {
      throw const VaultFailure(
        'Demo device is offline. Reconnect it before using the external signer.',
      );
    }
  }

  Future<void> _clearSessionState() async {
    _delegate.lock();
    await _store.delete(_connectedAtKey);
    await _store.delete(_lastErrorKey);
  }
}
