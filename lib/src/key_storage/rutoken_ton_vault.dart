import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';

import '../errors/app_error.dart';
import '../ton/ton_account.dart';
import '../ton/ton_network.dart';
import 'custody_backend.dart';
import 'key_storage_backend.dart';
import 'secure_key_value_store.dart';
import 'ton_mnemonic.dart';

/// The token exposes only its object identity and public key.
final class RutokenTonKey {
  RutokenTonKey({
    required List<int> id,
    required List<int> publicKey,
    required this.generatedOnCard,
  }) : id = Uint8List.fromList(id).asUnmodifiableView(),
       account = TonAccount(publicKey) {
    if (this.id.length != 16) {
      throw const FormatException('Invalid Rutoken TON key identity');
    }
  }

  final Uint8List id;
  final TonAccount account;
  final bool generatedOnCard;

  String get idHex => hex.encode(id);
}

abstract interface class RutokenTonAdapter implements RutokenNativeAdapter {
  Future<RutokenTonKey?> readTonKey(RutokenNativeSession session);
  Future<RutokenTonKey> generateTonKey(RutokenNativeSession session);
  Future<RutokenTonKey> importTonKey({
    required RutokenNativeSession session,
    required Uint8List seed,
    required Uint8List publicKey,
  });
  Future<Uint8List> signTonHash({
    required RutokenNativeSession session,
    required Uint8List keyId,
    required Uint8List hash,
  });
}

final class RutokenTonProfile {
  const RutokenTonProfile({required this.serial, required this.key});

  final String serial;
  final RutokenTonKey key;
}

/// Stores card profiles separately from Ethereum and signs in one NFC session.
final class RutokenTonVault {
  RutokenTonVault({
    required RutokenTonAdapter adapter,
    required SecureKeyValueStore store,
  }) : _adapter = adapter,
       _store = store;

  static const storageKey = 'wallet.rutoken_ton_testnet.v1';
  final RutokenTonAdapter _adapter;
  final SecureKeyValueStore _store;
  bool _busy = false;
  bool _cancelled = false;

  Future<List<RutokenTonProfile>> profiles() async {
    final raw = await _store.read(storageKey);
    if (raw == null) return [];
    try {
      return [
        for (final value in jsonDecode(raw) as List)
          RutokenTonProfile(
            serial: value['serial'] as String,
            key: RutokenTonKey(
              id: hex.decode(value['id'] as String),
              publicKey: hex.decode(value['publicKey'] as String),
              generatedOnCard: value['generatedOnCard'] as bool,
            ),
          ),
      ];
    } catch (_) {
      throw const VaultFailure.coded(AppErrorCode.cardDataCorrupted);
    }
  }

  Future<RutokenTonProfile> adopt({required String pin}) =>
      _withSession(pin, (session, serial) async {
        final key = await _adapter.readTonKey(session);
        if (key == null) {
          throw const VaultFailure.coded(AppErrorCode.cardNoCompatibleWallet);
        }
        return _register(serial, key);
      });

  Future<RutokenTonProfile> generateOnCard({required String pin}) =>
      _withSession(pin, (session, serial) async {
        final key = await _adapter.generateTonKey(session);
        return _register(serial, key);
      });

  Future<RutokenTonProfile> importMnemonic({
    required String mnemonic,
    required String pin,
    String? expectedAddress,
    TonNetwork network = TonNetwork.testnet,
  }) => _operation(() async {
    final seed = await TonMnemonic.deriveSeed(mnemonic);
    try {
      final pair = await (await Ed25519().newKeyPairFromSeed(seed)).extract();
      final Uint8List publicKey;
      try {
        publicKey = Uint8List.fromList((await pair.extractPublicKey()).bytes);
      } finally {
        pair.destroy();
      }
      TonAccount(
        publicKey,
        network: network,
      ).checkRecoveryAddress(expectedAddress);
      return await _openSession(pin, (session, serial) async {
        final key = await _adapter.importTonKey(
          session: session,
          seed: seed,
          publicKey: publicKey,
        );
        if (key.account.publicKeyHex != hex.encode(publicKey)) {
          throw const VaultFailure.coded(AppErrorCode.cardAddressMismatch);
        }
        return _register(serial, key);
      });
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  });

  Future<Uint8List> sign({
    required RutokenTonProfile profile,
    required String pin,
    required Uint8List hash,
  }) {
    if (hash.length != 32) throw ArgumentError('Expected a TON cell hash');
    final message = Uint8List.fromList(hash);
    return _withSession(pin, (session, serial) async {
      if (serial != profile.serial) {
        throw const VaultFailure.coded(AppErrorCode.cardWrongCard);
      }
      final actual = await _adapter.readTonKey(session);
      if (actual == null ||
          actual.idHex != profile.key.idHex ||
          actual.account.publicKeyHex != profile.key.account.publicKeyHex) {
        throw const VaultFailure.coded(AppErrorCode.cardAddressMismatch);
      }
      _assertActive();
      final signature = await _adapter.signTonHash(
        session: session,
        keyId: actual.id,
        hash: message,
      );
      if (!await profile.key.account.verify(message, signature)) {
        throw const VaultFailure.coded(AppErrorCode.cardAddressMismatch);
      }
      return signature;
    });
  }

  Future<void> cancelPendingOperation() async {
    if (!_busy) return;
    _cancelled = true;
    await _adapter.cancelPendingOperation();
  }

  Future<RutokenTonProfile> _register(String serial, RutokenTonKey key) async {
    _assertActive();
    final known = await profiles();
    final profile = RutokenTonProfile(serial: serial, key: key);
    final updated = [
      ...known.where((candidate) => candidate.serial != serial),
      profile,
    ];
    _assertActive();
    await _store.write(
      storageKey,
      jsonEncode([
        for (final item in updated)
          {
            'serial': item.serial,
            'id': item.key.idHex,
            'publicKey': item.key.account.publicKeyHex,
            'generatedOnCard': item.key.generatedOnCard,
          },
      ]),
    );
    return profile;
  }

  Future<T> _withSession<T>(
    String pin,
    Future<T> Function(RutokenNativeSession, String) use,
  ) => _operation(() => _openSession(pin, use));

  Future<T> _operation<T>(Future<T> Function() use) async {
    if (_busy) throw const VaultFailure.coded(AppErrorCode.cardNativeFailure);
    _busy = true;
    _cancelled = false;
    try {
      final result = await use();
      _assertActive();
      return result;
    } finally {
      _busy = false;
    }
  }

  Future<T> _openSession<T>(
    String pin,
    Future<T> Function(RutokenNativeSession, String) use,
  ) async {
    if (pin.isEmpty) throw const VaultFailure.coded(AppErrorCode.cardPinEmpty);
    _assertActive();
    final session = await _adapter.openSession(pin: pin);
    Object? primaryFailure;
    try {
      _assertActive();
      final serial = session.serial;
      if (serial == null || serial.isEmpty) {
        throw const VaultFailure.coded(AppErrorCode.cardProfileUnsupported);
      }
      return await use(session, serial);
    } catch (error) {
      primaryFailure = error;
      rethrow;
    } finally {
      try {
        await _adapter.closeSession(session);
      } catch (_) {
        if (primaryFailure == null) rethrow;
      }
    }
  }

  void _assertActive() {
    if (_cancelled) throw const VaultFailure.coded(AppErrorCode.cardCancelled);
  }
}
