import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/qr/qr_scanner.dart';

void main() {
  test('UnavailableQrScanner reports nothing available and throws', () async {
    const scanner = UnavailableQrScanner();

    expect(scanner.isCameraScanAvailable, isFalse);
    expect(scanner.isFileLoadAvailable, isFalse);
    await expectLater(
      scanner.scanWithCamera(),
      throwsA(isA<QrScannerException>()),
    );
    await expectLater(
      scanner.loadFromFile(),
      throwsA(isA<QrScannerException>()),
    );
  });

  test('FakeQrScanner returns its next result and records events', () async {
    final scanner = FakeQrScanner(nextResult: 'wc:abc@2');

    expect(scanner.isCameraScanAvailable, isTrue);
    expect(scanner.isFileLoadAvailable, isTrue);
    expect(await scanner.scanWithCamera(title: 'pairing'), 'wc:abc@2');
    expect(await scanner.loadFromFile(), 'wc:abc@2');
    expect(scanner.events, <String>['camera:pairing', 'file']);

    scanner.nextResult = null;
    expect(await scanner.loadFromFile(), isNull);
  });
}
