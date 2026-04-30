import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../key_storage/key_storage_backend.dart';

abstract interface class BiometricAuthGateway {
  Future<bool> isAvailable();

  Future<void> authenticate({required String reason});
}

class LocalAuthenticationGateway implements BiometricAuthGateway {
  LocalAuthenticationGateway([LocalAuthentication? localAuthentication])
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuthentication;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _localAuthentication.isDeviceSupported() &&
          await _localAuthentication.canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> authenticate({required String reason}) async {
    final available = await isAvailable();
    if (!available) {
      throw const BiometricUnavailableFailure();
    }

    try {
      final authenticated = await _localAuthentication.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (!authenticated) {
        throw const BiometricCancelledFailure();
      }
    } on PlatformException catch (error) {
      throw VaultFailure('Biometric authentication failed: ${error.message ?? error.code}');
    }
  }
}
