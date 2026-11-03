import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_wallet_demo/src/airgap/eip4527.dart';
import 'package:mobile_wallet_demo/src/errors/app_error.dart';
import 'package:mobile_wallet_demo/src/qr/file_qr_scanner.dart';
import 'package:mobile_wallet_demo/src/qr/qr_scanner.dart';
import 'package:mobile_wallet_demo/src/qr/ur_qr.dart';
import 'package:zxing2/qrcode.dart';

class _NullDecoder implements QrImageDecoder {
  const _NullDecoder();

  @override
  String? decode(Uint8List imageBytes) => null;
}

const String _fixtureText = 'wc:9.6demo@2?relay=irn';

const String _urText = 'UR:ETH-SIGN-REQUEST/TEST-PAYLOAD-1234567890';

final String _airGapSinglePart = const Eip4527Codec()
    .encodeSignRequest(
      EthSignRequest(
        requestId: '3b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
        signData: Uint8List.fromList(<int>[0x48, 0x69]),
        dataType: EthSignDataType.rawBytes,
        derivationPath: CryptoKeypath.parse("M/44'/60'/0'/0/0"),
      ),
    )
    .toUpperCase();

/// Draws a QR code of [text] into [image] (8 px modules, 4-module quiet zone)
/// and returns it as PNG bytes, the way an image tool would save it.
Uint8List _qrPng(
  String text,
  img.Image Function(int size) blank,
  img.Color Function(img.Image image, bool dark) colour,
) {
  final matrix = Encoder.encode(text, ErrorCorrectionLevel.m).matrix!;
  const scale = 8;
  const quiet = 4;
  final size = (matrix.width + quiet * 2) * scale;
  final image = blank(size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final mx = x ~/ scale - quiet;
      final my = y ~/ scale - quiet;
      final dark =
          mx >= 0 &&
          my >= 0 &&
          mx < matrix.width &&
          my < matrix.height &&
          matrix.get(mx, my) == 1;
      image.setPixel(x, y, colour(image, dark));
    }
  }
  return img.encodePng(image);
}

/// PNG header fields: bit depth and colour type (IHDR bytes 24 and 25).
(int, int) _pngDepthAndColourType(Uint8List png) => (png[24], png[25]);

void main() {
  Uint8List fixtureBytes() =>
      File('test/fixtures/qr_wc_uri.png').readAsBytesSync();

  test('ZxingQrImageDecoder decodes a wc: URI from a PNG fixture', () {
    final text = const ZxingQrImageDecoder().decode(fixtureBytes());
    expect(text, _fixtureText);
  });

  test('ZxingQrImageDecoder reads a 1-bit greyscale PNG', () {
    final png = _qrPng(
      _urText,
      (size) => img.Image(
        width: size,
        height: size,
        format: img.Format.uint1,
        numChannels: 1,
      ),
      (image, dark) => image.getColor(dark ? 0 : 1, 0, 0),
    );
    // What `qrcode.make()` saves: one bit per pixel, greyscale.
    expect(_pngDepthAndColourType(png), (1, 0));

    expect(const ZxingQrImageDecoder().decode(png), _urText);
  });

  test('ZxingQrImageDecoder reads an 8-bit greyscale PNG', () {
    final png = _qrPng(
      _urText,
      (size) => img.Image(width: size, height: size, numChannels: 1),
      (image, dark) => image.getColor(dark ? 0 : 255, 0, 0),
    );
    expect(_pngDepthAndColourType(png), (8, 0));

    expect(const ZxingQrImageDecoder().decode(png), _urText);
  });

  test('ZxingQrImageDecoder reads dark modules on a transparent PNG', () {
    final png = _qrPng(
      _urText,
      (size) => img.Image(width: size, height: size, numChannels: 4),
      (image, dark) => image.getColor(0, 0, 0, dark ? 255 : 0),
    );
    expect(_pngDepthAndColourType(png), (8, 6));

    expect(const ZxingQrImageDecoder().decode(png), _urText);
  });

  group('loadUrFromFiles', () {
    // A long personal message: its eth-sign-request needs several QR frames.
    final requestUr = const Eip4527Codec().encodeSignRequest(
      EthSignRequest(
        requestId: '4b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
        signData: Uint8List.fromList(
          List<int>.generate(400, (i) => 0x41 + i % 26),
        ),
        dataType: EthSignDataType.rawBytes,
        derivationPath: CryptoKeypath.parse("M/44'/60'/0'/0/0"),
      ),
    );
    final framePngs = <Uint8List>[
      for (final frame in const UrQrEncoder().encode(requestUr))
        _qrPng(
          frame.toUpperCase(),
          (size) => img.Image(width: size, height: size, numChannels: 1),
          (image, dark) => image.getColor(dark ? 0 : 255, 0, 0),
        ),
    ];

    FileQrScanner scanner(List<Uint8List> images) =>
        FileQrScanner(pickManyImageBytes: () async => images);

    test('rebuilds a multipart UR from all its frames, in any order', () async {
      expect(framePngs.length, greaterThan(2));
      final shuffled = <Uint8List>[
        ...framePngs.reversed,
        // A stray image without a QR in the selection does no harm.
        Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8))),
      ];

      final result = await scanner(
        shuffled,
      ).loadUrFromFiles(expectedType: Eip4527Codec.signRequestType);

      expect(result, requestUr);
    });

    test('says how many frames are missing', () async {
      await expectLater(
        scanner(<Uint8List>[
          framePngs.first,
        ]).loadUrFromFiles(expectedType: Eip4527Codec.signRequestType),
        throwsA(
          isA<QrScannerException>()
              .having(
                (error) => error.errorCode,
                'code',
                AppErrorCode.urFramesIncomplete,
              )
              .having((error) => error.errorArgs, 'args', <String, Object>{
                'framesReceived': 1,
                'framesNeeded': framePngs.length,
              }),
        ),
      );
    });

    test('a single-part UR needs one image', () async {
      final png = _qrPng(
        _airGapSinglePart,
        (size) => img.Image(width: size, height: size, numChannels: 1),
        (image, dark) => image.getColor(dark ? 0 : 255, 0, 0),
      );

      expect(
        await scanner(<Uint8List>[png]).loadUrFromFiles(),
        _airGapSinglePart.toLowerCase(),
      );
    });

    test('returns null when the picker is cancelled', () async {
      expect(await scanner(const <Uint8List>[]).loadUrFromFiles(), isNull);
    });
  });

  test('ZxingQrImageDecoder returns null on a non-image input', () {
    final text = const ZxingQrImageDecoder().decode(
      Uint8List.fromList(<int>[0, 1, 2, 3, 4]),
    );
    expect(text, isNull);
  });

  test('FileQrScanner.loadFromFile decodes the picked image', () async {
    final scanner = FileQrScanner(pickImageBytes: () async => fixtureBytes());

    expect(scanner.isFileLoadAvailable, isTrue);
    expect(scanner.isCameraScanAvailable, isFalse);
    expect(await scanner.loadFromFile(), _fixtureText);
  });

  test('FileQrScanner.loadFromFile returns null when cancelled', () async {
    final scanner = FileQrScanner(pickImageBytes: () async => null);
    expect(await scanner.loadFromFile(), isNull);
  });

  test('FileQrScanner.loadFromFile throws when no QR is found', () async {
    final scanner = FileQrScanner(
      decoder: const _NullDecoder(),
      pickImageBytes: () async => Uint8List.fromList(<int>[1, 2, 3]),
    );
    await expectLater(
      scanner.loadFromFile(),
      throwsA(isA<QrScannerException>()),
    );
  });

  test('FileQrScanner.scanWithCamera is deferred', () async {
    final scanner = FileQrScanner(pickImageBytes: () async => null);
    await expectLater(
      scanner.scanWithCamera(),
      throwsA(isA<QrScannerException>()),
    );
  });
}
