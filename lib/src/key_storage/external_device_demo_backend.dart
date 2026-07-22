import 'dart:async';
import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:web3dart/web3dart.dart' show EthPrivateKey, sign;

import '../auth/biometric_auth.dart';
import 'custody_backend.dart';
import 'external_device_pkcs11.dart';
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
    this.session,
  });

  final bool isAvailable;
  final bool hasLinkedWallet;
  final bool hasActiveSession;
  final DateTime? connectedAtUtc;
  final String? lastError;
  final ExternalDevicePkcs11SessionSnapshot? session;
}

class ExternalDeviceDemoBackend
    implements ExternalDeviceKeyStorageBackend, WalletCustodyBackend {
  ExternalDeviceDemoBackend({
    required SecureKeyValueStore store,
    ExternalDevicePkcs11Adapter? pkcs11Adapter,
  }) : _store = PrefixedSecureKeyValueStore(
         store: store,
         prefix: 'external_device_demo.',
       ),
       _pkcs11Adapter =
           pkcs11Adapter ?? const DemoExternalDevicePkcs11Adapter(),
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
  static const String _sessionIdKey = 'runtime.session_id';
  static const String _sessionOperationCountKey =
      'runtime.session_operation_count';
  static const String _lastOperationKindKey = 'runtime.last_operation_kind';
  static const String _lastOperationMessageKey =
      'runtime.last_operation_message';
  static const String _lastOperationAtKey = 'runtime.last_operation_at_utc';

  final SecureKeyValueStore _store;
  final ExternalDevicePkcs11Adapter _pkcs11Adapter;
  final PhoneSecureVault _delegate;

  @override
  String get backendId => 'external_nfc_demo_device';

  @override
  bool get isUnlocked => _delegate.isUnlocked;

  @override
  Future<void> clear() async {
    await _delegate.clear();
    await _store.delete(_availabilityKey);
    await _store.delete(_connectedAtKey);
    await _store.delete(_lastErrorKey);
    await _clearPkcs11SessionMetadata();
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
    final session = await loadSessionSnapshot();

    return ExternalDeviceDemoRuntimeState(
      isAvailable: available,
      hasLinkedWallet: await hasWallet(),
      hasActiveSession: isUnlocked,
      connectedAtUtc: connectedAtRaw == null
          ? null
          : DateTime.tryParse(connectedAtRaw),
      lastError: lastError,
      session: session,
    );
  }

  @override
  Future<WalletAccountDescriptor> readAccountDescriptor({
    required String pin,
  }) async {
    final session = await openSigningSession(pin: pin);
    try {
      return session.account;
    } finally {
      await session.close();
    }
  }

  @override
  Future<WalletAccountPublicKey> readAccountPublicKey({
    required String pin,
  }) async {
    final material = await unlock(pin: pin);
    try {
      final seed = bip39.mnemonicToSeed(material.mnemonic);
      final master = bip32.BIP32.fromSeed(seed);
      final accountNode = master.derivePath("m/44'/60'/0'");
      return WalletAccountPublicKey(
        account: WalletAccountDescriptor(
          backendId: backendId,
          address: material.address,
          derivationPath: "m/44'/60'/0'/0/0",
        ),
        accountPath: "m/44'/60'/0'",
        accountDepth: accountNode.depth,
        compressedPublicKey: Uint8List.fromList(accountNode.publicKey),
        chainCode: Uint8List.fromList(accountNode.chainCode),
        sourceFingerprint: _asUint32(master.fingerprint),
        parentFingerprint: accountNode.parentFingerprint,
      );
    } finally {
      await _closeCustodySession();
    }
  }

  @override
  Future<CustodySigningSession> openSigningSession({
    required String pin,
  }) async {
    final material = await unlock(pin: pin);
    return _DemoCustodySigningSession(
      account: WalletAccountDescriptor(
        backendId: backendId,
        address: material.address,
        derivationPath: "m/44'/60'/0'/0/0",
      ),
      privateKey: EthPrivateKey.fromHex(material.privateKeyHex).privateKey,
      closeSession: _closeCustodySession,
    );
  }

  Future<ExternalDevicePkcs11SessionSnapshot?> loadSessionSnapshot() async {
    final sessionId = await _store.read(_sessionIdKey);
    final connectedAtRaw = await _store.read(_connectedAtKey);
    if (sessionId == null || connectedAtRaw == null) {
      return null;
    }

    final connectedAtUtc = DateTime.tryParse(connectedAtRaw);
    if (connectedAtUtc == null) {
      return null;
    }

    final operationCountRaw = await _store.read(_sessionOperationCountKey);
    final operationCount = int.tryParse(operationCountRaw ?? '') ?? 0;
    final lastOperationKindRaw = await _store.read(_lastOperationKindKey);
    final lastOperationKind = _parseCommandKind(lastOperationKindRaw);
    final lastMessage = await _store.read(_lastOperationMessageKey);
    final lastOperationAtRaw = await _store.read(_lastOperationAtKey);

    return ExternalDevicePkcs11SessionSnapshot(
      sessionId: sessionId,
      connectedAtUtc: connectedAtUtc,
      operationCount: operationCount,
      lastOperationKind: lastOperationKind,
      lastMessage: lastMessage,
      lastOperationAtUtc: lastOperationAtRaw == null
          ? null
          : DateTime.tryParse(lastOperationAtRaw),
    );
  }

  Future<ExternalDevicePkcs11Result> performPkcs11Operation(
    ExternalDevicePkcs11Operation operation,
  ) async {
    await _requireDeviceAvailable();
    if (!isUnlocked) {
      throw const VaultFailure(
        'No active device session. Connect the demo device first.',
      );
    }

    final summary = await getWalletSummary();
    final session = await loadSessionSnapshot();
    if (summary == null || session == null) {
      throw const VaultFailure(
        'Demo device session metadata is missing. Reconnect the device first.',
      );
    }

    final response = await _pkcs11Adapter.performOperation(
      session: session,
      operation: operation,
      publicAddress: summary.address,
    );

    await _store.write(
      _sessionOperationCountKey,
      (session.operationCount + 1).toString(),
    );
    await _store.write(_lastOperationKindKey, operation.kind.name);
    await _store.write(_lastOperationMessageKey, response.message);
    await _store.write(
      _lastOperationAtKey,
      response.respondedAtUtc.toIso8601String(),
    );
    await _store.delete(_lastErrorKey);

    return response;
  }

  Future<void> simulateDeviceUnavailable() async {
    _delegate.lock();
    await _store.write(_availabilityKey, 'false');
    await _store.delete(_connectedAtKey);
    await _clearPkcs11SessionMetadata();
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
    await _clearPkcs11SessionMetadata();
    await _store.write(
      _lastErrorKey,
      'Device session ended. Re-enter the device PIN to continue.',
    );
  }

  @override
  void lock() {
    _delegate.lock();
    unawaited(_store.delete(_connectedAtKey));
    unawaited(_clearPkcs11SessionMetadata());
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
      await _beginPkcs11Session();
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
    await _clearPkcs11SessionMetadata();
    await _store.delete(_lastErrorKey);
  }

  Future<void> _beginPkcs11Session() async {
    final connectedAt = DateTime.now().toUtc();
    await _store.write(_connectedAtKey, connectedAt.toIso8601String());
    await _store.write(
      _sessionIdKey,
      'demo-session-${connectedAt.microsecondsSinceEpoch}',
    );
    await _store.write(_sessionOperationCountKey, '0');
    await _store.delete(_lastOperationKindKey);
    await _store.delete(_lastOperationMessageKey);
    await _store.delete(_lastOperationAtKey);
  }

  Future<void> _clearPkcs11SessionMetadata() async {
    await _store.delete(_sessionIdKey);
    await _store.delete(_sessionOperationCountKey);
    await _store.delete(_lastOperationKindKey);
    await _store.delete(_lastOperationMessageKey);
    await _store.delete(_lastOperationAtKey);
  }

  Future<void> _closeCustodySession() async {
    _delegate.lock();
    await _store.delete(_connectedAtKey);
    await _clearPkcs11SessionMetadata();
  }

  int _asUint32(Uint8List fingerprint) =>
      fingerprint.buffer.asByteData().getUint32(0);

  ExternalDevicePkcs11OperationKind? _parseCommandKind(String? rawValue) {
    if (rawValue == null) {
      return null;
    }

    for (final kind in ExternalDevicePkcs11OperationKind.values) {
      if (kind.name == rawValue) {
        return kind;
      }
    }

    return null;
  }
}

class _DemoCustodySigningSession implements CustodySigningSession {
  _DemoCustodySigningSession({
    required this.account,
    required Uint8List privateKey,
    required Future<void> Function() closeSession,
  }) : _privateKey = Uint8List.fromList(privateKey),
       _closeSession = closeSession;

  @override
  final WalletAccountDescriptor account;
  final Uint8List _privateKey;
  final Future<void> Function() _closeSession;
  bool _closed = false;

  @override
  Future<RawEcdsaSignature> signDigest(Uint8List digest) async {
    if (_closed) {
      throw StateError('Demo custody session is closed.');
    }
    if (digest.length != 32) {
      throw ArgumentError('Expected a 32-byte digest.');
    }
    final signature = sign(digest, _privateKey);
    return RawEcdsaSignature(
      r: _uint256(signature.r),
      s: _uint256(signature.s),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _privateKey.fillRange(0, _privateKey.length, 0);
    await _closeSession();
  }

  Uint8List _uint256(BigInt value) {
    final out = Uint8List(32);
    var remaining = value;
    for (var i = 31; i >= 0; i--) {
      out[i] = (remaining & BigInt.from(0xff)).toInt();
      remaining >>= 8;
    }
    return out;
  }
}
