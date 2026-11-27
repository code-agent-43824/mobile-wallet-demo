import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/errors/app_error.dart';
import 'package:mobile_wallet_demo/src/key_storage/custody_backend.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/key_storage/phone_ton_vault.dart';
import 'package:mobile_wallet_demo/src/key_storage/rutoken_ton_vault.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/key_storage/ton_mnemonic.dart';
import 'package:mobile_wallet_demo/src/ton/ton_network.dart';

import 'fixtures/ton_test_vectors.dart';

const _publicKey =
    'f6c450a16bb1c514e22f1977e390a3025599aa1e7b00068a6aacf2119484c1bd';
const _address = '0QC2w3H-ofk4DSeQynfr5fUiDdiVjxYoi8PGzW9Zd7X-sz0t';
const _signature =
    'af055d57adeb5069c9196e557ff271fc8e2467da3ac97c3ea09b1155e7e44121a'
    '5caf1e083b49f8721671af869d5c3b2e6344408200aceca1754ef143e1fab03';
final _hash = Uint8List.fromList(List.generate(32, (index) => index));

void main() {
  test(
    'phone vault restores the reference address and signs after a restart',
    () async {
      final store = InMemorySecureKeyValueStore();
      final original = PhoneTonVault(store: store, pbkdf2Iterations: 1);
      final account = await original.importMnemonic(
        mnemonic: tonTestMnemonic,
        pin: '123456',
      );
      expect(account.publicKeyHex, _publicKey);
      expect(account.address, _address);
      final stored = await store.read(PhoneTonVault.storageKey);
      expect(stored, isNot(contains(tonTestMnemonic)));
      expect(stored, isNot(contains('123456')));

      final restarted = PhoneTonVault(store: store, pbkdf2Iterations: 1);
      final restored = (await restarted.getAccount())!;
      expect(restored.address, _address);
      await expectLater(
        restarted.sign(account: restored, hash: _hash, pin: '654321'),
        throwsA(isA<InvalidPinFailure>()),
      );
      final signature = await restarted.sign(
        account: restored,
        hash: _hash,
        pin: '123456',
      );
      expect(hex.encode(signature), _signature);
      final mainnetSignature = await restarted.sign(
        account: restored.onNetwork(TonNetwork.mainnet),
        hash: _hash,
        pin: '123456',
      );
      expect(hex.encode(mainnetSignature), _signature);
      await expectLater(
        restarted.importMnemonic(mnemonic: tonTestMnemonic, pin: '654321'),
        throwsA(
          isA<VaultFailure>().having(
            (error) => error.errorCode,
            'code',
            AppErrorCode.walletAlreadyExists,
          ),
        ),
      );
    },
  );

  test('generated words satisfy native TON validation', () async {
    final phrase = await TonMnemonic.generate();
    expect(phrase.split(' '), hasLength(24));
    final seed = await TonMnemonic.deriveSeed(phrase);
    expect(seed, hasLength(32));
    seed.fillRange(0, seed.length, 0);
    await expectLater(
      TonMnemonic.deriveSeed(List.filled(24, 'notaword').join(' ')),
      throwsA(isA<InvalidMnemonicFailure>()),
    );
  });

  test(
    'card import binds public metadata and signs through the exact card',
    () async {
      final store = InMemorySecureKeyValueStore();
      final adapter = _Card();
      final vault = RutokenTonVault(adapter: adapter, store: store);
      final profile = await vault.importMnemonic(
        mnemonic: tonTestMnemonic,
        pin: '123456',
      );
      expect(profile.key.account.address, _address);
      expect(adapter.imports, 1);
      expect(adapter.closes, 1);
      final record = await store.read(RutokenTonVault.storageKey);
      expect(record, contains(_publicKey));
      expect(record, isNot(contains(tonTestMnemonic)));
      expect(record, isNot(contains('123456')));
      expect((await vault.profiles()).single.serial, 'serial-a');

      adapter.serial = 'serial-b';
      await expectLater(
        vault.sign(profile: profile, pin: '123456', hash: _hash),
        throwsA(
          isA<VaultFailure>().having(
            (error) => error.errorCode,
            'code',
            AppErrorCode.cardWrongCard,
          ),
        ),
      );
      expect(adapter.signs, 0);
      expect(adapter.closes, 2);
      adapter.serial = 'serial-a';
      expect(
        hex.encode(
          await vault.sign(profile: profile, pin: '123456', hash: _hash),
        ),
        _signature,
      );
      expect(adapter.signs, 1);
      expect(adapter.closes, 3);
    },
  );

  test(
    'card generation and adoption use the public key from the token',
    () async {
      final adapter = _Card();
      final vault = RutokenTonVault(
        adapter: adapter,
        store: InMemorySecureKeyValueStore(),
      );
      final generated = await vault.generateOnCard(pin: '123456');
      expect(generated.key.generatedOnCard, isTrue);
      final adopted = await vault.adopt(pin: '123456');
      expect(adopted.key.account.address, generated.key.account.address);
      expect(await vault.profiles(), hasLength(1));
      expect(adapter.imports, 0);
      expect(adapter.closes, 2);
    },
  );
}

class _Card implements RutokenTonAdapter {
  String serial = 'serial-a';
  int imports = 0;
  int closes = 0;
  int signs = 0;
  RutokenTonKey? key;

  @override
  Future<RutokenNativeSession> openSession({required String pin}) async =>
      RutokenNativeSession(
        id: 'session',
        openedAtUtc: DateTime.utc(2026),
        serial: serial,
      );

  @override
  Future<void> closeSession(RutokenNativeSession session) async => closes++;

  @override
  Future<RutokenTonKey?> readTonKey(RutokenNativeSession session) async => key;

  @override
  Future<RutokenTonKey> generateTonKey(RutokenNativeSession session) async =>
      key = RutokenTonKey(
        id: List.filled(16, 1),
        publicKey: hex.decode(_publicKey),
        generatedOnCard: true,
      );

  @override
  Future<RutokenTonKey> importTonKey({
    required RutokenNativeSession session,
    required Uint8List seed,
    required Uint8List publicKey,
  }) async {
    imports++;
    expect(seed, hasLength(32));
    expect(hex.encode(publicKey), _publicKey);
    return key = RutokenTonKey(
      id: List.filled(16, 1),
      publicKey: publicKey,
      generatedOnCard: false,
    );
  }

  @override
  Future<Uint8List> signTonHash({
    required RutokenNativeSession session,
    required Uint8List keyId,
    required Uint8List hash,
  }) async {
    signs++;
    expect(keyId, key!.id);
    expect(hash, _hash);
    return Uint8List.fromList(hex.decode(_signature));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
