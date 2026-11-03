import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/airgap/eip4527_message_preview.dart';

Eip4527MessagePreview _preview(String text) =>
    Eip4527MessagePreview(Uint8List.fromList(utf8.encode(text)));

void main() {
  test('readable text is shown as text, line breaks included', () {
    final preview = _preview('Вход на example.org\nNonce: 42');

    expect(preview.isText, isTrue);
    expect(preview.text, 'Вход на example.org\nNonce: 42');
  });

  test('bytes that are not UTF-8 are shown as hex', () {
    // A 32-byte digest: the classic thing to get signed as a "message".
    final digest = Uint8List.fromList(
      List<int>.generate(32, (i) => 0xf0 + i % 16),
    );
    final preview = Eip4527MessagePreview(digest);

    expect(preview.isText, isFalse);
    expect(preview.text, isNull);
    expect(preview.hex, startsWith('0xf0f1f2'));
  });

  test('characters that hide part of a text make it not text', () {
    expect(_preview('pay\u0000 later').isText, isFalse);
    // A right-to-left override reverses what follows it on screen.
    expect(_preview('approve \u202Eevil').isText, isFalse);
    expect(_preview('zero\u200Bwidth').isText, isFalse);
    expect(Eip4527MessagePreview(Uint8List(0)).isText, isFalse);
  });
}
