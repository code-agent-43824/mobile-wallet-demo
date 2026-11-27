import 'dart:math';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:convert/convert.dart';
import 'package:web3dart/web3dart.dart';

import '../auth/biometric_auth.dart';
import '../auth/pin_unlock_session.dart';
import '../errors/app_error.dart';
import 'biometric_secret_store.dart';
import 'encrypted_mnemonic_vault.dart';
import 'key_storage_backend.dart';
import 'secure_key_value_store.dart';

class PhoneSecureVault implements KeyStorageBackend {
  PhoneSecureVault({
    required SecureKeyValueStore store,
    BiometricAuthGateway? biometricAuth,
    BiometricSecretStore? biometricSecretStore,
    PinUnlockSession? session,
    Duration unlockTtl = const Duration(minutes: 5),
    int maxUnlockAttempts = 5,
    Duration unlockLockout = const Duration(minutes: 5),
    DateTime Function()? now,
    int pbkdf2Iterations = EncryptedMnemonicVault.defaultPinIterations,
    Random? random,
    BiometricPromptText? biometricPromptText,
  }) : _session = session ?? PinUnlockSession(ttl: unlockTtl),
       _vault = EncryptedMnemonicVault(
         store: store,
         storageKey: storageKey,
         backendId: _backendId,
         biometricSecretId: 'primary',
         biometricAuth: biometricAuth,
         biometricSecretStore: biometricSecretStore,
         biometricPromptText: biometricPromptText,
         maxUnlockAttempts: maxUnlockAttempts,
         unlockLockout: unlockLockout,
         now: now,
         pbkdf2Iterations: pbkdf2Iterations,
         random: random,
       );

  static const String storageKey = 'wallet.phone_secure_vault.v1';
  static const String derivationPath = "m/44'/60'/0'/0/0";
  static const String _backendId = 'phone_secure_vault';

  /// Used by widget tests to keep PIN derivation inline and fast.
  static int? get debugIterationsOverride =>
      EncryptedMnemonicVault.debugIterationsOverride;
  static set debugIterationsOverride(int? value) =>
      EncryptedMnemonicVault.debugIterationsOverride = value;

  final EncryptedMnemonicVault _vault;
  final PinUnlockSession _session;
  WalletMaterial? _cachedMaterial;

  @override
  String get backendId => _backendId;

  @override
  bool get isUnlocked => _session.isUnlocked && _cachedMaterial != null;

  @override
  Future<bool> hasWallet() => _vault.hasWallet();

  @override
  Future<StoredWalletSummary?> getWalletSummary() async {
    final payload = await _vault.read();
    if (payload == null) return null;
    return StoredWalletSummary(
      address: payload.address,
      backendId: payload.backendId,
      createdAtUtc: DateTime.parse(payload.createdAtUtc),
    );
  }

  @override
  Future<WalletMaterial> createWallet({required String pin}) =>
      _persistMnemonic(mnemonic: bip39.generateMnemonic(), pin: pin);

  @override
  Future<WalletMaterial> importWallet({
    required String mnemonic,
    required String pin,
  }) async {
    if (await hasWallet()) {
      throw const VaultFailure.coded(AppErrorCode.walletAlreadyExists);
    }
    final normalized = _normalizeMnemonic(mnemonic);
    if (!bip39.validateMnemonic(normalized)) {
      throw const InvalidMnemonicFailure();
    }
    return _persistMnemonic(mnemonic: normalized, pin: pin);
  }

  @override
  Future<WalletMaterial> unlock({required String pin}) async {
    if (isUnlocked) return _cachedMaterial!;
    try {
      final material = await _vault.withPin(pin: pin, use: _openMaterial);
      return _cacheUnlockedMaterial(material);
    } catch (_) {
      lock();
      rethrow;
    }
  }

  BiometricAuthMode get biometricAuthMode => _vault.biometricAuthMode;

  @override
  Future<bool> isBiometricUnlockAvailable() =>
      _vault.isBiometricUnlockAvailable();

  @override
  Future<bool> isBiometricUnlockEnabled() => _vault.isBiometricUnlockEnabled();

  @override
  Future<void> setBiometricUnlockEnabled({
    required bool enabled,
    required String pin,
  }) => _vault.setBiometricUnlockEnabled(enabled: enabled, pin: pin);

  @override
  Future<WalletMaterial> unlockWithBiometrics() async {
    if (isUnlocked) return _cachedMaterial!;
    final material = await _vault.withBiometrics(_openMaterial);
    return _cacheUnlockedMaterial(material);
  }

  @override
  Future<void> clear() async {
    lock();
    await _vault.clear();
  }

  @override
  void lock() {
    _session.lock();
    _cachedMaterial = null;
  }

  WalletMaterial _openMaterial(
    String mnemonic,
    EncryptedMnemonicRecord record,
  ) {
    if (!bip39.validateMnemonic(mnemonic)) {
      throw const InvalidPinFailure();
    }
    final material = _deriveWalletMaterial(
      mnemonic: mnemonic,
      derivationPath: record.derivationPath,
    );
    if (material.address.toLowerCase() != record.address.toLowerCase()) {
      throw const InvalidPinFailure();
    }
    return material;
  }

  Future<WalletMaterial> _persistMnemonic({
    required String mnemonic,
    required String pin,
  }) async {
    final material = _deriveWalletMaterial(
      mnemonic: mnemonic,
      derivationPath: derivationPath,
    );
    await _vault.create(
      mnemonic: mnemonic,
      pin: pin,
      address: material.address,
      derivationPath: derivationPath,
    );
    return _cacheUnlockedMaterial(material);
  }

  WalletMaterial _deriveWalletMaterial({
    required String mnemonic,
    required String derivationPath,
  }) {
    final seed = bip39.mnemonicToSeed(mnemonic);
    final node = bip32.BIP32.fromSeed(seed).derivePath(derivationPath);
    final privateKeyBytes = node.privateKey;
    if (privateKeyBytes == null || privateKeyBytes.length != 32) {
      throw const VaultFailure('Failed to derive a valid EVM private key.');
    }

    final privateKeyHex = hex.encode(privateKeyBytes);
    final credentials = EthPrivateKey.fromHex(privateKeyHex);

    return WalletMaterial(
      address: credentials.address.eip55With0x,
      mnemonic: mnemonic,
      privateKeyHex: privateKeyHex,
    );
  }

  WalletMaterial _cacheUnlockedMaterial(WalletMaterial material) {
    _cachedMaterial = material;
    _session.unlock();
    return material;
  }

  String _normalizeMnemonic(String mnemonic) {
    return mnemonic
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .join(' ');
  }
}
