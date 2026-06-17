import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/airgap/eip4527.dart';
import 'package:web3dart/web3dart.dart' show hexToBytes;

/// Keystone `ur-registry-eth` EthSignRequest test vectors.
///
/// requestId UUID `9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d`, a legacy-tx RLP
/// sign-data, data-type `1`, chain-id `1`, path `M/44'/1'/1'/0/1`,
/// source-fingerprint `0x12345678` (305419896).
const String kRequestId = '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d';
// Legacy-tx RLP `sign-data`. Kept as one literal so the hex isn't accidentally
// corrupted at a line break; it must match the Keystone vector exactly.
const String kSignDataHex =
    'f849808609184e72a00082271094000000000000000000000000000000000000000080a47f7465737432000000000000000000000000000000000000000000000000000000600057808080';
const int kSourceFingerprint = 0x12345678; // 305419896

// The UR vectors are kept as single literals on purpose: splitting a bytewords
// string across adjacent literals is error-prone (a stray pair flips the CRC32
// checksum) and these must match Keystone byte-for-byte.
const String kUrWithOrigin =
    'ur:eth-sign-request/oladtpdagdndcawmgtfrkigrpmndutdnbtkgfssbjnaohdgryagalalnascsgljpnbaelfdibemwaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaelaoxlbjyihjkjyeyaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaehnaehglalalaaxadaaadahtaaddyoeadlecsdwykadykadykaewkadwkaocybgeehfksatisjnihjyhsjnhsjkjetlnndant';

const String kUrWithoutOrigin =
    'ur:eth-sign-request/onadtpdagdndcawmgtfrkigrpmndutdnbtkgfssbjnaohdgryagalalnascsgljpnbaelfdibemwaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaelaoxlbjyihjkjyeyaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaehnaehglalalaaxadaaadahtaaddyoeadlecsdwykadykadykaewkadwkaocybgeehfkswdtklffd';

Uint8List _unhex(String hex) => Uint8List.fromList(hexToBytes(hex));

void main() {
  const codec = Eip4527Codec();

  group('Eip4527Codec.decodeSignRequest (Keystone vector)', () {
    test('decodes every field of the with-origin vector', () {
      final request = codec.decodeSignRequest(kUrWithOrigin);

      expect(request.requestId, kRequestId);
      expect(request.signDataHex, '0x$kSignDataHex');
      expect(request.dataType, EthSignDataType.transaction);
      expect(request.dataType.value, 1);
      expect(request.chainId, 1);
      expect(request.origin, 'metamask');
      expect(request.address, isNull);

      final path = request.derivationPath;
      expect(path.toPathString(), "M/44'/1'/1'/0/1");
      expect(path.components, <PathComponent>[
        (index: 44, hardened: true),
        (index: 1, hardened: true),
        (index: 1, hardened: true),
        (index: 0, hardened: false),
        (index: 1, hardened: false),
      ]);
      expect(path.sourceFingerprint, kSourceFingerprint);
    });

    test('decodes the without-origin vector (origin is null)', () {
      final request = codec.decodeSignRequest(kUrWithoutOrigin);

      expect(request.requestId, kRequestId);
      expect(request.signDataHex, '0x$kSignDataHex');
      expect(request.dataType, EthSignDataType.transaction);
      expect(request.chainId, 1);
      expect(request.origin, isNull);
      expect(request.derivationPath.sourceFingerprint, kSourceFingerprint);
    });
  });

  group('Eip4527Codec.encodeSignRequest (Keystone vector, byte-exact)', () {
    EthSignRequest buildRequest({String? origin}) {
      return EthSignRequest(
        requestId: kRequestId,
        signData: _unhex(kSignDataHex),
        dataType: EthSignDataType.transaction,
        chainId: 1,
        derivationPath: CryptoKeypath.parse(
          "M/44'/1'/1'/0/1",
          sourceFingerprint: kSourceFingerprint,
        ),
        origin: origin,
      );
    }

    test('encodes byte-for-byte equal to the with-origin vector', () {
      expect(
        codec.encodeSignRequest(buildRequest(origin: 'metamask')),
        kUrWithOrigin,
      );
    });

    test('encodes byte-for-byte equal to the without-origin vector', () {
      expect(codec.encodeSignRequest(buildRequest()), kUrWithoutOrigin);
    });

    test('round-trips encode -> decode -> encode', () {
      final request = buildRequest(origin: 'metamask');
      final encoded = codec.encodeSignRequest(request);
      final decoded = codec.decodeSignRequest(encoded);
      expect(codec.encodeSignRequest(decoded), kUrWithOrigin);
    });
  });

  group('Eip4527Codec EthSignature', () {
    test('encode -> decode round-trips a 65-byte signature', () {
      final signatureBytes = Uint8List.fromList(
        List<int>.generate(65, (i) => i),
      );
      final signature = EthSignature(
        requestId: kRequestId,
        signature: signatureBytes,
        origin: 'metamask',
      );

      final ur = codec.encodeSignature(signature);
      expect(ur, startsWith('ur:eth-signature/'));

      final decoded = codec.decodeSignature(ur);
      expect(decoded.requestId, kRequestId);
      expect(decoded.signature, signatureBytes);
      expect(decoded.signature.length, 65);
      expect(decoded.origin, 'metamask');
    });

    test('round-trips with no origin', () {
      final signatureBytes = Uint8List.fromList(
        List<int>.generate(65, (i) => 255 - i),
      );
      final ur = codec.encodeSignature(
        EthSignature(requestId: kRequestId, signature: signatureBytes),
      );
      final decoded = codec.decodeSignature(ur);
      expect(decoded.signature, signatureBytes);
      expect(decoded.origin, isNull);
    });

    test('rejects a signature that is not 65 bytes', () {
      expect(
        () => codec.encodeSignature(
          EthSignature(requestId: kRequestId, signature: Uint8List(64)),
        ),
        throwsA(isA<Eip4527Exception>()),
      );
    });
  });

  group('CryptoKeypath parsing/formatting', () {
    test('parses and reformats canonical paths', () {
      final keypath = CryptoKeypath.parse("m/44'/60'/0'/0/0");
      expect(keypath.toPathString(), "M/44'/60'/0'/0/0");
      expect(keypath.components.first, (index: 44, hardened: true));
      expect(keypath.components.last, (index: 0, hardened: false));
    });

    test('accepts the "h" hardened marker', () {
      final keypath = CryptoKeypath.parse('M/44h/1h');
      expect(keypath.components, <PathComponent>[
        (index: 44, hardened: true),
        (index: 1, hardened: true),
      ]);
    });
  });

  group('Eip4527Codec error handling', () {
    test('throws on a non-UR string', () {
      expect(
        () => codec.decodeSignRequest('not-a-ur'),
        throwsA(isA<Eip4527Exception>()),
      );
    });

    test('throws when the UR type does not match', () {
      expect(
        () => codec.decodeSignature(kUrWithOrigin),
        throwsA(isA<Eip4527Exception>()),
      );
    });
  });
}
