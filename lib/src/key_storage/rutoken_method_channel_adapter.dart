import 'package:flutter/services.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
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
  ) async {
    final response = await _invokeMap(
      'readAccountDescriptor',
      <String, Object?>{'sessionId': session.id},
    );
    final address = RutokenEcPoint.decode(_bytes(response, 'addressPublicKey'));
    return WalletAccountDescriptor(
      backendId: 'rutoken_nfc',
      address: '0x${bytesToHex(publicKeyToAddress(address.uncompressedXY))}',
      derivationPath: addressPath,
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
}

/// Validates PKCS#11's optional DER OCTET STRING wrapper and normalizes either
/// compressed or uncompressed SEC1 secp256k1 public points.
class RutokenEcPoint {
  const RutokenEcPoint._({
    required this.compressed,
    required this.uncompressedXY,
  });

  final Uint8List compressed;
  final Uint8List uncompressedXY;

  static RutokenEcPoint decode(Uint8List encoded) {
    final raw = _unwrapOctetString(encoded);
    if (!_isCompressed(raw) && !_isUncompressed(raw)) {
      throw RutokenNativeException(
        'Rutoken EC point has unsupported SEC1 encoding '
        '(${raw.length} bytes, prefix ${_prefix(raw)}).',
      );
    }

    Uint8List compressed;
    Uint8List uncompressed;
    try {
      final point = ECCurve_secp256k1().curve.decodePoint(raw);
      if (point == null || point.isInfinity) {
        throw const FormatException('Point is not on secp256k1.');
      }
      compressed = Uint8List.fromList(point.getEncoded(true));
      uncompressed = Uint8List.fromList(point.getEncoded(false));
    } catch (_) {
      throw const RutokenNativeException(
        'Rutoken EC point is not a valid secp256k1 public key.',
      );
    }

    if (!_isCompressed(compressed) || !_isUncompressed(uncompressed)) {
      throw const RutokenNativeException(
        'Rutoken EC point normalization returned an invalid secp256k1 key.',
      );
    }
    return RutokenEcPoint._(
      compressed: compressed,
      uncompressedXY: Uint8List.sublistView(uncompressed, 1),
    );
  }

  static Uint8List _unwrapOctetString(Uint8List encoded) {
    if (_isCompressed(encoded) || _isUncompressed(encoded)) return encoded;
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

  static bool _isCompressed(Uint8List value) =>
      value.length == 33 && (value.first == 0x02 || value.first == 0x03);

  static bool _isUncompressed(Uint8List value) =>
      value.length == 65 && value.first == 0x04;

  static String _prefix(Uint8List value) => value.isEmpty
      ? 'none'
      : '0x${value.first.toRadixString(16).padLeft(2, '0')}';
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
