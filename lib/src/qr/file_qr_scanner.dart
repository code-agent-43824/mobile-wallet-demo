import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import 'qr_scanner.dart';

/// Decodes QR text from raw image bytes. Pure Dart (`image` + `zxing2`), so it
/// runs on **every** platform including Windows — no camera, no native plugin.
/// Injectable so the file-load flow is testable without a real picker.
abstract interface class QrImageDecoder {
  /// Returns the decoded QR text, or null when the image holds no readable QR.
  String? decode(Uint8List imageBytes);
}

class ZxingQrImageDecoder implements QrImageDecoder {
  const ZxingQrImageDecoder();

  @override
  String? decode(Uint8List imageBytes) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        return null;
      }

      final pixels = Int32List(image.width * image.height);
      var i = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final p = image.getPixel(x, y);
          pixels[i++] =
              (p.a.toInt() << 24) |
              (p.r.toInt() << 16) |
              (p.g.toInt() << 8) |
              p.b.toInt();
        }
      }

      final source = RGBLuminanceSource(image.width, image.height, pixels);
      final bitmap = BinaryBitmap(HybridBinarizer(source));
      return QRCodeReader().decode(bitmap).text;
    } catch (_) {
      // `decodeImage` can throw on a non-image/truncated file, and zxing2 throws
      // NotFound/Format/Checksum when there's no readable QR — all "no QR".
      return null;
    }
  }
}

/// Production [QrScanner] default: loads a QR from an image **file** on every
/// platform (the only option on Windows x64, where camera plugins don't exist).
/// Live camera scanning stays deferred (a future native-platform step). File
/// picking goes through `file_selector` (official, Windows-supported), kept
/// injectable via [pickImageBytes] so tests don't touch the platform.
class FileQrScanner implements QrScanner {
  FileQrScanner({
    QrImageDecoder decoder = const ZxingQrImageDecoder(),
    Future<Uint8List?> Function()? pickImageBytes,
  }) : _decoder = decoder,
       _pickImageBytes = pickImageBytes ?? _pickWithFileSelector;

  final QrImageDecoder _decoder;
  final Future<Uint8List?> Function() _pickImageBytes;

  @override
  bool get isCameraScanAvailable => false;

  @override
  bool get isFileLoadAvailable => true;

  @override
  Future<String?> scanWithCamera({String title = ''}) async {
    throw const QrScannerException(
      'Сканирование камерой пока недоступно — используйте загрузку из файла.',
    );
  }

  @override
  Future<String?> scanUrWithCamera({
    String title = '',
    String? expectedType,
  }) async {
    throw const QrScannerException(
      'Сканирование камерой пока недоступно — используйте загрузку из файла.',
    );
  }

  @override
  Future<String?> loadFromFile() async {
    final bytes = await _pickImageBytes();
    if (bytes == null) {
      return null; // user cancelled the picker
    }
    final text = _decoder.decode(bytes);
    if (text == null) {
      throw const QrScannerException(
        'Не удалось распознать QR-код на выбранном изображении.',
      );
    }
    return text;
  }

  static Future<Uint8List?> _pickWithFileSelector() async {
    const typeGroup = XTypeGroup(
      label: 'QR image',
      extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'],
    );
    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (file == null) {
      return null;
    }
    return file.readAsBytes();
  }
}
