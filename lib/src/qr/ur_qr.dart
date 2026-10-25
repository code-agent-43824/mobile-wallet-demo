import 'package:bc_ur/bc_ur.dart';

import '../errors/app_error.dart';

/// A malformed, mismatched, or incomplete Blockchain Commons UR sequence.
class UrQrException implements Exception, CodedError {
  /// A failure whose text comes from outside the app; shown as is.
  const UrQrException(String message)
    : _message = message,
      errorCode = null,
      errorArgs = const <String, Object>{};

  const UrQrException.coded(
    AppErrorCode this.errorCode, [
    this.errorArgs = const <String, Object>{},
  ]) : _message = null;

  final String? _message;

  @override
  final AppErrorCode? errorCode;

  @override
  final Map<String, Object> errorArgs;

  @override
  String get message => _message ?? debugDescribeError(errorCode!, errorArgs);

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
      throw UrQrException.coded(AppErrorCode.urMalformed, <String, Object>{
        'detail': 'invalid UR: $error',
      });
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
      throw const UrQrException.coded(
        AppErrorCode.urMalformed,
        <String, Object>{'detail': 'cannot split into multipart UR'},
      );
    }
    final sequence = pieces[1].split('-');
    final count = sequence.length == 2 ? int.tryParse(sequence[1]) : null;
    if (count == null || count < 1) {
      throw const UrQrException.coded(
        AppErrorCode.urMalformed,
        <String, Object>{'detail': 'invalid multipart sequence numbering'},
      );
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
      throw const UrQrException.coded(
        AppErrorCode.urMalformed,
        <String, Object>{'detail': 'not a single- or multipart UR'},
      );
    }
    final type = pieces.first.substring(3);
    if (expectedType != null && type != expectedType) {
      throw UrQrException.coded(AppErrorCode.urWrongType, <String, Object>{
        'expected': 'ur:$expectedType',
        'actual': 'ur:$type',
      });
    }
    if (_type != null && _type != type) {
      throw const UrQrException.coded(
        AppErrorCode.urMalformed,
        <String, Object>{'detail': 'fragments belong to different UR types'},
      );
    }
    _type = type;

    if (pieces.length == 2) {
      try {
        _result = BCUR.fromString(normalized).toString();
      } catch (error) {
        throw UrQrException.coded(AppErrorCode.urMalformed, <String, Object>{
          'detail': 'invalid UR: $error',
        });
      }
      return true;
    }

    try {
      _decoder.receivePart(normalized);
    } catch (error) {
      throw UrQrException.coded(AppErrorCode.urMalformed, <String, Object>{
        'detail': 'invalid multipart UR: $error',
      });
    }
    if (_decoder.isComplete) {
      final decoded = _decoder.getResult();
      if (decoded == null) {
        throw const UrQrException.coded(
          AppErrorCode.urMalformed,
          <String, Object>{'detail': 'fragment set is corrupt'},
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
    throw const UrQrException.coded(AppErrorCode.urMalformed, <String, Object>{
      'detail': 'expected a value starting with "ur:"',
    });
  }
  return normalized;
}
