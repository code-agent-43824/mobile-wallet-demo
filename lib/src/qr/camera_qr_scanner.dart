import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'file_qr_scanner.dart';
import 'qr_scanner.dart';

/// Production [QrScanner] on Android/iOS: live **camera** QR scanning via
/// `mobile_scanner` (Apple Vision on iOS, ML Kit on Android), with **file**
/// loading delegated to a composed [FileQrScanner] so both sources work and the
/// pure-Dart file decode isn't duplicated.
///
/// `mobile_scanner` declares android/ios/macos/web only — on Windows x64 the DI
/// keeps a plain [FileQrScanner] (camera unavailable), so this class is never
/// instantiated there. Its Dart still compiles on every platform (the 9.9a CI
/// probe confirmed the native side builds/excludes cleanly).
///
/// [scanWithCamera] takes no `BuildContext` (the seam is UI-agnostic), so it
/// pushes the scanner route through the global [navigatorKey] installed on the
/// app's `MaterialApp`.
class CameraQrScanner implements QrScanner {
  CameraQrScanner({
    required GlobalKey<NavigatorState> navigatorKey,
    QrScanner? fileDelegate,
  }) : _navigatorKey = navigatorKey,
       _fileDelegate = fileDelegate ?? FileQrScanner();

  final GlobalKey<NavigatorState> _navigatorKey;
  final QrScanner _fileDelegate;

  @override
  bool get isCameraScanAvailable => true;

  @override
  bool get isFileLoadAvailable => _fileDelegate.isFileLoadAvailable;

  @override
  Future<String?> scanWithCamera({String title = ''}) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      throw const QrScannerException(
        'Не удалось открыть камеру: навигатор недоступен.',
      );
    }
    return navigator.push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (context) => _CameraScannerScreen(title: title),
      ),
    );
  }

  @override
  Future<String?> loadFromFile() => _fileDelegate.loadFromFile();
}

/// Full-screen camera scanner. Pops with the first decoded QR text, or null
/// when the user backs out (the AppBar back button).
class _CameraScannerScreen extends StatefulWidget {
  const _CameraScannerScreen({required this.title});

  /// Short label for what's being scanned (e.g. `wc: URI`), shown as a hint.
  final String title;

  @override
  State<_CameraScannerScreen> createState() => _CameraScannerScreenState();
}

class _CameraScannerScreenState extends State<_CameraScannerScreen> {
  // QR only + noDuplicates: scan a single code, ignore other barcode types.
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) {
      return; // already popping for the first detected code
    }
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.title.isEmpty
        ? 'Наведите камеру на QR-код'
        : 'Наведите камеру на QR-код (${widget.title})';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Сканирование QR')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Не удалось открыть камеру. Проверьте разрешение на доступ к '
                  'камере или используйте загрузку QR из файла.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(hint, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
