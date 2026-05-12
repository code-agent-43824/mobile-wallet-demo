import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/key_storage/backend_registry.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';

void main() {
  test(
    'falls back to first available backend and persists selection',
    () async {
      final store = InMemorySecureKeyValueStore();
      final registry = WalletBackendRegistry(
        store: store,
        entries: <WalletBackendCatalogEntry>[
          WalletBackendCatalogEntry(
            descriptor: const WalletBackendDescriptor(
              id: 'phone_secure_vault',
              kind: WalletBackendKind.phoneSecureVault,
              label: 'Phone Secure Vault',
              description: 'local vault',
            ),
            backend: _FakeBackend('phone_secure_vault'),
          ),
          const WalletBackendCatalogEntry(
            descriptor: WalletBackendDescriptor(
              id: 'external_nfc_device',
              kind: WalletBackendKind.externalDevice,
              label: 'External NFC device',
              description: 'future signer',
              isAvailable: false,
            ),
          ),
        ],
      );

      final selectedBackendId = await registry.loadSelectedBackendId();
      final selected = await registry.loadSelection();

      expect(selectedBackendId, 'phone_secure_vault');
      expect(selected?.backendId, 'phone_secure_vault');
    },
  );

  test('rejects selecting unavailable backend', () async {
    final registry = WalletBackendRegistry(
      store: InMemorySecureKeyValueStore(),
      entries: <WalletBackendCatalogEntry>[
        WalletBackendCatalogEntry(
          descriptor: const WalletBackendDescriptor(
            id: 'phone_secure_vault',
            kind: WalletBackendKind.phoneSecureVault,
            label: 'Phone Secure Vault',
            description: 'local vault',
          ),
          backend: _FakeBackend('phone_secure_vault'),
        ),
        const WalletBackendCatalogEntry(
          descriptor: WalletBackendDescriptor(
            id: 'external_nfc_device',
            kind: WalletBackendKind.externalDevice,
            label: 'External NFC device',
            description: 'future signer',
            isAvailable: false,
          ),
        ),
      ],
    );

    expect(
      () => registry.selectBackend('external_nfc_device'),
      throwsA(isA<VaultFailure>()),
    );
  });
}

class _FakeBackend implements KeyStorageBackend {
  const _FakeBackend(this.backendId);

  @override
  final String backendId;

  @override
  bool get isUnlocked => false;

  @override
  Future<void> clear() async {}

  @override
  Future<WalletMaterial> createWallet({required String pin}) {
    throw UnimplementedError();
  }

  @override
  Future<StoredWalletSummary?> getWalletSummary() async => null;

  @override
  Future<bool> hasWallet() async => false;

  @override
  Future<WalletMaterial> importWallet({
    required String mnemonic,
    required String pin,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<bool> isBiometricUnlockAvailable() async => false;

  @override
  Future<bool> isBiometricUnlockEnabled() async => false;

  @override
  void lock() {}

  @override
  Future<void> setBiometricUnlockEnabled({
    required bool enabled,
    required String pin,
  }) async {}

  @override
  Future<WalletMaterial> unlock({required String pin}) {
    throw UnimplementedError();
  }

  @override
  Future<WalletMaterial> unlockWithBiometrics() {
    throw UnimplementedError();
  }
}
