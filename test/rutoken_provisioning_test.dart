import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/key_storage/custody_backend.dart';
import 'package:mobile_wallet_demo/src/key_storage/rutoken_method_channel_adapter.dart';
import 'package:mobile_wallet_demo/src/key_storage/rutoken_provisioning.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:web3dart/web3dart.dart' show bytesToHex, publicKeyToAddress;

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _expectedMasterPrivateKey =
    'cbedc75b0d6412c85c79bc13875112ef912fd1e756631b5a00330866f22ff184';
const _expectedMasterChainCode =
    'a3fa8c983223306de0f0f65e74ebb1e98aba751633bf91d5fb56529aa5c132c1';

void main() {
  test(
    'imports the BIP39 vector, persists only public metadata, and closes',
    () async {
      final store = _RecordingStore();
      final adapter = _ProvisioningAdapter();
      final service = RutokenProvisioningService(
        adapter: adapter,
        store: store,
      );

      final result = await service.provision(
        mnemonic: _mnemonic,
        passphrase: 'TREZOR',
        pin: '12345678',
      );

      expect(bytesToHex(adapter.masterCopy!), _expectedMasterPrivateKey);
      expect(bytesToHex(adapter.chainCodeCopy!), _expectedMasterChainCode);
      expect(adapter.openCount, 1);
      expect(adapter.closeCount, 1);
      expect(adapter.masterReference, everyElement(0));
      expect(adapter.chainCodeReference, everyElement(0));
      expect(result.account.address, hasLength(42));

      final publicAccount = await service.loadPublicAccount();
      expect(publicAccount?.account.address, result.account.address);
      expect(publicAccount?.accountPath, "m/44'/60'/0'");
      expect(publicAccount?.compressedPublicKey, hasLength(33));
      expect(publicAccount?.chainCode, hasLength(32));

      final persisted = store.values.values.join();
      expect(persisted, isNot(contains('abandon')));
      expect(persisted, isNot(contains('TREZOR')));
      expect(persisted, isNot(contains(_expectedMasterPrivateKey)));
      expect(persisted, contains('"state":"active"'));
    },
  );

  test('normalizes equivalent Unicode passphrases with BIP39 NFKD', () async {
    final composed = _ProvisioningAdapter();
    final decomposed = _ProvisioningAdapter();

    await RutokenProvisioningService(
      adapter: composed,
      store: _RecordingStore(),
    ).provision(mnemonic: _mnemonic, passphrase: 'caf\u00e9', pin: '1234');
    await RutokenProvisioningService(
      adapter: decomposed,
      store: _RecordingStore(),
    ).provision(mnemonic: _mnemonic, passphrase: 'cafe\u0301', pin: '1234');

    expect(composed.masterCopy, decomposed.masterCopy);
    expect(composed.chainCodeCopy, decomposed.chainCodeCopy);
  });

  test(
    'rejects invalid mnemonic before NFC and keeps no active metadata',
    () async {
      final adapter = _ProvisioningAdapter();
      final service = RutokenProvisioningService(
        adapter: adapter,
        store: _RecordingStore(),
      );

      await expectLater(
        service.provision(
          mnemonic: 'abandon abandon abandon',
          passphrase: '',
          pin: '1234',
        ),
        throwsA(isA<RutokenNativeException>()),
      );
      expect(adapter.openCount, 0);
      expect(await service.loadPublicAccount(), isNull);
    },
  );

  test(
    'keeps failed provisioning metadata non-active and closes session',
    () async {
      final adapter = _ProvisioningAdapter(failImport: true);
      final service = RutokenProvisioningService(
        adapter: adapter,
        store: _RecordingStore(),
      );

      await expectLater(
        service.provision(mnemonic: _mnemonic, passphrase: '', pin: '1234'),
        throwsA(isA<StateError>()),
      );
      expect(adapter.closeCount, 1);
      expect(await service.loadPublicAccount(), isNull);
    },
  );

  test(
    'keeps verified public metadata if teardown reports after import',
    () async {
      final adapter = _ProvisioningAdapter(failClose: true);
      final service = RutokenProvisioningService(
        adapter: adapter,
        store: _RecordingStore(),
      );

      await expectLater(
        service.provision(mnemonic: _mnemonic, passphrase: '', pin: '1234'),
        throwsA(isA<StateError>()),
      );
      expect(adapter.closeCount, 1);
      expect(await service.loadPublicAccount(), isNotNull);
    },
  );

  test('generates a 24-word recoverable backup with the chosen passphrase', () {
    final service = RutokenProvisioningService(
      adapter: _ProvisioningAdapter(),
      store: _RecordingStore(),
    );

    final backup = service.generateBackup(passphrase: 'offline secret');

    expect(backup.mnemonic.split(' '), hasLength(24));
    expect(backup.passphrase, 'offline secret');
  });
}

class _ProvisioningAdapter implements RutokenNativeAdapter {
  _ProvisioningAdapter({this.failImport = false, this.failClose = false});

  final bool failImport;
  final bool failClose;
  int openCount = 0;
  int closeCount = 0;
  Uint8List? masterCopy;
  Uint8List? chainCodeCopy;
  Uint8List? masterReference;
  Uint8List? chainCodeReference;

  @override
  Future<RutokenNativeSession> openSession({required String pin}) async {
    openCount++;
    return RutokenNativeSession(
      id: 'provision-$openCount',
      openedAtUtc: DateTime.utc(2026, 7, 23),
    );
  }

  @override
  Future<WalletAccountDescriptor> importWallet({
    required RutokenNativeSession session,
    required Uint8List masterPrivateKey,
    required Uint8List chainCode,
  }) async {
    masterReference = masterPrivateKey;
    chainCodeReference = chainCode;
    masterCopy = Uint8List.fromList(masterPrivateKey);
    chainCodeCopy = Uint8List.fromList(chainCode);
    if (failImport) throw StateError('token is not empty');

    final master = bip32.BIP32.fromPrivateKey(masterPrivateKey, chainCode);
    final addressNode = master.derivePath(
      RutokenProvisioningService.addressPath,
    );
    final point = RutokenEcPoint.decode(addressNode.publicKey);
    return WalletAccountDescriptor(
      backendId: 'rutoken_nfc',
      address: '0x${bytesToHex(publicKeyToAddress(point.uncompressedXY))}',
      derivationPath: RutokenProvisioningService.addressPath,
    );
  }

  @override
  Future<void> closeSession(RutokenNativeSession session) async {
    closeCount++;
    if (failClose) throw StateError('teardown failed');
  }

  @override
  Future<WalletAccountDescriptor?> readAccountDescriptor(
    RutokenNativeSession session,
  ) async => null;

  @override
  Future<RawEcdsaSignature> signDigest({
    required RutokenNativeSession session,
    required String derivationPath,
    required Uint8List digest,
  }) async {
    return RawEcdsaSignature.fromBytes(Uint8List(64));
  }
}

class _RecordingStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
