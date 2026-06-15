import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/qr/qr_scanner.dart';

void main() {
  test('UnavailableQrScanner reports unavailable and throws on scan', () async {
    const scanner = UnavailableQrScanner();

    expect(scanner.isAvailable, isFalse);
    await expectLater(scanner.scan(), throwsA(isA<QrScannerException>()));
  });

  test('FakeQrScanner returns its next result and records titles', () async {
    final scanner = FakeQrScanner(nextResult: 'wc:abc@2');

    expect(scanner.isAvailable, isTrue);
    expect(await scanner.scan(title: 'pairing'), 'wc:abc@2');
    expect(scanner.scannedTitles, contains('pairing'));

    scanner.nextResult = null;
    expect(await scanner.scan(), isNull);
  });
}
