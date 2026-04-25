import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/key_storage/phone_secure_vault.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';

void main() {
  group('PhoneSecureVault', () {
    late InMemorySecureKeyValueStore store;
    late PhoneSecureVault vault;

    setUp(() {
      store = InMemorySecureKeyValueStore();
      vault = PhoneSecureVault(store: store);
    });

    test(
      'creates wallet, stores encrypted payload and unlocks with PIN',
      () async {
        final material = await vault.createWallet(pin: '123456');
        final storedPayload = await store.read(PhoneSecureVault.storageKey);

        expect(await vault.hasWallet(), isTrue);
        expect(material.address, startsWith('0x'));
        expect(material.mnemonic.split(' '), hasLength(12));
        expect(storedPayload, isNotNull);
        expect(storedPayload, isNot(contains(material.mnemonic)));

        vault.lock();
        expect(vault.isUnlocked, isFalse);

        final unlockedMaterial = await vault.unlock(pin: '123456');
        expect(unlockedMaterial.address, material.address);
        expect(unlockedMaterial.privateKeyHex, material.privateKeyHex);
      },
    );

    test(
      'imports known mnemonic and derives expected first EVM address',
      () async {
        const mnemonic =
            'test test test test test test test test test test test junk';

        final material = await vault.importWallet(
          mnemonic: mnemonic,
          pin: '654321',
        );

        expect(
          material.address,
          equals('0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'),
        );
      },
    );

    test('rejects invalid pin on unlock', () async {
      await vault.createWallet(pin: '123456');
      vault.lock();

      expect(
        () => vault.unlock(pin: '000000'),
        throwsA(isA<InvalidPinFailure>()),
      );
    });

    test('returns wallet summary without exposing mnemonic', () async {
      final material = await vault.createWallet(pin: '123456');
      final summary = await vault.getWalletSummary();

      expect(summary, isNotNull);
      expect(summary!.address, material.address);
      expect(summary.backendId, 'phone_secure_vault');
    });
  });
}
