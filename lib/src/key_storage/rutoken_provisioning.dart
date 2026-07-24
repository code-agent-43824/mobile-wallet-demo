import 'dart:convert';
import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:unorm_dart/unorm_dart.dart' as unorm;
import 'package:web3dart/web3dart.dart' show bytesToHex, publicKeyToAddress;

import 'custody_backend.dart';
import 'rutoken_method_channel_adapter.dart';
import 'secure_key_value_store.dart';

class RutokenGeneratedBackup {
  const RutokenGeneratedBackup({
    required this.mnemonic,
    required this.passphrase,
  });

  final String mnemonic;
  final String passphrase;
}

class RutokenProvisioningResult {
  const RutokenProvisioningResult({
    required this.account,
    required this.publicAccount,
  });

  final WalletAccountDescriptor account;
  final WalletAccountPublicKey publicAccount;
}

/// Recoverable Rutoken provisioning built around the one primitive demonstrated
/// by the supplied Android reference: import a raw BIP-32 master private key
/// plus chain code with `C_CreateObject`.
///
/// Mnemonic/passphrase material is never persisted. The only durable record is
/// public account-level BIP-32 metadata used by EIP-4527 account export and the
/// future production Rutoken backend.
class RutokenProvisioningService {
  const RutokenProvisioningService({
    required RutokenNativeAdapter adapter,
    required SecureKeyValueStore store,
  }) : _adapter = adapter,
       _store = store;

  static const String accountPath = "m/44'/60'/0'";
  static const String addressPath = "m/44'/60'/0'/0/0";
  static const String _metadataKey = 'rutoken.public_account.v1';

  final RutokenNativeAdapter _adapter;
  final SecureKeyValueStore _store;

  RutokenGeneratedBackup generateBackup({String passphrase = ''}) {
    return RutokenGeneratedBackup(
      mnemonic: bip39.generateMnemonic(strength: 256),
      passphrase: passphrase,
    );
  }

  Future<RutokenProvisioningResult> provision({
    required String mnemonic,
    required String passphrase,
    required String pin,
  }) async {
    final normalizedMnemonic = _normalizeMnemonic(mnemonic);
    if (!bip39.validateMnemonic(normalizedMnemonic)) {
      throw const RutokenNativeException(
        'Seed-фраза не прошла проверку BIP-39.',
      );
    }
    if (pin.isEmpty) {
      throw const RutokenNativeException('PIN Рутокена не должен быть пустым.');
    }

    Uint8List? seed;
    Uint8List? masterPrivateKey;
    Uint8List? masterChainCode;
    try {
      seed = bip39.mnemonicToSeed(
        unorm.nfkd(normalizedMnemonic),
        passphrase: unorm.nfkd(passphrase),
      );
      final master = bip32.BIP32.fromSeed(seed);
      final privateKey = master.privateKey;
      if (privateKey == null || privateKey.length != 32) {
        throw const RutokenNativeException(
          'Не удалось получить 32-байтовый BIP-32 master key.',
        );
      }
      masterPrivateKey = Uint8List.fromList(privateKey);
      masterChainCode = Uint8List.fromList(master.chainCode);

      final accountNode = master.derivePath(accountPath);
      final addressNode = master.derivePath(addressPath);
      final expectedAddress =
          '0x${bytesToHex(publicKeyToAddress(_uncompressedXY(addressNode.publicKey)))}';
      final provisionalAccount = WalletAccountDescriptor(
        backendId: 'rutoken_nfc',
        address: expectedAddress,
        derivationPath: addressPath,
      );
      final publicAccount = WalletAccountPublicKey(
        account: provisionalAccount,
        accountPath: accountPath,
        accountDepth: accountNode.depth,
        compressedPublicKey: Uint8List.fromList(accountNode.publicKey),
        chainCode: Uint8List.fromList(accountNode.chainCode),
        sourceFingerprint: _asUint32(master.fingerprint),
        parentFingerprint: accountNode.parentFingerprint,
      );

      // Persist only public recovery metadata before mutating the token. The
      // pending marker makes a process death after C_CreateObject recoverable
      // without ever storing the mnemonic or private key.
      await _writeMetadata(publicAccount, state: 'pending');

      final session = await _adapter.openSession(pin: pin);
      WalletAccountDescriptor? imported;
      Object? closeError;
      StackTrace? closeStackTrace;
      try {
        imported = await _adapter.importWallet(
          session: session,
          masterPrivateKey: masterPrivateKey,
          chainCode: masterChainCode,
        );
      } finally {
        try {
          await _adapter.closeSession(session);
        } catch (error, stackTrace) {
          closeError = error;
          closeStackTrace = stackTrace;
        }
      }

      if (imported.derivationPath != addressPath ||
          imported.address.toLowerCase() != expectedAddress.toLowerCase()) {
        throw const RutokenNativeException(
          'Адрес, полученный от Рутокена, не совпал с BIP-39/BIP-32 эталоном.',
        );
      }
      final verifiedPublicAccount = WalletAccountPublicKey(
        account: imported,
        accountPath: publicAccount.accountPath,
        accountDepth: publicAccount.accountDepth,
        compressedPublicKey: publicAccount.compressedPublicKey,
        chainCode: publicAccount.chainCode,
        sourceFingerprint: publicAccount.sourceFingerprint,
        parentFingerprint: publicAccount.parentFingerprint,
      );
      await _writeMetadata(verifiedPublicAccount, state: 'active');
      if (closeError != null) {
        Error.throwWithStackTrace(closeError, closeStackTrace!);
      }
      return RutokenProvisioningResult(
        account: imported,
        publicAccount: verifiedPublicAccount,
      );
    } finally {
      seed?.fillRange(0, seed.length, 0);
      masterPrivateKey?.fillRange(0, masterPrivateKey.length, 0);
      masterChainCode?.fillRange(0, masterChainCode.length, 0);
    }
  }

  /// Registers a compatible card that already contains the supported BIP-32
  /// master. The token is read only; no key object is created or replaced.
  Future<WalletAccountDescriptor> adoptExisting({required String pin}) async {
    if (pin.isEmpty) {
      throw const RutokenNativeException('PIN Рутокена не должен быть пустым.');
    }
    final session = await _adapter.openSession(pin: pin);
    WalletAccountDescriptor? account;
    try {
      account = await _adapter.readAccountDescriptor(session);
      if (account == null) {
        throw const RutokenNativeException(
          'Рутокен не содержит совместимый BIP-32 кошелёк.',
        );
      }
      if (account.backendId != 'rutoken_nfc' ||
          account.derivationPath != addressPath ||
          !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(account.address)) {
        throw const RutokenNativeException(
          'Публичный профиль Рутокена имеет неподдерживаемый формат.',
        );
      }
    } finally {
      await _adapter.closeSession(session);
    }

    final existing = await loadAccountDescriptor();
    if (existing != null &&
        existing.address.toLowerCase() != account.address.toLowerCase()) {
      throw const RutokenNativeException(
        'На телефоне уже зарегистрирован другой Рутокен.',
      );
    }
    if (existing != null) {
      // Preserve any account-xpub fields retained during Wallet Demo
      // provisioning; adopting the same card must not downgrade AirGap.
      return account;
    }
    await _writeAccount(account);
    return account;
  }

  Future<WalletAccountDescriptor?> loadAccountDescriptor() async {
    final json = await _loadActiveMetadata();
    if (json == null) return null;
    try {
      return WalletAccountDescriptor(
        backendId: json['backendId'] as String,
        address: json['address'] as String,
        derivationPath: json['derivationPath'] as String,
      );
    } catch (_) {
      throw const RutokenNativeException(
        'Сохранённый публичный профиль Рутокена повреждён.',
      );
    }
  }

  Future<WalletAccountPublicKey?> loadPublicAccount() async {
    final json = await _loadActiveMetadata();
    if (json == null || json['compressedPublicKey'] == null) return null;
    try {
      final account = WalletAccountDescriptor(
        backendId: json['backendId'] as String,
        address: json['address'] as String,
        derivationPath: json['derivationPath'] as String,
      );
      return WalletAccountPublicKey(
        account: account,
        accountPath: json['accountPath'] as String,
        accountDepth: json['accountDepth'] as int,
        compressedPublicKey: base64Decode(
          json['compressedPublicKey'] as String,
        ),
        chainCode: base64Decode(json['chainCode'] as String),
        sourceFingerprint: json['sourceFingerprint'] as int,
        parentFingerprint: json['parentFingerprint'] as int,
      );
    } catch (_) {
      throw const RutokenNativeException(
        'Сохранённые публичные данные Рутокена повреждены.',
      );
    }
  }

  Future<Map<String, dynamic>?> _loadActiveMetadata() async {
    final raw = await _store.read(_metadataKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> ||
          (json['schema'] != 1 && json['schema'] != 2) ||
          json['state'] != 'active') {
        return null;
      }
      return json;
    } catch (_) {
      throw const RutokenNativeException(
        'Сохранённые публичные данные Рутокена повреждены.',
      );
    }
  }

  Future<void> _writeAccount(WalletAccountDescriptor account) {
    return _store.write(
      _metadataKey,
      jsonEncode(<String, Object>{
        'schema': 2,
        'state': 'active',
        'backendId': account.backendId,
        'address': account.address,
        'derivationPath': account.derivationPath,
      }),
    );
  }

  Future<void> _writeMetadata(
    WalletAccountPublicKey publicAccount, {
    required String state,
  }) {
    return _store.write(
      _metadataKey,
      jsonEncode(<String, Object>{
        'schema': 2,
        'state': state,
        'backendId': publicAccount.account.backendId,
        'address': publicAccount.account.address,
        'derivationPath': publicAccount.account.derivationPath,
        'accountPath': publicAccount.accountPath,
        'accountDepth': publicAccount.accountDepth,
        'compressedPublicKey': base64Encode(publicAccount.compressedPublicKey),
        'chainCode': base64Encode(publicAccount.chainCode),
        'sourceFingerprint': publicAccount.sourceFingerprint,
        'parentFingerprint': publicAccount.parentFingerprint,
      }),
    );
  }

  Uint8List _uncompressedXY(Uint8List compressed) =>
      RutokenEcPoint.decode(compressed).uncompressedXY;

  int _asUint32(Uint8List value) =>
      value.buffer.asByteData(value.offsetInBytes, 4).getUint32(0);

  String _normalizeMnemonic(String mnemonic) => mnemonic
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .join(' ');
}
