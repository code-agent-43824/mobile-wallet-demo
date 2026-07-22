import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android Rutoken discovery listens for PC/SC slot events', () {
    final source = File(
      'android/app/src/main/kotlin/com/example/mobile_wallet_demo/rutoken/'
      'RutokenRuntime.kt',
    ).readAsStringSync();

    expect(source, contains('module.waitForSlotEvent(false)'));
    expect(source, contains('slotEventExecutor'));
    expect(source, contains('presentTokens = currentTokens()'));
    expect(source, isNot(contains('Thread.sleep(TOKEN_POLL_MILLIS)')));
  });
}
