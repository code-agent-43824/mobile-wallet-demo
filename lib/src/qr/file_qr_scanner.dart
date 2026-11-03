import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import '../errors/app_error.dart';
import 'qr_scanner.dart';
import 'ur_qr.dart';

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

      // Channels are read normalized: a 1-bit PNG keeps its pixels in 0..1
      // and a 16-bit one in 0..65535, and a grey image has no green or blue.
      // Transparency is laid over white, the paper a QR code is printed on.
      final pixels = Int32List(image.width * image.height);
      var i = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final p = image.getPixel(x, y);
          final alpha = p.aNormalized;
          final grey = (255 * (p.luminanceNormalized * alpha + 1 - alpha))
              .round();
          pixels[i++] = (grey << 16) | (grey << 8) | grey;
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
/// injectable via [pickImageBytes] and [pickManyImageBytes] so tests don't
/// touch the platform.
class FileQrScanner implements QrScanner {
  FileQrScanner({
    QrImageDecoder decoder = const ZxingQrImageDecoder(),
    Future<Uint8List?> Function()? pickImageBytes,
    Future<List<Uint8List>> Function()? pickManyImageBytes,
  }) : _decoder = decoder,
       _pickImageBytes = pickImageBytes ?? _pickWithFileSelector,
       _pickManyImageBytes = pickManyImageBytes ?? _pickManyWithFileSelector;

  final QrImageDecoder _decoder;
  final Future<Uint8List?> Function() _pickImageBytes;
  final Future<List<Uint8List>> Function() _pickManyImageBytes;

  @override
  bool get isCameraScanAvailable => false;

  @override
  bool get isFileLoadAvailable => true;

  @override
  Future<String?> scanWithCamera({String title = ''}) async {
    throw const QrScannerException.coded(AppErrorCode.qrCameraUnavailable);
  }

  @override
  Future<String?> scanUrWithCamera({
    String title = '',
    String? expectedType,
  }) async {
    throw const QrScannerException.coded(AppErrorCode.qrCameraUnavailable);
  }

  @override
  Future<String?> loadFromFile() async {
    final bytes = await _pickImageBytes();
    if (bytes == null) {
      return null; // user cancelled the picker
    }
    final text = _decoder.decode(bytes);
    if (text == null) {
      throw const QrScannerException.coded(AppErrorCode.qrImageNotRecognized);
    }
    return text;
  }

  /// Images that hold no QR are skipped, so a stray screenshot in the
  /// selection does no harm; frames of another UR type are refused.
  @override
  Future<String?> loadUrFromFiles({String? expectedType}) async {
    final images = await _pickManyImageBytes();
    if (images.isEmpty) {
      return null; // user cancelled the picker
    }
    final assembler = UrQrAssembler(expectedType: expectedType);
    var withQr = 0;
    for (final bytes in images) {
      final text = _decoder.decode(bytes);
      if (text == null) {
        continue;
      }
      withQr++;
      assembler.add(text);
      if (assembler.isComplete) {
        return assembler.result;
      }
    }
    if (withQr == 0) {
      throw const QrScannerException.coded(AppErrorCode.qrImageNotRecognized);
    }
    throw QrScannerException.coded(
      AppErrorCode.urFramesIncomplete,
      <String, Object>{
        'framesReceived': assembler.receivedCount,
        'framesNeeded': assembler.expectedCount,
      },
    );
  }

  static const XTypeGroup _imageTypes = XTypeGroup(
    label: 'QR image',
    extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'],
  );

  static Future<Uint8List?> _pickWithFileSelector() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_imageTypes],
    );
    if (file == null) {
      return null;
    }
    return file.readAsBytes();
  }

  static Future<List<Uint8List>> _pickManyWithFileSelector() async {
    final files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[_imageTypes],
    );
    return <Uint8List>[for (final file in files) await file.readAsBytes()];
  }
}
