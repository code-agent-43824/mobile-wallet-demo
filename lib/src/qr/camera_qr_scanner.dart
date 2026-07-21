import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'file_qr_scanner.dart';
import 'qr_scanner.dart';
import 'ur_qr.dart';

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
  Future<String?> scanUrWithCamera({
    String title = '',
    String? expectedType,
  }) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      throw const QrScannerException(
        'Не удалось открыть камеру: навигатор недоступен.',
      );
    }
    return navigator.push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (context) =>
            _CameraScannerScreen(title: title, expectedUrType: expectedType),
      ),
    );
  }

  @override
  Future<String?> loadFromFile() => _fileDelegate.loadFromFile();
}

/// Full-screen camera scanner. Pops with the first decoded QR text, or null
/// when the user backs out (the AppBar back button).
class _CameraScannerScreen extends StatefulWidget {
  const _CameraScannerScreen({required this.title, this.expectedUrType});

  /// Short label for what's being scanned (e.g. `wc: URI`), shown as a hint.
  final String title;
  final String? expectedUrType;

  @override
  State<_CameraScannerScreen> createState() => _CameraScannerScreenState();
}

class _CameraScannerScreenState extends State<_CameraScannerScreen> {
  // QR only + noDuplicates: scan a single code, ignore other barcode types.
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  late final UrQrAssembler? _urAssembler = widget.expectedUrType == null
      ? null
      : UrQrAssembler(expectedType: widget.expectedUrType);
  bool _handled = false;
  String? _sequenceError;

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
        final assembler = _urAssembler;
        if (assembler == null) {
          _handled = true;
          Navigator.of(context).pop(value);
          return;
        }
        try {
          assembler.add(value);
          if (assembler.isComplete) {
            _handled = true;
            Navigator.of(context).pop(assembler.result);
            return;
          }
          if (mounted) {
            setState(() => _sequenceError = null);
          }
        } on UrQrException catch (error) {
          if (mounted) {
            setState(() => _sequenceError = error.message);
          }
        }
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.title.isEmpty
        ? 'Наведите камеру на QR-код'
        : 'Наведите камеру на QR-код (${widget.title})';
    final assembler = _urAssembler;
    final sequenceHint = assembler == null
        ? hint
        : assembler.expectedCount > 0
        ? '$hint\nСобрано: ${assembler.receivedCount}/${assembler.expectedCount}'
        : '$hint\nОжидание первого UR-фрагмента';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Сканирование QR'),
        actions: [_TorchButton(controller: _controller)],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // A centred square scan window: detection is limited to it and the
          // overlay dims everything around it, so it's clear where to aim.
          final size = constraints.biggest;
          final dimension = size.shortestSide * 0.7;
          final scanWindow = Rect.fromCenter(
            center: size.center(Offset.zero),
            width: dimension,
            height: dimension,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                scanWindow: scanWindow,
                errorBuilder: (context, error) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Не удалось открыть камеру. Проверьте разрешение на '
                      'доступ к камере или используйте загрузку QR из файла.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
              ScanWindowOverlay(
                controller: _controller,
                scanWindow: scanWindow,
                borderColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                borderWidth: 3,
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
                    child: Text(
                      _sequenceError ?? sequenceHint,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// AppBar action that toggles the camera torch, reflecting the live torch state
/// from the controller. Hidden when the device reports no torch.
class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.controller});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: controller,
      builder: (context, state, child) {
        if (state.torchState == TorchState.unavailable) {
          return const SizedBox.shrink();
        }
        final on = state.torchState == TorchState.on;
        return IconButton(
          icon: Icon(on ? Icons.flash_on : Icons.flash_off),
          tooltip: on ? 'Выключить фонарик' : 'Включить фонарик',
          onPressed: () => controller.toggleTorch(),
        );
      },
    );
  }
}
