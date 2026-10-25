import '../errors/app_error.dart';

class StoredWalletSummary {
  const StoredWalletSummary({
    required this.address,
    required this.backendId,
    required this.createdAtUtc,
  });

  final String address;
  final String backendId;
  final DateTime createdAtUtc;
}

class WalletMaterial {
  const WalletMaterial({
    required this.address,
    required this.mnemonic,
    required this.privateKeyHex,
  });

  final String address;
  final String mnemonic;
  final String privateKeyHex;
}

class VaultFailure implements Exception, CodedError {
  /// A failure whose text comes from outside the app (or is already localized
  /// by the caller); shown as is.
  const VaultFailure(String message)
    : _message = message,
      errorCode = null,
      errorArgs = const <String, Object>{};

  const VaultFailure.coded(
    AppErrorCode this.errorCode, [
    this.errorArgs = const <String, Object>{},
  ]) : _message = null;

  final String? _message;

  @override
  final AppErrorCode? errorCode;

  @override
  final Map<String, Object> errorArgs;

  @override
  String get message => _message ?? debugDescribeError(errorCode!, errorArgs);

  @override
  String toString() => 'VaultFailure: $message';
}

class WalletNotInitializedFailure extends VaultFailure {
  const WalletNotInitializedFailure()
    : super.coded(AppErrorCode.walletNotInitialized);
}

class InvalidPinFailure extends VaultFailure {
  const InvalidPinFailure() : super.coded(AppErrorCode.invalidPin);
}

class InvalidMnemonicFailure extends VaultFailure {
  const InvalidMnemonicFailure() : super.coded(AppErrorCode.invalidMnemonic);
}

class BiometricUnavailableFailure extends VaultFailure {
  const BiometricUnavailableFailure()
    : super.coded(AppErrorCode.biometricUnavailable);
}

class BiometricNotEnabledFailure extends VaultFailure {
  const BiometricNotEnabledFailure()
    : super.coded(AppErrorCode.biometricNotEnabled);
}

class BiometricCancelledFailure extends VaultFailure {
  const BiometricCancelledFailure()
    : super.coded(AppErrorCode.biometricCancelled);
}

class VaultLockedOutFailure extends VaultFailure {
  VaultLockedOutFailure(this.remaining)
    : super.coded(AppErrorCode.vaultLockedOut, <String, Object>{
        'remaining': remaining,
      });

  /// How long until the next unlock attempt is accepted.
  final Duration remaining;
}

class CorruptVaultPayloadFailure extends VaultFailure {
  const CorruptVaultPayloadFailure() : super.coded(AppErrorCode.vaultCorrupt);
}

class UnsupportedVaultSchemaFailure extends VaultFailure {
  const UnsupportedVaultSchemaFailure(this.schemaVersion)
    : super.coded(AppErrorCode.vaultSchemaUnsupported);

  final int schemaVersion;
}

/// Common read-only lifecycle exposed by every selectable custody backend.
///
/// A hardware backend implements this surface plus `WalletCustodyBackend`; it
/// deliberately does not implement the secret-exporting [KeyStorageBackend].
abstract interface class WalletBackend {
  String get backendId;
  bool get isUnlocked;

  Future<bool> hasWallet();
  Future<StoredWalletSummary?> getWalletSummary();
  Future<bool> isBiometricUnlockAvailable();
  Future<bool> isBiometricUnlockEnabled();
  void lock();
}

abstract interface class KeyStorageBackend implements WalletBackend {
  Future<WalletMaterial> createWallet({required String pin});
  Future<WalletMaterial> importWallet({
    required String mnemonic,
    required String pin,
  });
  Future<WalletMaterial> unlock({required String pin});
  Future<void> setBiometricUnlockEnabled({
    required bool enabled,
    required String pin,
  });
  Future<WalletMaterial> unlockWithBiometrics();
  Future<void> clear();
}
