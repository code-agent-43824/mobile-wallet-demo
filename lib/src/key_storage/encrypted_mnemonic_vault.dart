import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';

import '../auth/biometric_auth.dart';
import '../errors/app_error.dart';
import 'biometric_secret_store.dart';
import 'key_storage_backend.dart';
import 'secure_key_value_store.dart';

/// PIN and biometric protection shared by the phone's mnemonic vaults.
class EncryptedMnemonicVault {
  EncryptedMnemonicVault({
    required SecureKeyValueStore store,
    required this.storageKey,
    required String backendId,
    required String biometricSecretId,
    BiometricAuthGateway? biometricAuth,
    BiometricSecretStore? biometricSecretStore,
    BiometricPromptText? biometricPromptText,
    int maxUnlockAttempts = 5,
    Duration unlockLockout = const Duration(minutes: 5),
    DateTime Function()? now,
    int pbkdf2Iterations = defaultPinIterations,
    Random? random,
  }) : _store = store,
       _backendId = backendId,
       _biometricSecretId = biometricSecretId,
       _biometricAuth = biometricAuth ?? defaultBiometricAuthGateway(),
       _biometricPromptText = biometricPromptText ?? defaultBiometricPromptText,
       _maxUnlockAttempts = maxUnlockAttempts,
       _unlockLockout = unlockLockout,
       _now = now ?? DateTime.now,
       _pinIterations = debugIterationsOverride ?? pbkdf2Iterations,
       _random = random ?? Random.secure() {
    _biometricSecretStore =
        biometricSecretStore ??
        GatedBiometricSecretStore(store: store, biometricAuth: _biometricAuth);
  }

  static const int _pinSaltLength = 16;
  static const int _cipherNonceLength = 12;
  static const int _dekLength = 32;
  static const int _currentSchemaVersion = 3;

  // PBKDF2-HMAC-SHA256 wraps a random, per-wallet AES-GCM data key. The PIN
  // remains transient. The at-rest strength is bounded by the PIN entropy.
  static const int defaultPinIterations = 600000;
  static int? debugIterationsOverride;

  final String storageKey;
  final String _backendId;
  final String _biometricSecretId;
  final SecureKeyValueStore _store;
  final BiometricAuthGateway _biometricAuth;
  final BiometricPromptText _biometricPromptText;
  final int _maxUnlockAttempts;
  final Duration _unlockLockout;
  final DateTime Function() _now;
  final int _pinIterations;
  final Random _random;
  final Cipher _cipher = AesGcm.with256bits();
  late final BiometricSecretStore _biometricSecretStore;
  Future<void> _pending = Future<void>.value();

  BiometricAuthMode get biometricAuthMode => _biometricAuth.mode;
  Future<bool> hasWallet() async => await _store.read(storageKey) != null;
  Future<bool> isBiometricUnlockAvailable() => _biometricAuth.isAvailable();
  Future<bool> isBiometricUnlockEnabled() async =>
      (await read())?.biometricEnabled ?? false;

  Future<void> create({
    required String mnemonic,
    required String pin,
    required String address,
    required String derivationPath,
    String? publicKeyHex,
  }) => _serialize(() async {
    if (await hasWallet()) {
      throw const VaultFailure.coded(AppErrorCode.walletAlreadyExists);
    }
    final dek = _randomBytes(_dekLength);
    final phrase = Uint8List.fromList(utf8.encode(mnemonic));
    final dataKey = SecretKey(dek);
    try {
      final mnemonicBox = await _cipher.encrypt(
        phrase,
        secretKey: dataKey,
        nonce: _randomBytes(_cipherNonceLength),
      );
      final salt = _randomBytes(_pinSaltLength);
      final pinKey = await _deriveEncryptionKey(
        pin: pin,
        salt: salt,
        iterations: _pinIterations,
      );
      final SecretBox dekBox;
      try {
        dekBox = await _cipher.encrypt(
          dek,
          secretKey: pinKey,
          nonce: _randomBytes(_cipherNonceLength),
        );
      } finally {
        pinKey.destroy();
      }

      await _writePayload(
        EncryptedMnemonicRecord(
          schemaVersion: _currentSchemaVersion,
          backendId: _backendId,
          address: address,
          publicKeyHex: publicKeyHex,
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
        ),
      );
    } finally {
      dataKey.destroy();
      dek.fillRange(0, dek.length, 0);
      phrase.fillRange(0, phrase.length, 0);
    }
  });

  Future<T> withPin<T>({
    required String pin,
    required FutureOr<T> Function(String, EncryptedMnemonicRecord) use,
  }) => _serialize(() async {
    final payload = await _requirePayload();
    _assertNotLockedOut(payload);
    final String mnemonic;
    try {
      final dek = await _unwrapDek(payload: payload, pin: pin);
      try {
        mnemonic = await _decryptMnemonicWithDek(payload: payload, dek: dek);
      } finally {
        dek.fillRange(0, dek.length, 0);
      }
    } on SecretBoxAuthenticationError {
      await _registerFailedUnlock(payload);
      throw const InvalidPinFailure();
    }
    final result = await use(mnemonic, payload);
    await _resetUnlockThrottle(payload);
    return result;
  });

  Future<T> withBiometrics<T>(
    FutureOr<T> Function(String, EncryptedMnemonicRecord) use,
  ) => _serialize(() async {
    final payload = await _requirePayload();
    if (!await isBiometricUnlockAvailable()) {
      throw const BiometricUnavailableFailure();
    }
    if (!payload.biometricEnabled) {
      throw const BiometricNotEnabledFailure();
    }
    final dek = await _biometricSecretStore.retrieve(
      id: _biometricSecretId,
      reason: _biometricPromptText(BiometricPrompt.unlockWallet),
    );
    if (dek == null) {
      throw const BiometricNotEnabledFailure();
    }
    final String mnemonic;
    try {
      mnemonic = await _decryptMnemonicWithDek(payload: payload, dek: dek);
    } finally {
      dek.fillRange(0, dek.length, 0);
    }
    return use(mnemonic, payload);
  });

  Future<void> setBiometricUnlockEnabled({
    required bool enabled,
    required String pin,
  }) => _serialize(() async {
    final payload = await _requirePayload();
    if (enabled) {
      _assertNotLockedOut(payload);
      if (!await isBiometricUnlockAvailable()) {
        throw const BiometricUnavailableFailure();
      }
      await _biometricAuth.authenticate(
        reason: _biometricPromptText(BiometricPrompt.enableQuickUnlock),
      );
      final List<int> dek;
      try {
        dek = await _unwrapDek(payload: payload, pin: pin);
      } on SecretBoxAuthenticationError {
        await _registerFailedUnlock(payload);
        throw const InvalidPinFailure();
      }
      try {
        await _biometricSecretStore.store(id: _biometricSecretId, secret: dek);
        await _writePayload(
          payload.copyWith(
            biometricEnabled: true,
            failedUnlockAttempts: 0,
            clearLockout: true,
          ),
        );
      } finally {
        dek.fillRange(0, dek.length, 0);
      }
    } else {
      await _biometricSecretStore.delete(_biometricSecretId);
      await _writePayload(payload.copyWith(biometricEnabled: false));
    }
  });

  Future<void> clear() => _serialize(() async {
    await _biometricSecretStore.delete(_biometricSecretId);
    await _store.delete(storageKey);
  });

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<EncryptedMnemonicRecord?> read() async {
    final raw = await _store.read(storageKey);
    if (raw == null) {
      return null;
    }

    final Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) {
        throw const CorruptVaultPayloadFailure();
      }
      decoded = parsed;
    } on VaultFailure {
      rethrow;
    } catch (_) {
      throw const CorruptVaultPayloadFailure();
    }

    final schemaVersion = decoded['schemaVersion'];
    if (schemaVersion is! int) {
      throw const CorruptVaultPayloadFailure();
    }
    if (schemaVersion != _currentSchemaVersion) {
      throw UnsupportedVaultSchemaFailure(schemaVersion);
    }

    try {
      return EncryptedMnemonicRecord.fromJson(decoded);
    } catch (_) {
      throw const CorruptVaultPayloadFailure();
    }
  }

  Future<EncryptedMnemonicRecord> _requirePayload() async {
    final payload = await read();
    if (payload == null) {
      throw const WalletNotInitializedFailure();
    }
    return payload;
  }

  Future<void> _writePayload(EncryptedMnemonicRecord payload) async {
    await _store.write(storageKey, jsonEncode(payload.toJson()));
  }

  void _assertNotLockedOut(EncryptedMnemonicRecord payload) {
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
      throw VaultLockedOutFailure(lockedUntil.difference(nowUtc));
    }
  }

  Future<void> _registerFailedUnlock(EncryptedMnemonicRecord payload) async {
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

  Future<void> _resetUnlockThrottle(EncryptedMnemonicRecord payload) async {
    if (payload.failedUnlockAttempts == 0 &&
        payload.lockoutUntilUtcIso == null) {
      return;
    }
    await _writePayload(
      payload.copyWith(failedUnlockAttempts: 0, clearLockout: true),
    );
  }

  Future<List<int>> _unwrapDek({
    required EncryptedMnemonicRecord payload,
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
    required EncryptedMnemonicRecord payload,
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

    try {
      return utf8.decode(decryptedBytes);
    } finally {
      decryptedBytes.fillRange(0, decryptedBytes.length, 0);
    }
  }

  Future<SecretKey> _deriveEncryptionKey({
    required String pin,
    required List<int> salt,
    required int iterations,
  }) async {
    Future<List<int>> derive() async {
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      );
      final key = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(pin)),
        nonce: salt,
      );
      return key.extractBytes();
    }

    // PBKDF2 at the configured (600k) iterations is CPU-heavy and would block
    // the UI isolate, freezing create/unlock for seconds. Offload it to a
    // background isolate so the UI stays responsive (the progress overlay
    // animates). It's pure computation with sendable args/result and no platform
    // channels, so it's isolate-safe. In tests ([debugIterationsOverride] set)
    // run inline instead: the count is tiny, and an isolate's spawn latency
    // would make `pumpAndSettle` time out against the overlay's spinner.
    final keyBytes = debugIterationsOverride != null
        ? await derive()
        : await Isolate.run(derive);
    return SecretKey(keyBytes);
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }
}

class EncryptedMnemonicRecord {
  const EncryptedMnemonicRecord({
    required this.schemaVersion,
    required this.backendId,
    required this.address,
    this.publicKeyHex,
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

  factory EncryptedMnemonicRecord.fromJson(Map<String, dynamic> json) {
    return EncryptedMnemonicRecord(
      schemaVersion: json['schemaVersion'] as int,
      backendId: json['backendId'] as String,
      address: json['address'] as String,
      publicKeyHex: json['publicKeyHex'] as String?,
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
  final String? publicKeyHex;
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

  EncryptedMnemonicRecord copyWith({
    bool? biometricEnabled,
    int? failedUnlockAttempts,
    String? lockoutUntilUtcIso,
    bool clearLockout = false,
  }) {
    return EncryptedMnemonicRecord(
      schemaVersion: schemaVersion,
      backendId: backendId,
      address: address,
      publicKeyHex: publicKeyHex,
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
      if (publicKeyHex != null) 'publicKeyHex': publicKeyHex,
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
