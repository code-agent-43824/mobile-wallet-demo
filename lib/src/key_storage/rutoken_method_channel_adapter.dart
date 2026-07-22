import 'package:bip32/bip32.dart' as bip32;
import 'package:flutter/services.dart';
import 'package:web3dart/web3dart.dart' show bytesToHex, publicKeyToAddress;

import 'custody_backend.dart';

class RutokenNativeException implements Exception {
  const RutokenNativeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Flutter platform-channel implementation of [RutokenNativeAdapter].
///
/// Native code owns NFC, login and PKCS#11 object/session lifetimes. This Dart
/// layer turns only public EC points into the account descriptor and keeps EVM
/// signature canonicalization in the already-tested EVM layer.
class MethodChannelRutokenNativeAdapter implements RutokenNativeAdapter {
  MethodChannelRutokenNativeAdapter({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'wallet_demo/rutoken';
  static const String accountPath = "m/44'/60'/0'";
  static const String addressPath = "m/44'/60'/0'/0/0";

  final MethodChannel _channel;

  @override
  Future<RutokenNativeSession> openSession({required String pin}) async {
    final response = await _invokeMap('openSession', <String, Object?>{
      'pin': pin,
    });
    final id = response['sessionId'];
    if (id is! String || id.isEmpty) {
      throw const RutokenNativeException(
        'Android Rutoken bridge returned no session identifier.',
      );
    }
    return RutokenNativeSession(id: id, openedAtUtc: DateTime.now().toUtc());
  }

  @override
  Future<WalletAccountDescriptor?> readAccountDescriptor(
    RutokenNativeSession session,
  ) async => (await readAccountPublicKey(session)).account;

  @override
  Future<WalletAccountPublicKey> readAccountPublicKey(
    RutokenNativeSession session,
  ) async {
    final response = await _invokeMap('readPublicMaterial', <String, Object?>{
      'sessionId': session.id,
    });
    final master = RutokenEcPoint.decode(_bytes(response, 'masterPublicKey'));
    final parent = RutokenEcPoint.decode(_bytes(response, 'parentPublicKey'));
    final account = RutokenEcPoint.decode(_bytes(response, 'accountPublicKey'));
    final address = RutokenEcPoint.decode(_bytes(response, 'addressPublicKey'));
    final chainCode = _bytes(response, 'accountChainCode');
    if (chainCode.length != 32) {
      throw RutokenNativeException(
        'Rutoken account chain code has ${chainCode.length} bytes; expected 32.',
      );
    }

    return WalletAccountPublicKey(
      account: WalletAccountDescriptor(
        backendId: 'rutoken_nfc',
        address: '0x${bytesToHex(publicKeyToAddress(address.uncompressedXY))}',
        derivationPath: addressPath,
      ),
      accountPath: accountPath,
      accountDepth: 3,
      compressedPublicKey: account.compressed,
      chainCode: chainCode,
      sourceFingerprint: _fingerprint(master.compressed),
      parentFingerprint: _fingerprint(parent.compressed),
    );
  }

  @override
  Future<RawEcdsaSignature> signDigest({
    required RutokenNativeSession session,
    required String derivationPath,
    required Uint8List digest,
  }) async {
    if (digest.length != 32) {
      throw ArgumentError.value(digest.length, 'digest', 'Expected 32 bytes.');
    }
    final signature = await _invokeBytes('signDigest', <String, Object?>{
      'sessionId': session.id,
      'derivationPath': RutokenDerivationPath.parse(derivationPath),
      'digest': digest,
    });
    return RawEcdsaSignature.fromBytes(signature);
  }

  @override
  Future<void> closeSession(RutokenNativeSession session) =>
      _invokeVoid('closeSession', <String, Object?>{'sessionId': session.id});

  @override
  Future<RutokenProvisioningResult> generateWallet({
    required RutokenNativeSession session,
    int mnemonicWordCount = 24,
    String? passphrase,
  }) => throw const RutokenNativeException(
    'Rutoken provisioning is not enabled in the transport-spike build.',
  );

  @override
  Future<WalletAccountDescriptor> importWallet({
    required RutokenNativeSession session,
    required Uint8List masterPrivateKey,
    required Uint8List chainCode,
  }) => throw const RutokenNativeException(
    'Rutoken provisioning is not enabled in the transport-spike build.',
  );

  Future<Map<Object?, Object?>> _invokeMap(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final response = await _channel.invokeMethod<Object?>(method, arguments);
      if (response is Map<Object?, Object?>) return response;
      throw RutokenNativeException('$method returned an invalid response.');
    } on PlatformException catch (error) {
      throw RutokenNativeException(error.message ?? error.code);
    } on MissingPluginException {
      throw const RutokenNativeException(
        'Rutoken native bridge is available only in the Android build.',
      );
    }
  }

  Future<Uint8List> _invokeBytes(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final response = await _channel.invokeMethod<Object?>(method, arguments);
      if (response is Uint8List) return response;
      throw RutokenNativeException('$method returned an invalid byte array.');
    } on PlatformException catch (error) {
      throw RutokenNativeException(error.message ?? error.code);
    }
  }

  Future<void> _invokeVoid(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      throw RutokenNativeException(error.message ?? error.code);
    } on MissingPluginException {
      // Idempotent teardown: a disappearing engine must not hide the original
      // operation result from the caller.
    }
  }

  Uint8List _bytes(Map<Object?, Object?> response, String key) {
    final value = response[key];
    if (value is Uint8List) return value;
    throw RutokenNativeException("Rutoken response has no '$key' bytes.");
  }

  int _fingerprint(Uint8List compressedPublicKey) {
    final node = bip32.BIP32.fromPublicKey(compressedPublicKey, Uint8List(32));
    return node.fingerprint.buffer.asByteData().getUint32(0);
  }
}

/// Validates PKCS#11's DER OCTET STRING wrapper and normalizes a secp256k1
/// public point without depending on the vendor's presentation details.
class RutokenEcPoint {
  const RutokenEcPoint._({
    required this.compressed,
    required this.uncompressedXY,
  });

  final Uint8List compressed;
  final Uint8List uncompressedXY;

  static RutokenEcPoint decode(Uint8List encoded) {
    final raw = _unwrapOctetString(encoded);
    if (raw.length != 65 || raw.first != 0x04) {
      throw RutokenNativeException(
        'Rutoken EC point must be an uncompressed 65-byte secp256k1 point.',
      );
    }
    final xy = Uint8List.sublistView(raw, 1);
    final compressed = Uint8List(33)
      ..[0] = raw.last.isEven ? 0x02 : 0x03
      ..setRange(1, 33, raw, 1);
    return RutokenEcPoint._(
      compressed: compressed,
      uncompressedXY: Uint8List.fromList(xy),
    );
  }

  static Uint8List _unwrapOctetString(Uint8List encoded) {
    if (encoded.length == 65 && encoded.first == 0x04) return encoded;
    if (encoded.length < 3 || encoded.first != 0x04) {
      throw const RutokenNativeException('Invalid DER EC-point wrapper.');
    }
    var offset = 1;
    var length = encoded[offset++];
    if ((length & 0x80) != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 2 || encoded.length < offset + count) {
        throw const RutokenNativeException('Invalid DER EC-point length.');
      }
      length = 0;
      for (var index = 0; index < count; index++) {
        length = (length << 8) | encoded[offset++];
      }
    }
    if (offset + length != encoded.length) {
      throw const RutokenNativeException('Truncated DER EC point.');
    }
    return Uint8List.sublistView(encoded, offset);
  }
}

class RutokenDerivationPath {
  const RutokenDerivationPath._();

  static List<int> parse(String path) {
    final parts = path.split('/');
    if (parts.isEmpty || parts.first.toLowerCase() != 'm') {
      throw ArgumentError.value(
        path,
        'path',
        "Expected a path starting with 'm'.",
      );
    }
    return parts
        .skip(1)
        .map((part) {
          final hardened = part.endsWith("'") || part.endsWith('h');
          final digits = hardened ? part.substring(0, part.length - 1) : part;
          final index = int.tryParse(digits);
          if (index == null || index < 0 || index >= 0x80000000) {
            throw ArgumentError.value(
              path,
              'path',
              'Invalid BIP-32 component.',
            );
          }
          return hardened ? index | 0x80000000 : index;
        })
        .toList(growable: false);
  }
}
