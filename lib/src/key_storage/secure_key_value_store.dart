import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              // Never erase a wallet merely because the platform keystore
              // reported a transient/migration error. Surface the exception
              // instead so recovery remains possible.
              resetOnError: false,
              migrateOnAlgorithmChange: true,
              // v10 migrates the legacy v9 Android cipher used by existing
              // installs. Keep a crash-safe backup until migration commits.
              migrateWithBackup: true,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) {
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) {
    return _storage.delete(key: key);
  }
}

class InMemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
