import 'dart:typed_data';

import 'package:bc_ur/bc_ur.dart';
import 'package:cbor/cbor.dart';
import 'package:web3dart/web3dart.dart' show bytesToHex, hexToBytes;

/// Thrown when an EIP-4527 / BC-UR payload (or one of its fields) is malformed.
class Eip4527Exception implements Exception {
  const Eip4527Exception(this.message);

  final String message;

  @override
  String toString() => 'Eip4527Exception: $message';
}

/// What the `sign-data` bytes of an [EthSignRequest] represent (CDDL key `3`).
///
/// The `value` is the on-the-wire integer per EIP-4527.
enum EthSignDataType {
  /// Legacy (pre-EIP-2718) RLP-encoded transaction.
  transaction(1),

  /// EIP-712 typed structured data.
  typedData(2),

  /// Raw bytes — i.e. `personal_sign` / EIP-191.
  rawBytes(3),

  /// EIP-2718 typed transaction (includes EIP-1559).
  typedTransaction(4);

  const EthSignDataType(this.value);

  /// The integer encoded under CDDL key `3`.
  final int value;

  /// Maps an on-the-wire integer to its [EthSignDataType].
  static EthSignDataType fromValue(int value) {
    for (final type in EthSignDataType.values) {
      if (type.value == value) {
        return type;
      }
    }
    throw Eip4527Exception('Unknown eth-sign-request data-type: $value.');
  }
}

/// A single level of a BIP-32 derivation path: a child [index] and whether it
/// is [hardened].
typedef PathComponent = ({int index, bool hardened});

/// A `crypto-keypath` (BC-UR tag 304): the BIP-32 derivation path the signer
/// should use, plus the optional master-key [sourceFingerprint] and [depth].
class CryptoKeypath {
  const CryptoKeypath({
    required this.components,
    this.sourceFingerprint,
    this.depth,
  });

  /// Parses a textual path such as `M/44'/1'/1'/0/1` (a leading `m`/`M` is
  /// optional; `'` or `h`/`H` mark a hardened level).
  factory CryptoKeypath.parse(
    String path, {
    int? sourceFingerprint,
    int? depth,
  }) {
    var trimmed = path.trim();
    if (trimmed.startsWith('m') || trimmed.startsWith('M')) {
      trimmed = trimmed.substring(1);
    }
    if (trimmed.startsWith('/')) {
      trimmed = trimmed.substring(1);
    }
    final components = <PathComponent>[];
    if (trimmed.isNotEmpty) {
      for (final raw in trimmed.split('/')) {
        final segment = raw.trim();
        if (segment.isEmpty) {
          throw Eip4527Exception('Empty path component in "$path".');
        }
        final hardened =
            segment.endsWith("'") ||
            segment.endsWith('h') ||
            segment.endsWith('H');
        final digits = hardened
            ? segment.substring(0, segment.length - 1)
            : segment;
        final index = int.tryParse(digits);
        if (index == null || index < 0) {
          throw Eip4527Exception('Invalid path component "$segment".');
        }
        components.add((index: index, hardened: hardened));
      }
    }
    return CryptoKeypath(
      components: components,
      sourceFingerprint: sourceFingerprint,
      depth: depth,
    );
  }

  /// The ordered derivation levels.
  final List<PathComponent> components;

  /// The 32-bit fingerprint of the master key (CDDL key `2`), if known.
  final int? sourceFingerprint;

  /// The depth of the path (CDDL key `3`), if provided.
  final int? depth;

  /// Renders the path in canonical text form, e.g. `M/44'/1'/1'/0/1`.
  String toPathString() {
    final buffer = StringBuffer('M');
    for (final component in components) {
      buffer.write('/');
      buffer.write(component.index);
      if (component.hardened) {
        buffer.write("'");
      }
    }
    return buffer.toString();
  }

  @override
  String toString() => toPathString();
}

/// An EIP-4527 `eth-sign-request` (UR type `eth-sign-request`): the unsigned
/// payload a watch-only wallet hands to an offline signer.
class EthSignRequest {
  const EthSignRequest({
    required this.requestId,
    required this.signData,
    required this.dataType,
    required this.derivationPath,
    this.chainId = 1,
    this.address,
    this.origin,
  });

  /// The request UUID in canonical text form (e.g.
  /// `9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d`).
  final String requestId;

  /// The unsigned payload to sign; meaning is set by [dataType].
  final Uint8List signData;

  /// What [signData] represents.
  final EthSignDataType dataType;

  /// The EVM chain id (CDDL key `4`, default `1`).
  final int chainId;

  /// The derivation path (and optional fingerprint/depth) for the signer.
  final CryptoKeypath derivationPath;

  /// The 20-byte account address (CDDL key `6`), if the wallet pinned one.
  final Uint8List? address;

  /// The requesting dApp's origin (CDDL key `7`), e.g. `metamask`.
  final String? origin;

  /// [signData] as a `0x`-prefixed hex string.
  String get signDataHex => bytesToHex(signData, include0x: true);

  /// [address] as a `0x`-prefixed hex string, or `null` when absent.
  String? get addressHex =>
      address == null ? null : bytesToHex(address!, include0x: true);
}

/// An EIP-4527 `eth-signature` (UR type `eth-signature`): the signer's reply.
class EthSignature {
  const EthSignature({
    required this.requestId,
    required this.signature,
    this.origin,
  });

  /// The UUID echoed from the matching [EthSignRequest].
  final String requestId;

  /// The 65-byte signature `r‖s‖v`.
  final Uint8List signature;

  /// The signer's origin (CDDL key `3`), if any.
  final String? origin;

  /// [signature] as a `0x`-prefixed hex string.
  String get signatureHex => bytesToHex(signature, include0x: true);
}

/// Pure-Dart codec for the EIP-4527 / Keystone BC-UR air-gapped protocol.
///
/// Encodes/decodes `eth-sign-request` and `eth-signature` UR strings — the CBOR
/// (RFC-8949) map is built/parsed with the `cbor` package (tag 37 for the
/// request-id UUID, tag 304 for the `crypto-keypath`) and wrapped/unwrapped as a
/// single-part `ur:<type>/<bytewords>` string with the `bc_ur` package.
/// No relay, SDK, signing, or QR handling lives here — just the wire format.
class Eip4527Codec {
  const Eip4527Codec();

  static const String signRequestType = 'eth-sign-request';
  static const String signatureType = 'eth-signature';

  static const int _uuidTag = 37;
  static const int _keypathTag = 304;

  /// Decodes an `ur:eth-sign-request/...` string into an [EthSignRequest].
  EthSignRequest decodeSignRequest(String ur) {
    final map = _decodeMap(ur, signRequestType);

    final requestId = _uuidFromValue(
      _required(map, 1, 'request-id'),
      'request-id',
    );
    final signData = _bytes(_required(map, 2, 'sign-data'), 'sign-data');
    final dataType = EthSignDataType.fromValue(
      _int(_required(map, 3, 'data-type'), 'data-type'),
    );
    final chainValue = map[const CborSmallInt(4)];
    final chainId = chainValue == null ? 1 : _int(chainValue, 'chain-id');
    final derivationPath = _keypathFromValue(
      _required(map, 5, 'derivation-path'),
    );

    final addressValue = map[const CborSmallInt(6)];
    final address = addressValue == null
        ? null
        : _bytes(addressValue, 'address');

    final originValue = map[const CborSmallInt(7)];
    final origin = originValue == null ? null : _string(originValue, 'origin');

    return EthSignRequest(
      requestId: requestId,
      signData: signData,
      dataType: dataType,
      chainId: chainId,
      derivationPath: derivationPath,
      address: address,
      origin: origin,
    );
  }

  /// Encodes an [EthSignRequest] into an `ur:eth-sign-request/...` string.
  ///
  /// CBOR map keys are emitted in ascending order (1,2,3,4,5,[6],[7]); this
  /// matches the Keystone reference vectors byte-for-byte.
  String encodeSignRequest(EthSignRequest request) {
    final entries = <CborValue, CborValue>{
      const CborSmallInt(1): _uuidToValue(request.requestId),
      const CborSmallInt(2): CborBytes(request.signData),
      const CborSmallInt(3): CborSmallInt(request.dataType.value),
      const CborSmallInt(4): CborSmallInt(request.chainId),
      const CborSmallInt(5): _keypathToValue(request.derivationPath),
    };
    if (request.address != null) {
      entries[const CborSmallInt(6)] = CborBytes(request.address!);
    }
    if (request.origin != null) {
      entries[const CborSmallInt(7)] = CborString(request.origin!);
    }
    return _encodeMap(CborMap(entries), signRequestType);
  }

  /// Decodes an `ur:eth-signature/...` string into an [EthSignature].
  EthSignature decodeSignature(String ur) {
    final map = _decodeMap(ur, signatureType);

    final requestId = _uuidFromValue(
      _required(map, 1, 'request-id'),
      'request-id',
    );
    final signature = _bytes(_required(map, 2, 'signature'), 'signature');
    if (signature.length != 65) {
      throw Eip4527Exception(
        'eth-signature signature must be 65 bytes, got ${signature.length}.',
      );
    }
    final originValue = map[const CborSmallInt(3)];
    final origin = originValue == null ? null : _string(originValue, 'origin');

    return EthSignature(
      requestId: requestId,
      signature: signature,
      origin: origin,
    );
  }

  /// Encodes an [EthSignature] into an `ur:eth-signature/...` string.
  String encodeSignature(EthSignature signature) {
    if (signature.signature.length != 65) {
      throw Eip4527Exception(
        'eth-signature signature must be 65 bytes, got '
        '${signature.signature.length}.',
      );
    }
    final entries = <CborValue, CborValue>{
      const CborSmallInt(1): _uuidToValue(signature.requestId),
      const CborSmallInt(2): CborBytes(signature.signature),
    };
    if (signature.origin != null) {
      entries[const CborSmallInt(3)] = CborString(signature.origin!);
    }
    return _encodeMap(CborMap(entries), signatureType);
  }

  // --- UR <-> CBOR map plumbing -------------------------------------------

  CborMap _decodeMap(String ur, String expectedType) {
    final BCUR bcur;
    try {
      bcur = BCUR.fromString(ur.trim());
    } catch (error) {
      throw Eip4527Exception('Malformed UR string: $error');
    }
    if (bcur.type != expectedType) {
      throw Eip4527Exception(
        'Expected a "$expectedType" UR but got "${bcur.type}".',
      );
    }
    final CborValue decoded;
    try {
      decoded = cbor.decode(bcur.getCbor());
    } catch (error) {
      throw Eip4527Exception('Malformed CBOR payload: $error');
    }
    if (decoded is! CborMap) {
      throw Eip4527Exception('Expected a CBOR map at the top level.');
    }
    return decoded;
  }

  String _encodeMap(CborMap map, String type) {
    final bytes = Uint8List.fromList(cbor.encode(map));
    return BCUR.fromCbor(type, bytes).toString();
  }

  // --- CBOR field helpers --------------------------------------------------

  CborValue _required(CborMap map, int key, String name) {
    final value = map[CborSmallInt(key)];
    if (value == null) {
      throw Eip4527Exception('Missing required field "$name" (key $key).');
    }
    return value;
  }

  int _int(CborValue value, String name) {
    if (value is CborInt) {
      return value.toInt();
    }
    throw Eip4527Exception('Field "$name" must be an integer.');
  }

  Uint8List _bytes(CborValue value, String name) {
    if (value is CborBytes) {
      return Uint8List.fromList(value.bytes);
    }
    throw Eip4527Exception('Field "$name" must be a byte string.');
  }

  String _string(CborValue value, String name) {
    if (value is CborString) {
      return value.toString();
    }
    throw Eip4527Exception('Field "$name" must be a text string.');
  }

  CryptoKeypath _keypathFromValue(CborValue value) {
    if (value is! CborMap || !value.tags.contains(_keypathTag)) {
      throw Eip4527Exception(
        'derivation-path must be a crypto-keypath (CBOR tag $_keypathTag).',
      );
    }
    final componentsValue = _required(value, 1, 'keypath components');
    if (componentsValue is! CborList) {
      throw const Eip4527Exception('crypto-keypath components must be a list.');
    }
    if (componentsValue.length.isOdd) {
      throw const Eip4527Exception(
        'crypto-keypath components must be index/hardened pairs.',
      );
    }
    final components = <PathComponent>[];
    for (var i = 0; i < componentsValue.length; i += 2) {
      final indexValue = componentsValue[i];
      final hardenedValue = componentsValue[i + 1];
      if (indexValue is! CborInt || hardenedValue is! CborBool) {
        throw const Eip4527Exception(
          'crypto-keypath components must be [int, bool, ...].',
        );
      }
      components.add((
        index: indexValue.toInt(),
        hardened: hardenedValue.value,
      ));
    }
    final fingerprintValue = value[const CborSmallInt(2)];
    final depthValue = value[const CborSmallInt(3)];
    return CryptoKeypath(
      components: components,
      sourceFingerprint: fingerprintValue == null
          ? null
          : _int(fingerprintValue, 'source-fingerprint'),
      depth: depthValue == null ? null : _int(depthValue, 'depth'),
    );
  }

  CborValue _keypathToValue(CryptoKeypath keypath) {
    final components = <CborValue>[];
    for (final component in keypath.components) {
      components
        ..add(CborSmallInt(component.index))
        ..add(CborBool(component.hardened));
    }
    final entries = <CborValue, CborValue>{
      const CborSmallInt(1): CborList(components),
    };
    if (keypath.sourceFingerprint != null) {
      entries[const CborSmallInt(2)] = CborSmallInt(keypath.sourceFingerprint!);
    }
    if (keypath.depth != null) {
      entries[const CborSmallInt(3)] = CborSmallInt(keypath.depth!);
    }
    return CborMap(entries, tags: const [_keypathTag]);
  }

  // --- UUID <-> tag-37 16-byte bstr ---------------------------------------

  CborValue _uuidToValue(String uuid) {
    return CborBytes(_uuidToBytes(uuid), tags: const [_uuidTag]);
  }

  String _uuidFromValue(CborValue value, String name) {
    if (value is! CborBytes || !value.tags.contains(_uuidTag)) {
      throw Eip4527Exception(
        'Field "$name" must be a UUID (CBOR tag $_uuidTag).',
      );
    }
    return _uuidFromBytes(Uint8List.fromList(value.bytes));
  }

  Uint8List _uuidToBytes(String uuid) {
    final normalized = uuid.replaceAll('-', '').trim();
    if (normalized.length != 32) {
      throw Eip4527Exception('Invalid UUID "$uuid" (expected 32 hex digits).');
    }
    try {
      return Uint8List.fromList(hexToBytes(normalized));
    } catch (_) {
      throw Eip4527Exception('Invalid UUID "$uuid".');
    }
  }

  String _uuidFromBytes(Uint8List bytes) {
    if (bytes.length != 16) {
      throw Eip4527Exception('A UUID must be 16 bytes, got ${bytes.length}.');
    }
    final hex = bytesToHex(bytes);
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
