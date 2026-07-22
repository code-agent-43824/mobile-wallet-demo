import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_wallet_demo/src/qr/camera_qr_scanner.dart';
import 'package:mobile_wallet_demo/src/qr/qr_scanner.dart';

void main() {
  // GlobalKey.currentState reads WidgetsBinding.instance; initialise the test
  // binding so the unmounted-navigator path behaves like production (runApp
  // always initialises the binding).
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CameraQrScanner', () {
    test('uses dense-QR camera settings without a low-resolution stream', () {
      final controller = createCameraQrScannerController();
      addTearDown(controller.dispose);

      expect(controller.formats, const <BarcodeFormat>[BarcodeFormat.qrCode]);
      expect(controller.detectionSpeed, DetectionSpeed.noDuplicates);
      expect(controller.cameraResolution, const Size(1920, 1080));
      expect(controller.autoZoom, isTrue);
    });

    test('reports camera available and mirrors the file delegate', () {
      final scanner = CameraQrScanner(
        navigatorKey: GlobalKey<NavigatorState>(),
        fileDelegate: FakeQrScanner(),
      );
      expect(scanner.isCameraScanAvailable, isTrue);
      expect(scanner.isFileLoadAvailable, isTrue);
    });

    test('isFileLoadAvailable follows the delegate when unavailable', () {
      final scanner = CameraQrScanner(
        navigatorKey: GlobalKey<NavigatorState>(),
        fileDelegate: FakeQrScanner(fileLoadAvailable: false),
      );
      expect(scanner.isFileLoadAvailable, isFalse);
    });

    test('loadFromFile delegates to the file scanner', () async {
      final delegate = FakeQrScanner(nextResult: 'wc:delegated@2');
      final scanner = CameraQrScanner(
        navigatorKey: GlobalKey<NavigatorState>(),
        fileDelegate: delegate,
      );

      final result = await scanner.loadFromFile();

      expect(result, 'wc:delegated@2');
      expect(delegate.events, contains('file'));
    });

    test('scanWithCamera throws when the navigator is not mounted', () async {
      final scanner = CameraQrScanner(
        // A fresh key never attached to a Navigator → currentState is null.
        navigatorKey: GlobalKey<NavigatorState>(),
        fileDelegate: FakeQrScanner(),
      );

      await expectLater(
        () => scanner.scanWithCamera(title: 'wc: URI'),
        throwsA(isA<QrScannerException>()),
      );
      await expectLater(
        () => scanner.scanUrWithCamera(
          title: 'request',
          expectedType: 'eth-sign-request',
        ),
        throwsA(isA<QrScannerException>()),
      );
    });
  });
}
