import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/key_storage/rutoken_biometric_pin_store.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';

const _address = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

void main() {
  test(
    'declining remembers the one-time choice without storing a PIN',
    () async {
      final store = InMemorySecureKeyValueStore();
      final gateway = _CountingBiometricGateway();
      final pins = RutokenBiometricPinStore(
        store: store,
        biometricAuth: gateway,
      );

      expect(await pins.shouldOffer(_address), isTrue);
      await pins.decline(_address);

      expect(await pins.shouldOffer(_address), isFalse);
      expect(await pins.isEnabled(_address), isFalse);
      expect(gateway.authenticationCount, 0);
    },
  );

  test('enable and every retrieval require biometric authentication', () async {
    final store = InMemorySecureKeyValueStore();
    final gateway = _CountingBiometricGateway();
    final pins = RutokenBiometricPinStore(store: store, biometricAuth: gateway);

    await pins.enable(address: _address, pin: '12345678');
    expect(gateway.authenticationCount, 1);
    expect(await pins.isEnabled(_address), isTrue);

    expect(await pins.retrieve(_address), '12345678');
    expect(gateway.authenticationCount, 2);
  });
}

class _CountingBiometricGateway implements BiometricAuthGateway {
  int authenticationCount = 0;

  @override
  BiometricAuthMode get mode => BiometricAuthMode.local;

  @override
  Future<void> authenticate({required String reason}) async {
    authenticationCount++;
  }

  @override
  Future<bool> isAvailable() async => true;
}
