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

/// A `crypto-coininfo` (BC-UR tag 305): a `crypto-hdkey`'s `use-info` (CDDL key
/// 5) — the SLIP-44 coin [type] (60 for Ethereum) and [network].
class CoinInfo {
  const CoinInfo({this.type = 60, this.network = 0});

  /// SLIP-44 coin type (CDDL key `1`; the CBOR default when absent is `0` =
  /// Bitcoin). Ethereum is `60`.
  final int type;

  /// Network (CDDL key `2`, default `0` = mainnet).
  final int network;
}

/// A `crypto-hdkey` (UR type `crypto-hdkey`, BC-UR tag 303): a BIP-32 extended
/// key. For account export (pairing) this is a **derived public** key — the
/// account-level node's compressed pubkey ([keyData]) + [chainCode] + the
/// derivation [origin] and [parentFingerprint] — which an online wallet
/// (MetaMask) imports watch-only and then derives addresses from.
class CryptoHDKey {
  const CryptoHDKey({
    required this.keyData,
    this.chainCode,
    this.isMaster = false,
    this.isPrivate = false,
    this.useInfo,
    this.origin,
    this.children,
    this.parentFingerprint,
    this.name,
    this.note,
  });

  /// `is-master` (CDDL key `1`): `true` only for the master node. Omitted from
  /// the encoding for derived keys (the CBOR default is `false`).
  final bool isMaster;

  /// `is-private` (CDDL key `2`): `true` if [keyData] is a private key. Omitted
  /// for public keys (the default). Always `false`/omitted for an export.
  final bool isPrivate;

  /// `key-data` (CDDL key `3`): the 33-byte compressed SEC1 public key (or, if
  /// [isPrivate], `0x00 ‖ 32-byte private key`).
  final Uint8List keyData;

  /// `chain-code` (CDDL key `4`): the 32-byte BIP-32 chain code, if present.
  final Uint8List? chainCode;

  /// `use-info` (CDDL key `5`): the coin/network this key is for.
  final CoinInfo? useInfo;

  /// `origin` (CDDL key `6`): the derivation path from the master to this key
  /// (with the master's `source-fingerprint`), e.g. `M/44'/60'/0'`.
  final CryptoKeypath? origin;

  /// `children` (CDDL key `7`): the path pattern for this key's children, e.g.
  /// `0/*`, telling the importer how to derive addresses.
  final CryptoKeypath? children;

  /// `parent-fingerprint` (CDDL key `8`): the 32-bit fingerprint of this key's
  /// immediate parent node.
  final int? parentFingerprint;

  /// `name` (CDDL key `9`): a human-readable label, if any.
  final String? name;

  /// `note` (CDDL key `10`): free-form note. Keystone uses it to signal the
  /// derivation scheme (e.g. `account.standard`).
  final String? note;

  /// [keyData] as a `0x`-prefixed hex string.
  String get keyDataHex => bytesToHex(keyData, include0x: true);
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
  static const String hdKeyType = 'crypto-hdkey';

  static const int _uuidTag = 37;
  static const int _keypathTag = 304;
  static const int _coinInfoTag = 305;

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

  /// Encodes a [CryptoHDKey] into an `ur:crypto-hdkey/...` string.
  ///
  /// Top-level UR: the CBOR map is emitted **without** the `crypto-hdkey` tag
  /// (303) — the UR type string carries the type. Keys are emitted in ascending
  /// order; optional fields (and `is-master`/`is-private` when false) are
  /// omitted, matching the Keystone encoder.
  String encodeHdKey(CryptoHDKey key) {
    final entries = <CborValue, CborValue>{};
    if (key.isMaster) {
      entries[const CborSmallInt(1)] = const CborBool(true);
    }
    if (key.isPrivate) {
      entries[const CborSmallInt(2)] = const CborBool(true);
    }
    entries[const CborSmallInt(3)] = CborBytes(key.keyData);
    if (key.chainCode != null) {
      entries[const CborSmallInt(4)] = CborBytes(key.chainCode!);
    }
    if (key.useInfo != null) {
      entries[const CborSmallInt(5)] = _coinInfoToValue(key.useInfo!);
    }
    if (key.origin != null) {
      entries[const CborSmallInt(6)] = _keypathToValue(key.origin!);
    }
    if (key.children != null) {
      entries[const CborSmallInt(7)] = _keypathToValue(key.children!);
    }
    if (key.parentFingerprint != null) {
      entries[const CborSmallInt(8)] = CborSmallInt(key.parentFingerprint!);
    }
    if (key.name != null) {
      entries[const CborSmallInt(9)] = CborString(key.name!);
    }
    if (key.note != null) {
      entries[const CborSmallInt(10)] = CborString(key.note!);
    }
    return _encodeMap(CborMap(entries), hdKeyType);
  }

  /// Decodes an `ur:crypto-hdkey/...` string into a [CryptoHDKey].
  CryptoHDKey decodeHdKey(String ur) {
    final map = _decodeMap(ur, hdKeyType);

    final isMasterValue = map[const CborSmallInt(1)];
    final isMaster = isMasterValue is CborBool ? isMasterValue.value : false;
    final isPrivateValue = map[const CborSmallInt(2)];
    final isPrivate = isPrivateValue is CborBool ? isPrivateValue.value : false;

    final keyData = _bytes(_required(map, 3, 'key-data'), 'key-data');

    final chainCodeValue = map[const CborSmallInt(4)];
    final chainCode = chainCodeValue == null
        ? null
        : _bytes(chainCodeValue, 'chain-code');

    final useInfoValue = map[const CborSmallInt(5)];
    final useInfo = useInfoValue == null
        ? null
        : _coinInfoFromValue(useInfoValue);

    final originValue = map[const CborSmallInt(6)];
    final origin = originValue == null ? null : _keypathFromValue(originValue);

    final childrenValue = map[const CborSmallInt(7)];
    final children = childrenValue == null
        ? null
        : _keypathFromValue(childrenValue);

    final parentFingerprintValue = map[const CborSmallInt(8)];
    final parentFingerprint = parentFingerprintValue == null
        ? null
        : _int(parentFingerprintValue, 'parent-fingerprint');

    final nameValue = map[const CborSmallInt(9)];
    final name = nameValue == null ? null : _string(nameValue, 'name');

    final noteValue = map[const CborSmallInt(10)];
    final note = noteValue == null ? null : _string(noteValue, 'note');

    return CryptoHDKey(
      keyData: keyData,
      chainCode: chainCode,
      isMaster: isMaster,
      isPrivate: isPrivate,
      useInfo: useInfo,
      origin: origin,
      children: children,
      parentFingerprint: parentFingerprint,
      name: name,
      note: note,
    );
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

  CborValue _coinInfoToValue(CoinInfo info) {
    // Omit fields at their CDDL default (type 0, network 0) for the canonical
    // minimal encoding.
    final entries = <CborValue, CborValue>{};
    if (info.type != 0) {
      entries[const CborSmallInt(1)] = CborSmallInt(info.type);
    }
    if (info.network != 0) {
      entries[const CborSmallInt(2)] = CborSmallInt(info.network);
    }
    return CborMap(entries, tags: const [_coinInfoTag]);
  }

  CoinInfo _coinInfoFromValue(CborValue value) {
    if (value is! CborMap || !value.tags.contains(_coinInfoTag)) {
      throw Eip4527Exception(
        'use-info must be a crypto-coininfo (CBOR tag $_coinInfoTag).',
      );
    }
    final typeValue = value[const CborSmallInt(1)];
    final networkValue = value[const CborSmallInt(2)];
    return CoinInfo(
      type: typeValue == null ? 0 : _int(typeValue, 'coin-type'),
      network: networkValue == null ? 0 : _int(networkValue, 'coin-network'),
    );
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
