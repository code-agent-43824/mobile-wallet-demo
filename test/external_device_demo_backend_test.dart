import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/key_storage/external_device_demo_backend.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';

void main() {
  test(
    'tracks availability and session lifecycle for demo external device',
    () async {
      final backend = ExternalDeviceDemoBackend(
        store: InMemorySecureKeyValueStore(),
      );

      expect(await backend.isDeviceAvailable(), isTrue);

      final material = await backend.createWallet(pin: '1234');
      expect(material.address, isNotEmpty);

      var state = await backend.loadRuntimeState();
      expect(state.hasLinkedWallet, isTrue);
      expect(state.hasActiveSession, isFalse);
      expect(state.lastError, isNull);

      await backend.unlock(pin: '1234');
      state = await backend.loadRuntimeState();
      expect(state.hasActiveSession, isTrue);
      expect(state.connectedAtUtc, isNotNull);

      await backend.disconnectSession();
      state = await backend.loadRuntimeState();
      expect(state.hasActiveSession, isFalse);
      expect(state.lastError, contains('Device session ended'));

      await backend.simulateDeviceUnavailable();
      state = await backend.loadRuntimeState();
      expect(state.isAvailable, isFalse);
      expect(state.lastError, contains('offline'));

      expect(() => backend.unlock(pin: '1234'), throwsA(isA<VaultFailure>()));

      await backend.reconnectDevice();
      state = await backend.loadRuntimeState();
      expect(state.isAvailable, isTrue);
      expect(state.lastError, isNull);
    },
  );
}
