import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';

void main() {
  test('deleting an absent key never reaches the platform delete', () async {
    // On macOS the plugin reports an absent key's delete as -34018.
    final storage = _RecordingStorage();
    await FlutterSecureKeyValueStore(storage).delete('missing');
    expect(storage.deleted, isEmpty);
  });

  test('deleting a stored key removes it', () async {
    final storage = _RecordingStorage()..values['present'] = 'v';
    await FlutterSecureKeyValueStore(storage).delete('present');
    expect(storage.deleted, <String>['present']);
  });
}

class _RecordingStorage implements FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};
  final List<String> deleted = <String>[];

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deleted.add(key);
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
