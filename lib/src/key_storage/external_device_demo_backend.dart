import 'dart:async';

import '../auth/biometric_auth.dart';
import 'external_device_protocol.dart';
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
  final ExternalDeviceSessionSnapshot? session;
}

class ExternalDeviceDemoBackend implements ExternalDeviceKeyStorageBackend {
  ExternalDeviceDemoBackend({
    required SecureKeyValueStore store,
    ExternalDeviceProtocolAdapter? protocolAdapter,
  }) : _store = PrefixedSecureKeyValueStore(
         store: store,
         prefix: 'external_device_demo.',
       ),
       _protocolAdapter =
           protocolAdapter ?? const DemoExternalDeviceProtocolAdapter(),
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
  static const String _sessionCommandCountKey = 'runtime.session_command_count';
  static const String _lastCommandKindKey = 'runtime.last_command_kind';
  static const String _lastCommandMessageKey = 'runtime.last_command_message';
  static const String _lastCommandAtKey = 'runtime.last_command_at_utc';

  final SecureKeyValueStore _store;
  final ExternalDeviceProtocolAdapter _protocolAdapter;
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
    await _clearProtocolSessionMetadata();
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

  Future<ExternalDeviceSessionSnapshot?> loadSessionSnapshot() async {
    final sessionId = await _store.read(_sessionIdKey);
    final connectedAtRaw = await _store.read(_connectedAtKey);
    if (sessionId == null || connectedAtRaw == null) {
      return null;
    }

    final connectedAtUtc = DateTime.tryParse(connectedAtRaw);
    if (connectedAtUtc == null) {
      return null;
    }

    final commandCountRaw = await _store.read(_sessionCommandCountKey);
    final commandCount = int.tryParse(commandCountRaw ?? '') ?? 0;
    final lastCommandKindRaw = await _store.read(_lastCommandKindKey);
    final lastCommandKind = _parseCommandKind(lastCommandKindRaw);
    final lastMessage = await _store.read(_lastCommandMessageKey);
    final lastCommandAtRaw = await _store.read(_lastCommandAtKey);

    return ExternalDeviceSessionSnapshot(
      sessionId: sessionId,
      connectedAtUtc: connectedAtUtc,
      commandCount: commandCount,
      lastCommandKind: lastCommandKind,
      lastMessage: lastMessage,
      lastCommandAtUtc: lastCommandAtRaw == null
          ? null
          : DateTime.tryParse(lastCommandAtRaw),
    );
  }

  Future<ExternalDeviceResponse> sendProtocolCommand(
    ExternalDeviceCommand command,
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

    final response = await _protocolAdapter.sendCommand(
      session: session,
      command: command,
      publicAddress: summary.address,
    );

    await _store.write(
      _sessionCommandCountKey,
      (session.commandCount + 1).toString(),
    );
    await _store.write(_lastCommandKindKey, command.kind.name);
    await _store.write(_lastCommandMessageKey, response.message);
    await _store.write(
      _lastCommandAtKey,
      response.respondedAtUtc.toIso8601String(),
    );
    await _store.delete(_lastErrorKey);

    return response;
  }

  Future<void> simulateDeviceUnavailable() async {
    _delegate.lock();
    await _store.write(_availabilityKey, 'false');
    await _store.delete(_connectedAtKey);
    await _clearProtocolSessionMetadata();
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
    await _clearProtocolSessionMetadata();
    await _store.write(
      _lastErrorKey,
      'Device session ended. Re-enter the device PIN to continue.',
    );
  }

  @override
  void lock() {
    _delegate.lock();
    unawaited(_store.delete(_connectedAtKey));
    unawaited(_clearProtocolSessionMetadata());
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
      await _beginProtocolSession();
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
    await _clearProtocolSessionMetadata();
    await _store.delete(_lastErrorKey);
  }

  Future<void> _beginProtocolSession() async {
    final connectedAt = DateTime.now().toUtc();
    await _store.write(_connectedAtKey, connectedAt.toIso8601String());
    await _store.write(
      _sessionIdKey,
      'demo-session-${connectedAt.microsecondsSinceEpoch}',
    );
    await _store.write(_sessionCommandCountKey, '0');
    await _store.delete(_lastCommandKindKey);
    await _store.delete(_lastCommandMessageKey);
    await _store.delete(_lastCommandAtKey);
  }

  Future<void> _clearProtocolSessionMetadata() async {
    await _store.delete(_sessionIdKey);
    await _store.delete(_sessionCommandCountKey);
    await _store.delete(_lastCommandKindKey);
    await _store.delete(_lastCommandMessageKey);
    await _store.delete(_lastCommandAtKey);
  }

  ExternalDeviceCommandKind? _parseCommandKind(String? rawValue) {
    if (rawValue == null) {
      return null;
    }

    for (final kind in ExternalDeviceCommandKind.values) {
      if (kind.name == rawValue) {
        return kind;
      }
    }

    return null;
  }
}
