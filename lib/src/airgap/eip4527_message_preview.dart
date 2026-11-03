import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' show bytesToHex;

/// What an EIP-4527 `personal_sign` request (`rawBytes`) asks to sign, in the
/// form a person can check: the text itself when the bytes read as text, the
/// hex otherwise.
///
/// A message is the usual way to get someone to sign something else — a
/// transaction hash or a permit digest is an opaque blob, and characters that
/// do not print can hide part of a text — so such bytes are never shown as if
/// they were plain text.
class Eip4527MessagePreview {
  Eip4527MessagePreview(this.bytes) : text = _readableText(bytes);

  /// The exact bytes that get signed (the signer adds the EIP-191 prefix).
  final Uint8List bytes;

  /// The message as text, or null when the bytes are not readable text.
  final String? text;

  bool get isText => text != null;

  String get hex => bytesToHex(bytes, include0x: true);

  static String? _readableText(Uint8List bytes) {
    if (bytes.isEmpty) {
      return null;
    }
    final String decoded;
    try {
      decoded = utf8.decode(bytes);
    } on FormatException {
      return null;
    }
    return decoded.runes.any(_hidesText) ? null : decoded;
  }

  /// Control characters other than line breaks and tabs, zero-width
  /// characters and bidirectional overrides change what the eye reads.
  static bool _hidesText(int rune) =>
      (rune < 0x20 && rune != 0x09 && rune != 0x0a && rune != 0x0d) ||
      (rune >= 0x7f && rune <= 0x9f) ||
      (rune >= 0x200b && rune <= 0x200f) ||
      (rune >= 0x202a && rune <= 0x202e) ||
      (rune >= 0x2066 && rune <= 0x2069) ||
      rune == 0xfeff;
}
