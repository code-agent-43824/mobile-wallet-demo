import 'package:bc_ur/bc_ur.dart';

/// A malformed, mismatched, or incomplete Blockchain Commons UR sequence.
class UrQrException implements Exception {
  const UrQrException(this.message);

  final String message;

  @override
  String toString() => 'UrQrException: $message';
}

/// Turns a canonical single-part BC-UR into QR frames. Small payloads stay a
/// single QR; larger payloads use the BC-UR fountain multipart form and can be
/// looped indefinitely by the presentation layer.
class UrQrEncoder {
  const UrQrEncoder({this.maxFragmentLength = 100});

  final int maxFragmentLength;

  List<String> encode(String value) {
    final normalized = normalizeUr(value);
    final BCUR ur;
    try {
      ur = BCUR.fromString(normalized);
    } catch (error) {
      throw UrQrException('Некорректный BC-UR: $error');
    }
    if (ur.payload.length <= maxFragmentLength) {
      return <String>[ur.toString()];
    }

    final fountain = BCURFountainEncoder(
      ur,
      maxFragmentLength: maxFragmentLength,
    );
    final first = fountain.nextPart();
    final count = _sequenceLength(first);
    return <String>[
      first,
      for (var index = 1; index < count; index++) fountain.nextPart(),
    ];
  }

  int _sequenceLength(String firstPart) {
    final pieces = firstPart.split('/');
    if (pieces.length != 3) {
      throw const UrQrException('Не удалось создать multipart BC-UR.');
    }
    final sequence = pieces[1].split('-');
    final count = sequence.length == 2 ? int.tryParse(sequence[1]) : null;
    if (count == null || count < 1) {
      throw const UrQrException('Некорректная нумерация multipart BC-UR.');
    }
    return count;
  }
}

/// Incrementally assembles single- or multipart BC-UR scans. The completed
/// value is returned in canonical single-part form so protocol codecs do not
/// need to understand fountain fragments.
class UrQrAssembler {
  UrQrAssembler({this.expectedType});

  final String? expectedType;
  final BCURFountainDecoder _decoder = BCURFountainDecoder();
  String? _type;
  String? _result;

  bool get isComplete => _result != null;
  String? get result => _result;
  double get progress => isComplete ? 1 : _decoder.progress;
  int get receivedCount => _decoder.receivedCount;
  int get expectedCount => _decoder.expectedCount;

  /// Adds one scanned QR value. Returns true only when it was a valid UR frame
  /// for this sequence (duplicates are harmless).
  bool add(String value) {
    if (isComplete) {
      return false;
    }
    final normalized = normalizeUr(value);
    final pieces = normalized.split('/');
    if (pieces.length != 2 && pieces.length != 3) {
      throw const UrQrException('Ожидался single- или multipart BC-UR QR.');
    }
    final type = pieces.first.substring(3);
    if (expectedType != null && type != expectedType) {
      throw UrQrException('Ожидался ur:$expectedType, получен ur:$type.');
    }
    if (_type != null && _type != type) {
      throw const UrQrException('QR-фрагменты относятся к разным UR типам.');
    }
    _type = type;

    if (pieces.length == 2) {
      try {
        _result = BCUR.fromString(normalized).toString();
      } catch (error) {
        throw UrQrException('Некорректный BC-UR: $error');
      }
      return true;
    }

    try {
      _decoder.receivePart(normalized);
    } catch (error) {
      throw UrQrException('Некорректный multipart BC-UR: $error');
    }
    if (_decoder.isComplete) {
      final decoded = _decoder.getResult();
      if (decoded == null) {
        throw const UrQrException(
          'Не удалось собрать BC-UR: повреждён набор QR-фрагментов.',
        );
      }
      _result = decoded.toString();
    }
    return true;
  }
}

/// BC-UR is case-insensitive. Camera encoders normally use uppercase to enter
/// QR alphanumeric mode, while Dart protocol codecs use canonical lowercase.
String normalizeUr(String value) {
  final normalized = value.trim().toLowerCase();
  if (!normalized.startsWith('ur:')) {
    throw const UrQrException('Ожидался BC-UR, начинающийся с "ur:".');
  }
  return normalized;
}
