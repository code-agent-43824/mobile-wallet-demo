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

  test('Rutoken transport attaches from Application before MainActivity', () {
    final applicationSource = File(
      'android/app/src/main/kotlin/com/example/mobile_wallet_demo/'
      'WalletDemoApplication.kt',
    ).readAsStringSync();
    final activitySource = File(
      'android/app/src/main/kotlin/com/example/mobile_wallet_demo/'
      'MainActivity.kt',
    ).readAsStringSync();
    final runtimeSource = File(
      'android/app/src/main/kotlin/com/example/mobile_wallet_demo/rutoken/'
      'RutokenRuntime.kt',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    final setContext = applicationSource.indexOf('RtPcscBridge.setAppContext');
    final attach = applicationSource.indexOf('attachToLifecycle');
    final createRuntime = applicationSource.indexOf('RutokenRuntime.get()');
    expect(setContext, greaterThanOrEqualTo(0));
    expect(attach, greaterThan(setContext));
    expect(createRuntime, greaterThan(attach));
    expect(manifest, contains('android:name=".WalletDemoApplication"'));
    expect(activitySource, contains('application as WalletDemoApplication'));
    expect(runtimeSource, isNot(contains('RtPcscBridge')));
  });

  test('Rutoken master derivation uses the vendor nullable empty path', () {
    final source = File(
      'android/app/src/main/kotlin/com/example/mobile_wallet_demo/rutoken/'
      'RutokenRuntime.kt',
    ).readAsStringSync();

    expect(source, contains('derivePublic(open.session, master, null)'));
    expect(source, contains('path: LongArray?'));
    expect(
      source,
      isNot(contains('derivePublic(open.session, master, longArrayOf())')),
    );
    expect(source, contains('makeAttribute(CKA_KEY_TYPE, CKK_VENDOR_BIP32)'));
    expect(source, contains('no BIP32 ECDSA master key'));
  });
}
