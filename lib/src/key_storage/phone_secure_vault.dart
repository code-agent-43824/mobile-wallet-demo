import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:web3dart/web3dart.dart';

import '../auth/pin_unlock_session.dart';
import 'key_storage_backend.dart';
import 'secure_key_value_store.dart';

class PhoneSecureVault implements KeyStorageBackend {
  PhoneSecureVault({
    required SecureKeyValueStore store,
    PinUnlockSession? session,
    Duration unlockTtl = const Duration(minutes: 5),
    Random? random,
  }) : _store = store,
       _session = session ?? PinUnlockSession(ttl: unlockTtl),
       _random = random ?? Random.secure();

  static const String storageKey = 'wallet.phone_secure_vault.v1';
  static const String derivationPath = "m/44'/60'/0'/0/0";
  static const int _pinSaltLength = 16;
  static const int _cipherNonceLength = 12;
  static const int _pinIterations = 120000;

  final SecureKeyValueStore _store;
  final PinUnlockSession _session;
  final Random _random;
  final Cipher _cipher = AesGcm.with256bits();
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

    final payload = await _readPayload();
    if (payload == null) {
      throw const WalletNotInitializedFailure();
    }

    try {
      final decryptedMnemonic = await _decryptMnemonic(
        payload: payload,
        pin: pin,
      );
      final material = _deriveWalletMaterial(
        mnemonic: decryptedMnemonic,
        derivationPath: payload.derivationPath,
      );

      if (material.address.toLowerCase() != payload.address.toLowerCase()) {
        throw const InvalidPinFailure();
      }

      return _cacheUnlockedMaterial(material);
    } catch (_) {
      lock();
      throw const InvalidPinFailure();
    }
  }

  @override
  Future<void> clear() async {
    await _store.delete(storageKey);
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
    final salt = _randomBytes(_pinSaltLength);
    final nonce = _randomBytes(_cipherNonceLength);
    final encryptedBox = await _cipher.encrypt(
      utf8.encode(material.mnemonic),
      secretKey: await _deriveEncryptionKey(
        pin: pin,
        salt: salt,
        iterations: _pinIterations,
      ),
      nonce: nonce,
    );

    final payload = _VaultPayload(
      schemaVersion: 1,
      backendId: backendId,
      address: material.address,
      createdAtUtc: DateTime.now().toUtc().toIso8601String(),
      derivationPath: derivationPath,
      pinSaltHex: hex.encode(salt),
      pinIterations: _pinIterations,
      cipherNonceHex: hex.encode(encryptedBox.nonce),
      cipherTextHex: hex.encode(encryptedBox.cipherText),
      macHex: hex.encode(encryptedBox.mac.bytes),
    );

    await _store.write(storageKey, jsonEncode(payload.toJson()));
    return _cacheUnlockedMaterial(material);
  }

  Future<_VaultPayload?> _readPayload() async {
    final raw = await _store.read(storageKey);
    if (raw == null) {
      return null;
    }

    return _VaultPayload.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<String> _decryptMnemonic({
    required _VaultPayload payload,
    required String pin,
  }) async {
    final secretKey = await _deriveEncryptionKey(
      pin: pin,
      salt: hex.decode(payload.pinSaltHex),
      iterations: payload.pinIterations,
    );

    final decryptedBytes = await _cipher.decrypt(
      SecretBox(
        hex.decode(payload.cipherTextHex),
        nonce: hex.decode(payload.cipherNonceHex),
        mac: Mac(hex.decode(payload.macHex)),
      ),
      secretKey: secretKey,
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
    required this.cipherNonceHex,
    required this.cipherTextHex,
    required this.macHex,
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
      cipherNonceHex: json['cipherNonceHex'] as String,
      cipherTextHex: json['cipherTextHex'] as String,
      macHex: json['macHex'] as String,
    );
  }

  final int schemaVersion;
  final String backendId;
  final String address;
  final String createdAtUtc;
  final String derivationPath;
  final String pinSaltHex;
  final int pinIterations;
  final String cipherNonceHex;
  final String cipherTextHex;
  final String macHex;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'backendId': backendId,
      'address': address,
      'createdAtUtc': createdAtUtc,
      'derivationPath': derivationPath,
      'pinSaltHex': pinSaltHex,
      'pinIterations': pinIterations,
      'cipherNonceHex': cipherNonceHex,
      'cipherTextHex': cipherTextHex,
      'macHex': macHex,
    };
  }
}
