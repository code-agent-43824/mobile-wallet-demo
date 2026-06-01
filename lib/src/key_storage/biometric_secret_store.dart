import 'package:convert/convert.dart';

import '../auth/biometric_auth.dart';
import 'secure_key_value_store.dart';

/// Stores a small secret (e.g. a wallet data-encryption key) that must only be
/// released after a successful biometric authentication.
///
/// Security note: a fully correct production implementation should bind the
/// secret to platform secure hardware (Android Keystore / iOS Keychain with
/// biometric access control) so that the secret cannot be recovered from a
/// storage dump alone. [GatedBiometricSecretStore] is the default used by the
/// app: it keeps the biometric secret in its own namespace inside the injected
/// [SecureKeyValueStore] and gates every read behind a [BiometricAuthGateway].
/// That already removes the previous flaw of co-locating a usable key next to
/// the seed ciphertext and of persisting the user's PIN, but true
/// hardware-bound biometric release still requires a native keystore plugin
/// (tracked as follow-up work).
abstract interface class BiometricSecretStore {
  Future<bool> isAvailable();

  /// Persists [secret] under [id]. Callers are expected to have already
  /// confirmed user intent (the vault authenticates when enabling biometrics).
  Future<void> store({required String id, required List<int> secret});

  /// Returns the secret stored for [id], prompting for biometric
  /// authentication first. Returns null when nothing is stored for [id].
  Future<List<int>?> retrieve({required String id, required String reason});

  Future<void> delete(String id);
}

class GatedBiometricSecretStore implements BiometricSecretStore {
  GatedBiometricSecretStore({
    required SecureKeyValueStore store,
    required BiometricAuthGateway biometricAuth,
    String namespace = 'wallet.biometric_secret.v1.',
  }) : _store = store,
       _biometricAuth = biometricAuth,
       _namespace = namespace;

  final SecureKeyValueStore _store;
  final BiometricAuthGateway _biometricAuth;
  final String _namespace;

  String _key(String id) => '$_namespace$id';

  @override
  Future<bool> isAvailable() => _biometricAuth.isAvailable();

  @override
  Future<void> store({required String id, required List<int> secret}) {
    return _store.write(_key(id), hex.encode(secret));
  }

  @override
  Future<List<int>?> retrieve({
    required String id,
    required String reason,
  }) async {
    await _biometricAuth.authenticate(reason: reason);
    final raw = await _store.read(_key(id));
    if (raw == null) {
      return null;
    }
    return hex.decode(raw);
  }

  @override
  Future<void> delete(String id) => _store.delete(_key(id));
}
