import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:web3dart/web3dart.dart';

import '../auth/biometric_auth.dart';
import '../auth/pin_unlock_session.dart';
import 'biometric_secret_store.dart';
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
    Duration unlockLockout = const Duration(minutes: 1),
    DateTime Function()? now,
    int pbkdf2Iterations = _defaultPinIterations,
    Random? random,
  }) : _store = store,
       _biometricAuth = biometricAuth ?? defaultBiometricAuthGateway(),
       _session = session ?? PinUnlockSession(ttl: unlockTtl),
       _maxUnlockAttempts = maxUnlockAttempts,
       _unlockLockout = unlockLockout,
       _pinIterations = pbkdf2Iterations,
       _now = now ?? _defaultNow,
       _random = random ?? Random.secure() {
    _biometricSecretStore =
        biometricSecretStore ??
        GatedBiometricSecretStore(store: store, biometricAuth: _biometricAuth);
  }

  static DateTime _defaultNow() => DateTime.now().toUtc();

  static const String storageKey = 'wallet.phone_secure_vault.v1';
  static const String derivationPath = "m/44'/60'/0'/0/0";
  static const String _biometricSecretId = 'primary';
  static const int _pinSaltLength = 16;
  static const int _cipherNonceLength = 12;
  static const int _dekLength = 32;

  // The at-rest seed is encrypted under a random data-encryption key (DEK); the
  // DEK is wrapped by a PIN-derived key. The PIN itself is never persisted.
  //
  // PBKDF2-HMAC-SHA256 at the OWASP-recommended 600k iterations, paired with
  // the failed-attempt lockout below. The at-rest strength is still ultimately
  // bounded by PIN entropy. Injectable so tests can use a cheaper value.
  static const int _defaultPinIterations = 600000;

  final SecureKeyValueStore _store;
  final BiometricAuthGateway _biometricAuth;
  final PinUnlockSession _session;
  final int _maxUnlockAttempts;
  final Duration _unlockLockout;
  final int _pinIterations;
  final DateTime Function() _now;
  final Random _random;
  final Cipher _cipher = AesGcm.with256bits();
  late final BiometricSecretStore _biometricSecretStore;
  WalletMaterial? _cachedMaterial;

  @override
  String get backendId => 'phone_secure_vault';

  @override
  bool get isUnlocked => _session.isUnlocked && _cachedMaterial != null;

  @override
  Future<bool> hasWallet() async {
    final payload = await _store.read(storageKey);
    return payload != null;
  }

  @override
  Future<StoredWalletSummary?> getWalletSummary() async {
    final payload = await _readPayload();
    if (payload == null) {
      return null;
    }

    return StoredWalletSummary(
      address: payload.address,
      backendId: payload.backendId,
      createdAtUtc: DateTime.parse(payload.createdAtUtc),
    );
  }

  @override
  Future<WalletMaterial> createWallet({required String pin}) async {
    final mnemonic = bip39.generateMnemonic();
    return _persistMnemonic(mnemonic: mnemonic, pin: pin);
  }

  @override
  Future<WalletMaterial> importWallet({
    required String mnemonic,
    required String pin,
  }) async {
    final normalizedMnemonic = _normalizeMnemonic(mnemonic);
    if (!bip39.validateMnemonic(normalizedMnemonic)) {
      throw const InvalidMnemonicFailure();
    }

    return _persistMnemonic(mnemonic: normalizedMnemonic, pin: pin);
  }

  @override
  Future<WalletMaterial> unlock({required String pin}) async {
    if (isUnlocked) {
      return _cachedMaterial!;
    }

    final payload = await _requirePayload();
    _assertNotLockedOut(payload);

    try {
      final dek = await _unwrapDek(payload: payload, pin: pin);
      final mnemonic = await _decryptMnemonicWithDek(
        payload: payload,
        dek: dek,
      );
      final material = _deriveWalletMaterial(
        mnemonic: mnemonic,
        derivationPath: payload.derivationPath,
      );

      if (material.address.toLowerCase() != payload.address.toLowerCase()) {
        throw const InvalidPinFailure();
      }

      await _resetUnlockThrottle(payload);
      return _cacheUnlockedMaterial(material);
    } catch (_) {
      lock();
      await _registerFailedUnlock(payload);
      throw const InvalidPinFailure();
    }
  }

  BiometricAuthMode get biometricAuthMode => _biometricAuth.mode;

  @override
  Future<bool> isBiometricUnlockAvailable() {
    return _biometricAuth.isAvailable();
  }

  @override
  Future<bool> isBiometricUnlockEnabled() async {
    final payload = await _readPayload();
    return payload?.biometricEnabled ?? false;
  }

  @override
  Future<void> setBiometricUnlockEnabled({
    required bool enabled,
    required String pin,
  }) async {
    final payload = await _requirePayload();
    if (enabled) {
      if (!await isBiometricUnlockAvailable()) {
        throw const BiometricUnavailableFailure();
      }

      await _biometricAuth.authenticate(
        reason: 'Подтвердите биометрию для включения быстрого unlock.',
      );

      // Unwrap the DEK with the PIN, then hand it to the gated biometric store.
      // The PIN is used only transiently here and is never persisted.
      List<int> dek;
      try {
        dek = await _unwrapDek(payload: payload, pin: pin);
      } catch (_) {
        throw const InvalidPinFailure();
      }

      await _biometricSecretStore.store(id: _biometricSecretId, secret: dek);
      await _writePayload(payload.copyWith(biometricEnabled: true));
      return;
    }

    await _biometricSecretStore.delete(_biometricSecretId);
    await _writePayload(payload.copyWith(biometricEnabled: false));
  }

  @override
  Future<WalletMaterial> unlockWithBiometrics() async {
    if (isUnlocked) {
      return _cachedMaterial!;
    }

    final payload = await _requirePayload();
    if (!await isBiometricUnlockAvailable()) {
      throw const BiometricUnavailableFailure();
    }
    if (!payload.biometricEnabled) {
      throw const BiometricNotEnabledFailure();
    }

    // Releasing the DEK prompts for biometric authentication inside the store.
    final dek = await _biometricSecretStore.retrieve(
      id: _biometricSecretId,
      reason: 'Подтвердите биометрию для разблокировки кошелька.',
    );
    if (dek == null) {
      throw const BiometricNotEnabledFailure();
    }

    final mnemonic = await _decryptMnemonicWithDek(payload: payload, dek: dek);
    final material = _deriveWalletMaterial(
      mnemonic: mnemonic,
      derivationPath: payload.derivationPath,
    );
    return _cacheUnlockedMaterial(material);
  }

  @override
  Future<void> clear() async {
    await _store.delete(storageKey);
    await _biometricSecretStore.delete(_biometricSecretId);
    lock();
  }

  @override
  void lock() {
    _session.lock();
    _cachedMaterial = null;
  }

  Future<WalletMaterial> _persistMnemonic({
    required String mnemonic,
    required String pin,
  }) async {
    final material = _deriveWalletMaterial(
      mnemonic: mnemonic,
      derivationPath: derivationPath,
    );

    // 1. Encrypt the mnemonic under a fresh random DEK.
    final dek = _randomBytes(_dekLength);
    final mnemonicNonce = _randomBytes(_cipherNonceLength);
    final mnemonicBox = await _cipher.encrypt(
      utf8.encode(material.mnemonic),
      secretKey: SecretKey(dek),
      nonce: mnemonicNonce,
    );

    // 2. Wrap the DEK with a PIN-derived key (the PIN is never stored).
    final salt = _randomBytes(_pinSaltLength);
    final dekNonce = _randomBytes(_cipherNonceLength);
    final dekBox = await _cipher.encrypt(
      dek,
      secretKey: await _deriveEncryptionKey(
        pin: pin,
        salt: salt,
        iterations: _pinIterations,
      ),
      nonce: dekNonce,
    );

    final payload = _VaultPayload(
      schemaVersion: 3,
      backendId: backendId,
      address: material.address,
      createdAtUtc: DateTime.now().toUtc().toIso8601String(),
      derivationPath: derivationPath,
      pinSaltHex: hex.encode(salt),
      pinIterations: _pinIterations,
      mnemonicNonceHex: hex.encode(mnemonicBox.nonce),
      mnemonicCipherTextHex: hex.encode(mnemonicBox.cipherText),
      mnemonicMacHex: hex.encode(mnemonicBox.mac.bytes),
      dekNonceHex: hex.encode(dekBox.nonce),
      dekCipherTextHex: hex.encode(dekBox.cipherText),
      dekMacHex: hex.encode(dekBox.mac.bytes),
      biometricEnabled: false,
    );

    await _writePayload(payload);
    return _cacheUnlockedMaterial(material);
  }

  Future<_VaultPayload?> _readPayload() async {
    final raw = await _store.read(storageKey);
    if (raw == null) {
      return null;
    }

    return _VaultPayload.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<_VaultPayload> _requirePayload() async {
    final payload = await _readPayload();
    if (payload == null) {
      throw const WalletNotInitializedFailure();
    }
    return payload;
  }

  Future<void> _writePayload(_VaultPayload payload) async {
    await _store.write(storageKey, jsonEncode(payload.toJson()));
  }

  void _assertNotLockedOut(_VaultPayload payload) {
    final lockedUntilIso = payload.lockoutUntilUtcIso;
    if (lockedUntilIso == null) {
      return;
    }
    final lockedUntil = DateTime.tryParse(lockedUntilIso)?.toUtc();
    if (lockedUntil == null) {
      return;
    }
    final nowUtc = _now();
    if (nowUtc.isBefore(lockedUntil)) {
      final remainingSeconds = lockedUntil.difference(nowUtc).inSeconds + 1;
      throw VaultLockedOutFailure(
        'Слишком много неверных попыток. Повторите через $remainingSeconds с.',
      );
    }
  }

  Future<void> _registerFailedUnlock(_VaultPayload payload) async {
    final attempts = payload.failedUnlockAttempts + 1;
    if (attempts >= _maxUnlockAttempts) {
      await _writePayload(
        payload.copyWith(
          failedUnlockAttempts: 0,
          lockoutUntilUtcIso: _now().add(_unlockLockout).toIso8601String(),
        ),
      );
    } else {
      await _writePayload(payload.copyWith(failedUnlockAttempts: attempts));
    }
  }

  Future<void> _resetUnlockThrottle(_VaultPayload payload) async {
    if (payload.failedUnlockAttempts == 0 &&
        payload.lockoutUntilUtcIso == null) {
      return;
    }
    await _writePayload(
      payload.copyWith(failedUnlockAttempts: 0, clearLockout: true),
    );
  }

  Future<List<int>> _unwrapDek({
    required _VaultPayload payload,
    required String pin,
  }) async {
    final secretKey = await _deriveEncryptionKey(
      pin: pin,
      salt: hex.decode(payload.pinSaltHex),
      iterations: payload.pinIterations,
    );

    return _cipher.decrypt(
      SecretBox(
        hex.decode(payload.dekCipherTextHex),
        nonce: hex.decode(payload.dekNonceHex),
        mac: Mac(hex.decode(payload.dekMacHex)),
      ),
      secretKey: secretKey,
    );
  }

  Future<String> _decryptMnemonicWithDek({
    required _VaultPayload payload,
    required List<int> dek,
  }) async {
    final decryptedBytes = await _cipher.decrypt(
      SecretBox(
        hex.decode(payload.mnemonicCipherTextHex),
        nonce: hex.decode(payload.mnemonicNonceHex),
        mac: Mac(hex.decode(payload.mnemonicMacHex)),
      ),
      secretKey: SecretKey(dek),
    );

    final mnemonic = utf8.decode(decryptedBytes);
    if (!bip39.validateMnemonic(mnemonic)) {
      throw const InvalidPinFailure();
    }

    return mnemonic;
  }

  Future<SecretKey> _deriveEncryptionKey({
    required String pin,
    required List<int> salt,
    required int iterations,
  }) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );

    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
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
      address: credentials.address.hexEip55,
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

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }
}

class _VaultPayload {
  const _VaultPayload({
    required this.schemaVersion,
    required this.backendId,
    required this.address,
    required this.createdAtUtc,
    required this.derivationPath,
    required this.pinSaltHex,
    required this.pinIterations,
    required this.mnemonicNonceHex,
    required this.mnemonicCipherTextHex,
    required this.mnemonicMacHex,
    required this.dekNonceHex,
    required this.dekCipherTextHex,
    required this.dekMacHex,
    required this.biometricEnabled,
    this.failedUnlockAttempts = 0,
    this.lockoutUntilUtcIso,
  });

  factory _VaultPayload.fromJson(Map<String, dynamic> json) {
    return _VaultPayload(
      schemaVersion: json['schemaVersion'] as int,
      backendId: json['backendId'] as String,
      address: json['address'] as String,
      createdAtUtc: json['createdAtUtc'] as String,
      derivationPath: json['derivationPath'] as String,
      pinSaltHex: json['pinSaltHex'] as String,
      pinIterations: json['pinIterations'] as int,
      mnemonicNonceHex: json['mnemonicNonceHex'] as String,
      mnemonicCipherTextHex: json['mnemonicCipherTextHex'] as String,
      mnemonicMacHex: json['mnemonicMacHex'] as String,
      dekNonceHex: json['dekNonceHex'] as String,
      dekCipherTextHex: json['dekCipherTextHex'] as String,
      dekMacHex: json['dekMacHex'] as String,
      biometricEnabled: json['biometricEnabled'] as bool? ?? false,
      failedUnlockAttempts: json['failedUnlockAttempts'] as int? ?? 0,
      lockoutUntilUtcIso: json['lockoutUntilUtcIso'] as String?,
    );
  }

  final int schemaVersion;
  final String backendId;
  final String address;
  final String createdAtUtc;
  final String derivationPath;
  final String pinSaltHex;
  final int pinIterations;
  final String mnemonicNonceHex;
  final String mnemonicCipherTextHex;
  final String mnemonicMacHex;
  final String dekNonceHex;
  final String dekCipherTextHex;
  final String dekMacHex;
  final bool biometricEnabled;
  final int failedUnlockAttempts;
  final String? lockoutUntilUtcIso;

  _VaultPayload copyWith({
    bool? biometricEnabled,
    int? failedUnlockAttempts,
    String? lockoutUntilUtcIso,
    bool clearLockout = false,
  }) {
    return _VaultPayload(
      schemaVersion: schemaVersion,
      backendId: backendId,
      address: address,
      createdAtUtc: createdAtUtc,
      derivationPath: derivationPath,
      pinSaltHex: pinSaltHex,
      pinIterations: pinIterations,
      mnemonicNonceHex: mnemonicNonceHex,
      mnemonicCipherTextHex: mnemonicCipherTextHex,
      mnemonicMacHex: mnemonicMacHex,
      dekNonceHex: dekNonceHex,
      dekCipherTextHex: dekCipherTextHex,
      dekMacHex: dekMacHex,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      failedUnlockAttempts: failedUnlockAttempts ?? this.failedUnlockAttempts,
      lockoutUntilUtcIso: clearLockout
          ? null
          : (lockoutUntilUtcIso ?? this.lockoutUntilUtcIso),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'backendId': backendId,
      'address': address,
      'createdAtUtc': createdAtUtc,
      'derivationPath': derivationPath,
      'pinSaltHex': pinSaltHex,
      'pinIterations': pinIterations,
      'mnemonicNonceHex': mnemonicNonceHex,
      'mnemonicCipherTextHex': mnemonicCipherTextHex,
      'mnemonicMacHex': mnemonicMacHex,
      'dekNonceHex': dekNonceHex,
      'dekCipherTextHex': dekCipherTextHex,
      'dekMacHex': dekMacHex,
      'biometricEnabled': biometricEnabled,
      'failedUnlockAttempts': failedUnlockAttempts,
      'lockoutUntilUtcIso': lockoutUntilUtcIso,
    };
  }
}
