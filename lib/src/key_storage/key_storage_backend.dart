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

class VaultFailure implements Exception {
  const VaultFailure(this.message);

  final String message;

  @override
  String toString() => 'VaultFailure: $message';
}

class WalletNotInitializedFailure extends VaultFailure {
  const WalletNotInitializedFailure()
    : super('Wallet vault is not initialized yet.');
}

class InvalidPinFailure extends VaultFailure {
  const InvalidPinFailure() : super('Invalid PIN or corrupted wallet payload.');
}

class InvalidMnemonicFailure extends VaultFailure {
  const InvalidMnemonicFailure()
    : super('Seed phrase is invalid or unsupported.');
}

abstract interface class KeyStorageBackend {
  String get backendId;
  bool get isUnlocked;

  Future<bool> hasWallet();
  Future<StoredWalletSummary?> getWalletSummary();
  Future<WalletMaterial> createWallet({required String pin});
  Future<WalletMaterial> importWallet({
    required String mnemonic,
    required String pin,
  });
  Future<WalletMaterial> unlock({required String pin});
  Future<void> clear();
  void lock();
}

abstract interface class ExternalDeviceKeyStorageBackend
    implements KeyStorageBackend {
  Future<bool> isDeviceAvailable();
}
