import 'dart:convert';

import '../auth/biometric_auth.dart';
import 'biometric_secret_store.dart';
import 'key_storage_backend.dart';
import 'secure_key_value_store.dart';

/// Keeps a Rutoken PIN outside the public account profile and releases it only
/// after the configured [BiometricSecretStore] completes authentication.
///
/// The account address scopes both the secret and the one-time offer decision,
/// so adopting another card cannot silently reuse the previous card's PIN.
class RutokenBiometricPinStore {
  RutokenBiometricPinStore({
    required SecureKeyValueStore store,
    required BiometricAuthGateway biometricAuth,
    BiometricSecretStore? secretStore,
  }) : _store = store,
       _biometricAuth = biometricAuth,
       _secretStore =
           secretStore ??
           GatedBiometricSecretStore(
             store: store,
             biometricAuth: biometricAuth,
             namespace: 'wallet.rutoken_pin_secret.v1.',
           );

  static const String _decisionPrefix = 'wallet.rutoken_pin_offer.v1.';

  final SecureKeyValueStore _store;
  final BiometricAuthGateway _biometricAuth;
  final BiometricSecretStore _secretStore;

  Future<bool> isAvailable() => _secretStore.isAvailable();

  Future<bool> isEnabled(String address) async {
    return await _store.read(_decisionKey(address)) == 'enabled';
  }

  Future<bool> shouldOffer(String address) async {
    return await isAvailable() &&
        await _store.read(_decisionKey(address)) == null;
  }

  Future<void> enable({required String address, required String pin}) async {
    if (pin.isEmpty) {
      throw const VaultFailure('PIN Рутокена не должен быть пустым.');
    }
    if (!await isAvailable()) {
      throw const BiometricUnavailableFailure();
    }
    await _biometricAuth.authenticate(
      reason: 'Подтвердите биометрию, чтобы сохранить PIN Рутокена.',
    );
    final bytes = utf8.encode(pin);
    try {
      await _secretStore.store(id: _secretId(address), secret: bytes);
      await _store.write(_decisionKey(address), 'enabled');
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<void> decline(String address) async {
    await _secretStore.delete(_secretId(address));
    await _store.write(_decisionKey(address), 'declined');
  }

  Future<String> retrieve(String address) async {
    if (!await isEnabled(address)) {
      throw const BiometricNotEnabledFailure();
    }
    final bytes = await _secretStore.retrieve(
      id: _secretId(address),
      reason: 'Подтвердите биометрию для доступа к PIN Рутокена.',
    );
    if (bytes == null) {
      throw const BiometricNotEnabledFailure();
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  String _decisionKey(String address) =>
      '$_decisionPrefix${_accountId(address)}';

  String _secretId(String address) => 'pin.${_accountId(address)}';

  String _accountId(String address) =>
      address.toLowerCase().replaceFirst('0x', '');
}
