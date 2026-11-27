import 'dart:async';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';

import '../auth/biometric_auth.dart';
import '../errors/app_error.dart';
import '../ton/ton_account.dart';
import 'biometric_secret_store.dart';
import 'encrypted_mnemonic_vault.dart';
import 'key_storage_backend.dart';
import 'secure_key_value_store.dart';
import 'ton_mnemonic.dart';

/// Keeps signing and seed derivation inside the vault, without an unlock cache.
final class PhoneTonVault {
  PhoneTonVault({
    required SecureKeyValueStore store,
    BiometricAuthGateway? biometricAuth,
    BiometricSecretStore? biometricSecretStore,
    int pbkdf2Iterations = EncryptedMnemonicVault.defaultPinIterations,
  }) : _vault = EncryptedMnemonicVault(
         store: store,
         storageKey: storageKey,
         backendId: 'phone_ton_vault',
         biometricSecretId: 'ton.testnet',
         biometricAuth: biometricAuth,
         biometricSecretStore: biometricSecretStore,
         pbkdf2Iterations: pbkdf2Iterations,
       );

  static const storageKey = 'wallet.phone_ton_testnet.v1';
  static const _derivation = 'ton-mnemonic';
  final EncryptedMnemonicVault _vault;

  Future<TonAccount?> getAccount() async {
    final record = await _vault.read();
    return record == null ? null : _accountFromRecord(record);
  }

  /// Called after the user supplies or confirms a backed-up phrase.
  Future<TonAccount> importMnemonic({
    required String mnemonic,
    required String pin,
  }) async {
    if (await _vault.hasWallet()) {
      throw const VaultFailure.coded(AppErrorCode.walletAlreadyExists);
    }
    final phrase = TonMnemonic.normalize(mnemonic);
    final account = await _withKeyPair(phrase, (keyPair) async {
      return TonAccount((await keyPair.extractPublicKey()).bytes);
    });
    await _vault.create(
      mnemonic: phrase,
      pin: pin,
      address: account.rawAddress,
      derivationPath: _derivation,
      publicKeyHex: account.publicKeyHex,
    );
    return account;
  }

  Future<bool> isBiometricUnlockAvailable() =>
      _vault.isBiometricUnlockAvailable();

  Future<bool> isBiometricUnlockEnabled() => _vault.isBiometricUnlockEnabled();

  Future<void> setBiometricUnlockEnabled({
    required bool enabled,
    required String pin,
  }) => _vault.setBiometricUnlockEnabled(enabled: enabled, pin: pin);

  Future<Uint8List> sign({
    required TonAccount account,
    required Uint8List hash,
    String? pin,
  }) {
    if (hash.length != 32) throw ArgumentError('Expected a TON cell hash');
    final message = Uint8List.fromList(hash);
    Future<Uint8List> signOnce(
      String phrase,
      EncryptedMnemonicRecord record,
    ) async {
      if (_accountFromRecord(record).rawAddress != account.rawAddress) {
        throw const VaultFailure.coded(AppErrorCode.txSenderMismatch);
      }
      return _withKeyPair(phrase, (keyPair) async {
        final actual = await keyPair.extractPublicKey();
        if (hex.encode(actual.bytes) != account.publicKeyHex) {
          throw const CorruptVaultPayloadFailure();
        }
        final signature = await Ed25519().sign(message, keyPair: keyPair);
        return Uint8List.fromList(signature.bytes);
      });
    }

    return pin == null
        ? _vault.withBiometrics(signOnce)
        : _vault.withPin(pin: pin, use: signOnce);
  }

  TonAccount _accountFromRecord(EncryptedMnemonicRecord record) {
    try {
      final account = TonAccount(hex.decode(record.publicKeyHex!));
      if (record.derivationPath != _derivation ||
          account.rawAddress != record.address) {
        throw const CorruptVaultPayloadFailure();
      }
      return account;
    } catch (_) {
      throw const CorruptVaultPayloadFailure();
    }
  }

  Future<T> _withKeyPair<T>(
    String phrase,
    FutureOr<T> Function(SimpleKeyPairData) use,
  ) async {
    final seed = await TonMnemonic.deriveSeed(phrase);
    try {
      final pair = await (await Ed25519().newKeyPairFromSeed(seed)).extract();
      try {
        return await use(pair);
      } finally {
        pair.destroy();
      }
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }
}
