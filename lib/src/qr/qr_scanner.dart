/// Injectable seam for obtaining a QR payload — a WalletConnect `wc:` pairing
/// URI or an AirGap `airgap-tx:` request — from one of two sources:
///
/// - **camera scan** (`scanWithCamera`): live camera; not available on every
///   platform (notably Windows x64, a CI build target) so it stays deferred for
///   now (see the docs in `file_qr_scanner.dart`);
/// - **file load** (`loadFromFile`): decode a QR from a picked image file; works
///   on **every** platform and is the only option on Windows.
///
/// [FileQrScanner] (in `file_qr_scanner.dart`) is the production default;
/// [UnavailableQrScanner] is the inert fallback and [FakeQrScanner] drives tests.
abstract interface class QrScanner {
  /// Whether live camera scanning is wired on this platform/build.
  bool get isCameraScanAvailable;

  /// Whether loading a QR from an image file is available (all platforms).
  bool get isFileLoadAvailable;

  /// Opens the camera scanner; resolves with the decoded text or null when
  /// cancelled. Throws [QrScannerException] when camera scanning is unavailable.
  Future<String?> scanWithCamera({String title});

  /// Picks an image file and decodes the QR in it; resolves with the decoded
  /// text or null when the user cancels. Throws [QrScannerException] when file
  /// loading is unavailable or the image holds no readable QR.
  Future<String?> loadFromFile();
}

class QrScannerException implements Exception {
  const QrScannerException(this.message);

  final String message;

  @override
  String toString() => 'QrScannerException: $message';
}

/// Inert [QrScanner]: no camera, no file load. Used as an explicit "disabled"
/// option and in tests that don't exercise scanning.
class UnavailableQrScanner implements QrScanner {
  const UnavailableQrScanner();

  static const String _message = 'Сканер QR недоступен в этой сборке.';

  @override
  bool get isCameraScanAvailable => false;

  @override
  bool get isFileLoadAvailable => false;

  @override
  Future<String?> scanWithCamera({String title = ''}) async {
    throw const QrScannerException(_message);
  }

  @override
  Future<String?> loadFromFile() async {
    throw const QrScannerException(_message);
  }
}

/// In-memory [QrScanner] for tests/DI: both sources resolve with [nextResult]
/// (null = cancelled) and each call is recorded in [events].
class FakeQrScanner implements QrScanner {
  FakeQrScanner({
    this.nextResult,
    this.cameraAvailable = true,
    this.fileLoadAvailable = true,
  });

  /// The value the next call returns; null simulates a cancelled pick/scan.
  String? nextResult;
  bool cameraAvailable;
  bool fileLoadAvailable;
  final List<String> events = <String>[];

  @override
  bool get isCameraScanAvailable => cameraAvailable;

  @override
  bool get isFileLoadAvailable => fileLoadAvailable;

  @override
  Future<String?> scanWithCamera({String title = ''}) async {
    events.add('camera:$title');
    return nextResult;
  }

  @override
  Future<String?> loadFromFile() async {
    events.add('file');
    return nextResult;
  }
}
