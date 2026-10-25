import 'dart:io';

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../errors/app_error.dart';
import '../key_storage/key_storage_backend.dart';

enum BiometricAuthMode { local, simulated, unavailable }

/// Why the system biometric dialog is shown. The dialog's sentence belongs to
/// the active UI language, so domain code names the purpose and whoever builds
/// the backend supplies the text ([BiometricPromptText]).
enum BiometricPrompt {
  enableQuickUnlock,
  unlockWallet,
  saveCardPin,
  releaseCardPin,
}

typedef BiometricPromptText = String Function(BiometricPrompt prompt);

/// Fallback for backends built without a localized source (tests, tools).
String defaultBiometricPromptText(BiometricPrompt prompt) => switch (prompt) {
  BiometricPrompt.enableQuickUnlock => 'Confirm to turn on quick unlock.',
  BiometricPrompt.unlockWallet => 'Confirm to unlock the wallet.',
  BiometricPrompt.saveCardPin => 'Confirm to save the card PIN.',
  BiometricPrompt.releaseCardPin => 'Confirm to use the saved card PIN.',
};

abstract interface class BiometricAuthGateway {
  BiometricAuthMode get mode;

  Future<bool> isAvailable();

  Future<void> authenticate({required String reason});
}

BiometricAuthGateway defaultBiometricAuthGateway() {
  if (Platform.isAndroid || Platform.isIOS) {
    return LocalAuthenticationGateway();
  }
  if (Platform.isWindows) {
    return const SimulatedBiometricAuthGateway();
  }
  return const UnavailableBiometricAuthGateway();
}

class LocalAuthenticationGateway implements BiometricAuthGateway {
  LocalAuthenticationGateway([LocalAuthentication? localAuthentication])
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuthentication;

  @override
  BiometricAuthMode get mode => BiometricAuthMode.local;

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
      throw VaultFailure.coded(AppErrorCode.biometricFailed, <String, Object>{
        'detail': error.message ?? error.code,
      });
    }
  }
}

class SimulatedBiometricAuthGateway implements BiometricAuthGateway {
  const SimulatedBiometricAuthGateway({this.available = true});

  final bool available;

  @override
  BiometricAuthMode get mode => BiometricAuthMode.simulated;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> authenticate({required String reason}) async {
    if (!available) {
      throw const BiometricUnavailableFailure();
    }
  }
}

class UnavailableBiometricAuthGateway implements BiometricAuthGateway {
  const UnavailableBiometricAuthGateway();

  @override
  BiometricAuthMode get mode => BiometricAuthMode.unavailable;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> authenticate({required String reason}) async {
    throw const BiometricUnavailableFailure();
  }
}
