import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/qr/file_qr_scanner.dart';
import 'package:mobile_wallet_demo/src/qr/qr_scanner.dart';

class _NullDecoder implements QrImageDecoder {
  const _NullDecoder();

  @override
  String? decode(Uint8List imageBytes) => null;
}

const String _fixtureText = 'wc:9.6demo@2?relay=irn';

void main() {
  Uint8List fixtureBytes() =>
      File('test/fixtures/qr_wc_uri.png').readAsBytesSync();

  test('ZxingQrImageDecoder decodes a wc: URI from a PNG fixture', () {
    final text = const ZxingQrImageDecoder().decode(fixtureBytes());
    expect(text, _fixtureText);
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
