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

  test('Rutoken address derivation uses only the explicit EVM child path', () {
    final source = File(
      'android/app/src/main/kotlin/com/example/mobile_wallet_demo/rutoken/'
      'RutokenRuntime.kt',
    ).readAsStringSync();

    expect(source, contains('path: LongArray'));
    expect(source, isNot(contains('path: LongArray?')));
    expect(source, contains('longArrayOf(hardened(44), hardened(60)'));
    expect(source, contains('makeAttribute(CKA_KEY_TYPE, CKK_VENDOR_BIP32)'));
    expect(source, contains('no BIP32 ECDSA master key'));
  });

  test('Rutoken derives and reads the official EC public-key object type', () {
    final source = File(
      'android/app/src/main/kotlin/com/example/mobile_wallet_demo/rutoken/'
      'RutokenRuntime.kt',
    ).readAsStringSync();

    expect(source, contains('Pkcs11EcPublicKeyObject::class.java'));
    expect(source, contains('key.getEcPointAttributeValue(session)'));
    expect(
      source,
      isNot(contains('key.getByteArrayAttributeValue(session, CKA_EC_POINT)')),
    );
  });

  test('Rutoken signing mirrors the raw ECDSA reference flow only', () {
    final runtime = File(
      'android/app/src/main/kotlin/com/example/mobile_wallet_demo/rutoken/'
      'RutokenRuntime.kt',
    ).readAsStringSync();
    final channel = File(
      'android/app/src/main/kotlin/com/example/mobile_wallet_demo/rutoken/'
      'RutokenMethodChannel.kt',
    ).readAsStringSync();

    expect(runtime, contains('Pkcs11EcPrivateKeyObject::class.java'));
    expect(runtime, contains('makeAttribute(CKA_TOKEN, true)'));
    expect(runtime, contains('Pkcs11Mechanism.make(CKM_ECDSA)'));
    expect(runtime, contains('objectManager.destroyObject(derived)'));
    expect(runtime, isNot(contains('CKA_VENDOR_BIP32_CHAINCODE')));
    expect(channel, contains('"readAccountDescriptor"'));
    expect(channel, isNot(contains('"readPublicMaterial"')));
  });
}
