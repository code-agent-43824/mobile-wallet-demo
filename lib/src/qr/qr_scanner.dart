/// Injectable seam for scanning a QR code into a text payload — a WalletConnect
/// `wc:` pairing URI or an AirGap `airgap-tx:` request.
///
/// The real camera-backed implementation (`mobile_scanner`) is **deferred**: it
/// does not support all of our target platforms (notably Windows x64, a CI build
/// target) and needs per-platform camera permissions. [UnavailableQrScanner] is
/// the shippable default (the screen hides the scan affordance and keeps the
/// paste field); [FakeQrScanner] drives tests/DI. This mirrors how the real
/// `WalletConnectService` is deferred behind its seam.
abstract interface class QrScanner {
  /// Whether a real scanner is wired and usable on this platform/build.
  bool get isAvailable;

  /// Opens the scanner and resolves with the decoded text, or null when the
  /// user cancels. Throws [QrScannerException] when scanning is unavailable.
  Future<String?> scan({String title});
}

class QrScannerException implements Exception {
  const QrScannerException(this.message);

  final String message;

  @override
  String toString() => 'QrScannerException: $message';
}

/// Default production [QrScanner] until the camera impl lands: reports
/// unavailable and refuses to scan, so the UI shows paste-only instead of a
/// dead camera button.
class UnavailableQrScanner implements QrScanner {
  const UnavailableQrScanner();

  static const String _message =
      'Сканер QR недоступен в этой сборке (камера подключится позже).';

  @override
  bool get isAvailable => false;

  @override
  Future<String?> scan({String title = ''}) async {
    throw const QrScannerException(_message);
  }
}

/// In-memory [QrScanner] for tests/DI: returns [nextResult] (null = cancelled)
/// and records the [scannedTitles] it was asked to scan.
class FakeQrScanner implements QrScanner {
  FakeQrScanner({this.nextResult});

  /// The value the next [scan] returns; null simulates a cancelled scan.
  String? nextResult;

  final List<String> scannedTitles = <String>[];

  @override
  bool get isAvailable => true;

  @override
  Future<String?> scan({String title = ''}) async {
    scannedTitles.add(title);
    return nextResult;
  }
}
