import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/key_storage/rutoken_method_channel_adapter.dart';
import 'package:web3dart/web3dart.dart' show hexToBytes;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('wallet_demo/rutoken');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('normalizes uncompressed DER EC point and hardened BIP32 path', () {
    final raw = _generatorPoint();
    final point = RutokenEcPoint.decode(
      Uint8List.fromList(<int>[0x04, raw.length, ...raw]),
    );

    expect(point.compressed.length, 33);
    expect(point.compressed.first, 0x02);
    expect(point.uncompressedXY, raw.sublist(1));
    expect(RutokenDerivationPath.parse("m/44'/60'/0'/0/0"), <int>[
      0x8000002c,
      0x8000003c,
      0x80000000,
      0,
      0,
    ]);
  });

  test('normalizes raw and DER-wrapped compressed secp256k1 points', () {
    final uncompressed = _generatorPoint();
    final compressed = Uint8List.fromList(<int>[
      0x02,
      ...uncompressed.sublist(1, 33),
    ]);

    for (final encoded in <Uint8List>[
      compressed,
      Uint8List.fromList(<int>[0x04, compressed.length, ...compressed]),
    ]) {
      final point = RutokenEcPoint.decode(encoded);
      expect(point.compressed, compressed);
      expect(point.uncompressedXY, uncompressed.sublist(1));
    }
  });

  test('rejects compressed bytes that are not a secp256k1 point', () {
    final invalid = Uint8List.fromList(<int>[
      0x02,
      ...List<int>.filled(32, 0xff),
    ]);

    expect(
      () => RutokenEcPoint.decode(invalid),
      throwsA(
        isA<RutokenNativeException>().having(
          (error) => error.message,
          'message',
          contains('not a valid secp256k1 public key'),
        ),
      ),
    );
  });

  test(
    'platform adapter keeps session opaque and requests raw EVM digest',
    () async {
      final calls = <MethodCall>[];
      final raw = _generatorPoint();
      final derPoint = Uint8List.fromList(<int>[0x04, raw.length, ...raw]);
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'openSession':
            return <String, Object?>{'sessionId': 'native-1'};
          case 'readAccountDescriptor':
            return <String, Object?>{'addressPublicKey': derPoint};
          case 'signDigest':
            return Uint8List.fromList(List<int>.generate(64, (index) => index));
          case 'closeSession':
            return null;
        }
        throw MissingPluginException(call.method);
      });

      final adapter = MethodChannelRutokenNativeAdapter(channel: channel);
      final session = await adapter.openSession(pin: '12345678');
      final account = await adapter.readAccountDescriptor(session);
      final signature = await adapter.signDigest(
        session: session,
        derivationPath: MethodChannelRutokenNativeAdapter.addressPath,
        digest: Uint8List.fromList(List<int>.generate(32, (index) => index)),
      );
      await adapter.closeSession(session);

      expect(session.id, 'native-1');
      expect(account?.address, hasLength(42));
      expect(signature.toBytes(), List<int>.generate(64, (index) => index));
      expect(calls.map((call) => call.method), <String>[
        'openSession',
        'readAccountDescriptor',
        'signDigest',
        'closeSession',
      ]);
      final signArguments = calls[2].arguments as Map<Object?, Object?>;
      expect(signArguments['derivationPath'], <int>[
        0x8000002c,
        0x8000003c,
        0x80000000,
        0,
        0,
      ]);
      expect(signArguments['digest'], hasLength(32));

      expect(calls, hasLength(4));
    },
  );
}

Uint8List _generatorPoint() => Uint8List.fromList(
  hexToBytes(
    '0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798'
    '483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8',
  ),
);
