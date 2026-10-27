import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/errors/app_error.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';

void main() {
  Future<Object?> failureOf(_FakeLocalAuthentication plugin) async {
    try {
      await LocalAuthenticationGateway(plugin).authenticate(reason: 'test');
      return null;
    } on Object catch (error) {
      return error;
    }
  }

  test('asks for biometrics only, kept across backgrounding', () async {
    final plugin = _FakeLocalAuthentication();
    await LocalAuthenticationGateway(plugin).authenticate(reason: 'Unlock');
    expect(plugin.lastReason, 'Unlock');
    expect(plugin.lastBiometricOnly, isTrue);
    expect(plugin.lastPersistAcrossBackgrounding, isTrue);
  });

  test('a declined check is a cancel', () async {
    expect(
      await failureOf(_FakeLocalAuthentication(result: false)),
      isA<BiometricCancelledFailure>(),
    );
  });

  test('plugin failures map to the app wording', () async {
    const expected = <LocalAuthExceptionCode, AppErrorCode>{
      LocalAuthExceptionCode.userCanceled: AppErrorCode.biometricCancelled,
      LocalAuthExceptionCode.systemCanceled: AppErrorCode.biometricCancelled,
      LocalAuthExceptionCode.timeout: AppErrorCode.biometricCancelled,
      LocalAuthExceptionCode.userRequestedFallback:
          AppErrorCode.biometricCancelled,
      LocalAuthExceptionCode.noBiometricHardware:
          AppErrorCode.biometricUnavailable,
      LocalAuthExceptionCode.noBiometricsEnrolled:
          AppErrorCode.biometricUnavailable,
      LocalAuthExceptionCode.noCredentialsSet:
          AppErrorCode.biometricUnavailable,
      LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
          AppErrorCode.biometricUnavailable,
      LocalAuthExceptionCode.temporaryLockout: AppErrorCode.biometricLockedOut,
      LocalAuthExceptionCode.biometricLockout: AppErrorCode.biometricLockedOut,
      LocalAuthExceptionCode.authInProgress: AppErrorCode.biometricFailed,
      LocalAuthExceptionCode.uiUnavailable: AppErrorCode.biometricFailed,
      LocalAuthExceptionCode.deviceError: AppErrorCode.biometricFailed,
      LocalAuthExceptionCode.unknownError: AppErrorCode.biometricFailed,
    };
    expect(expected.keys, containsAll(LocalAuthExceptionCode.values));

    for (final MapEntry(key: code, value: errorCode) in expected.entries) {
      final failure = await failureOf(
        _FakeLocalAuthentication(error: LocalAuthException(code: code)),
      );
      expect(failure, isA<VaultFailure>(), reason: code.name);
      expect((failure! as VaultFailure).errorCode, errorCode, reason: '$code');
    }
  });

  test('an unexpected failure keeps its detail', () async {
    final failure = await failureOf(
      _FakeLocalAuthentication(
        error: const LocalAuthException(
          code: LocalAuthExceptionCode.deviceError,
          description: 'sensor error',
        ),
      ),
    );
    expect((failure! as VaultFailure).errorArgs['detail'], 'sensor error');
  });

  test('an older platform exception still reads as a failure', () async {
    final failure = await failureOf(
      _FakeLocalAuthentication(
        error: PlatformException(code: 'NotAvailable', message: 'no sensor'),
      ),
    );
    expect((failure! as VaultFailure).errorCode, AppErrorCode.biometricFailed);
  });

  test('no sensor means unavailable, without a prompt', () async {
    final plugin = _FakeLocalAuthentication(canCheck: false);
    expect(await failureOf(plugin), isA<BiometricUnavailableFailure>());
    expect(plugin.lastReason, isNull);
  });
}

class _FakeLocalAuthentication implements LocalAuthentication {
  _FakeLocalAuthentication({
    this.result = true,
    this.error,
    this.canCheck = true,
  });

  final bool result;
  final Object? error;
  final bool canCheck;

  String? lastReason;
  bool? lastBiometricOnly;
  bool? lastPersistAcrossBackgrounding;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const <Object>[],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    lastReason = localizedReason;
    lastBiometricOnly = biometricOnly;
    lastPersistAcrossBackgrounding = persistAcrossBackgrounding;
    if (error case final Object failure) throw failure;
    return result;
  }

  @override
  Future<bool> get canCheckBiometrics async => canCheck;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
