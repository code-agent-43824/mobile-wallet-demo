import 'dart:isolate';
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

  /// Images with more pixels are refused from their header, before any
  /// decoding: a 7000 × 7000 photo is far beyond what a QR needs, and a header
  /// that claims more could be crafted to exhaust memory.
  static const int maxPixels = 50 * 1000 * 1000;

  /// The smallest side worth reading after scaling down; below it the modules
  /// of a large QR blur together.
  static const int _minScaledSide = 80;

  @override
  String? decode(Uint8List imageBytes) {
    final img.Image? image;
    try {
      final decoder = img.findDecoderForData(imageBytes);
      final info = decoder?.startDecode(imageBytes);
      if (decoder == null ||
          info == null ||
          info.width * info.height > maxPixels) {
        return null;
      }
      image = decoder.decode(imageBytes);
    } catch (_) {
      // A non-image or truncated file: no QR.
      return null;
    }
    if (image == null) {
      return null;
    }
    // zxing2 misjudges the module size of a large, high-version QR (a 200+
    // character wc: URI at 10 px per module is version 15) and reports no
    // code; zbar reads the same file. So after the plain read come two more:
    // the image as a lone code on its page, which reads the grid without
    // looking for finder patterns (a QR saved as an image), and smaller copies
    // of it, at which the detector's estimate comes out right (a screenshot
    // with the code among other things).
    final luminance = _luminance(image);
    return _read(luminance) ??
        _read(luminance, pureBarcode: true) ??
        _readScaledDown(image);
  }

  String? _readScaledDown(img.Image image) {
    for (var divisor = 2; divisor <= 10; divisor++) {
      final width = image.width ~/ divisor;
      final height = image.height ~/ divisor;
      if (width < _minScaledSide || height < _minScaledSide) {
        return null;
      }
      final smaller = img.copyResize(
        image,
        width: width,
        height: height,
        interpolation: img.Interpolation.average,
      );
      final text = _read(_luminance(smaller));
      if (text != null) {
        return text;
      }
    }
    return null;
  }

  static String? _read(LuminanceSource source, {bool pureBarcode = false}) {
    try {
      final hints = DecodeHints();
      if (pureBarcode) {
        hints.put(DecodeHintType.pureBarcode);
      }
      return QRCodeReader()
          .decode(BinaryBitmap(HybridBinarizer(source)), hints: hints)
          .text;
    } catch (_) {
      // NotFound/Format/Checksum: no readable QR this way.
      return null;
    }
  }

  /// Channels are read normalized: a 1-bit PNG keeps its pixels in 0..1 and a
  /// 16-bit one in 0..65535, and a grey image has no green or blue.
  /// Transparency is laid over white, the paper a QR code is printed on.
  static LuminanceSource _luminance(img.Image image) {
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
    return RGBLuminanceSource(image.width, image.height, pixels);
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

  /// The production decoder runs on a background isolate: a large picture
  /// takes long enough to read that the window would stop responding.
  Future<String?> _decode(Uint8List bytes) {
    if (_decoder is ZxingQrImageDecoder) {
      return Isolate.run(() => const ZxingQrImageDecoder().decode(bytes));
    }
    return Future<String?>.value(_decoder.decode(bytes));
  }

  @override
  Future<String?> loadFromFile() async {
    final bytes = await _pickImageBytes();
    if (bytes == null) {
      return null; // user cancelled the picker
    }
    final text = await _decode(bytes);
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
      final text = await _decode(bytes);
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
