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

/// One registered card, as the phone remembers it between taps.
///
/// Everything here is public: an address, a derivation path, the token's own
/// serial and label. Nothing that could reconstruct a key is stored — that is
/// the whole point of the custody backend.
class RutokenCardProfile {
  const RutokenCardProfile({
    required this.id,
    required this.account,
    this.publicAccount,
    this.serial,
    this.label,
  });

  /// Stable identity of the profile: the lowercased address. Two cards holding
  /// the same key *are* the same wallet, so the address is the right key —
  /// and unlike the serial it exists for profiles registered before the
  /// serial was read (v1.53 and earlier).
  final String id;

  final WalletAccountDescriptor account;

  /// Account-level BIP-32 metadata for EIP-4527 export. Null for a card adopted
  /// read-only, which cannot synthesize it.
  final WalletAccountPublicKey? publicAccount;

  /// The token's own serial, when the transport reported it.
  final String? serial;

  /// The token's own label, when the transport reported it.
  final String? label;

  static String idForAddress(String address) => address.toLowerCase();
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
      // The token's own identity, reported when the session opened. Recorded so
      // the picker can tell two cards apart by more than their address.
      final serial = session.serial;
      final tokenLabel = session.label;
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
      await _writeMetadata(
        verifiedPublicAccount,
        state: 'active',
        serial: serial,
        label: tokenLabel,
      );
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
    final serial = session.serial;
    final tokenLabel = session.label;
    WalletAccountDescriptor? account;
    Object? primaryFailure;
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
    } catch (error) {
      primaryFailure = error;
      rethrow;
    } finally {
      try {
        await _adapter.closeSession(session);
      } catch (_) {
        if (primaryFailure == null) rethrow;
      }
    }

    // A card the phone already knows keeps everything it has — in particular
    // the account xpub retained when its key was created here, which adoption
    // alone cannot reconstruct. A card it does not know becomes an additional
    // profile rather than being refused: several registered cards is the point
    // of Phase 14. Either way the adopted card becomes the selected one, since
    // connecting it is a deliberate act.
    final profileId = RutokenCardProfile.idForAddress(account.address);
    final known = (await loadProfiles()).any(
      (profile) => profile.id == profileId,
    );
    if (known) {
      await _recordTokenIdentity(profileId, serial: serial, label: tokenLabel);
      await selectProfile(profileId);
      return account;
    }
    await _writeAccount(account, serial: serial, label: tokenLabel);
    return account;
  }

  /// Adds the token's own serial/label to an already-registered profile,
  /// leaving every other field — including the account xpub — untouched.
  Future<void> _recordTokenIdentity(
    String profileId, {
    String? serial,
    String? label,
  }) async {
    if (serial == null && label == null) return;
    final document = await _loadDocument();
    final profiles = _entries(document);
    final index = profiles.indexWhere((entry) => entry['id'] == profileId);
    if (index == -1) return;
    final updated = Map<String, dynamic>.from(profiles[index]);
    if (serial != null) updated['serial'] = serial;
    if (label != null) updated['label'] = label;
    profiles[index] = updated;
    document['profiles'] = profiles;
    await _writeDocument(document);
  }

  /// Every registered card, in registration order. Half-written entries left by
  /// a process death mid-provisioning are excluded — they are recovery evidence,
  /// not usable wallets.
  Future<List<RutokenCardProfile>> loadProfiles() async {
    final document = await _loadDocument();
    return _activeEntries(document).map(_profileFromJson).toList();
  }

  /// The card operations act on, or null when none is registered.
  Future<RutokenCardProfile?> loadSelectedProfile() async {
    final document = await _loadDocument();
    final entry = _selectedEntry(document);
    return entry == null ? null : _profileFromJson(entry);
  }

  /// Points later operations at [profileId]. Unknown or half-written ids are
  /// refused rather than silently clearing the selection — an operation must
  /// never end up bound to "no card in particular".
  Future<void> selectProfile(String profileId) async {
    final document = await _loadDocument();
    final exists = _activeEntries(
      document,
    ).any((entry) => entry['id'] == profileId);
    if (!exists) {
      throw const RutokenNativeException('Такая карта не зарегистрирована.');
    }
    document['selectedId'] = profileId;
    await _writeDocument(document);
  }

  Future<WalletAccountDescriptor?> loadAccountDescriptor() async {
    final entry = _selectedEntry(await _loadDocument());
    if (entry == null) return null;
    try {
      return _accountFromJson(entry);
    } catch (_) {
      throw const RutokenNativeException(
        'Сохранённый публичный профиль Рутокена повреждён.',
      );
    }
  }

  Future<WalletAccountPublicKey?> loadPublicAccount() async {
    final entry = _selectedEntry(await _loadDocument());
    if (entry == null || entry['compressedPublicKey'] == null) return null;
    try {
      return _publicAccountFromJson(entry);
    } catch (_) {
      throw const RutokenNativeException(
        'Сохранённые публичные данные Рутокена повреждены.',
      );
    }
  }

  // --- persistence -----------------------------------------------------------
  //
  // One JSON document under [_metadataKey]: a list of card profiles plus the
  // id of the selected one. Schemas 1 and 2 held a single profile inline, so
  // they are migrated on read — an install that registered a card before v1.55
  // keeps it, still selected, without touching the token.

  Future<Map<String, dynamic>> _loadDocument() async {
    final raw = await _store.read(_metadataKey);
    if (raw == null) return _emptyDocument();
    Object? json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      throw const RutokenNativeException(
        'Сохранённые публичные данные Рутокена повреждены.',
      );
    }
    if (json is! Map<String, dynamic>) {
      throw const RutokenNativeException(
        'Сохранённые публичные данные Рутокена повреждены.',
      );
    }
    final schema = json['schema'];
    if (schema == 3) return json;
    if (schema == 1 || schema == 2) return _migrateSingleProfile(json);
    // A newer schema from a downgraded install: refuse rather than guess, so a
    // future format cannot be silently truncated back to this one.
    throw const RutokenNativeException(
      'Сохранённые публичные данные Рутокена повреждены.',
    );
  }

  Map<String, dynamic> _emptyDocument() => <String, dynamic>{
    'schema': 3,
    'selectedId': null,
    'profiles': <Map<String, dynamic>>[],
  };

  /// Schemas 1/2 → 3. The single record becomes the one profile, selected when
  /// it was active; a `pending` record migrates as pending and stays unusable,
  /// preserving the crash-recovery marker rather than promoting it.
  Map<String, dynamic> _migrateSingleProfile(Map<String, dynamic> json) {
    final address = json['address'];
    if (address is! String || address.isEmpty) {
      throw const RutokenNativeException(
        'Сохранённые публичные данные Рутокена повреждены.',
      );
    }
    final id = RutokenCardProfile.idForAddress(address);
    final entry = Map<String, dynamic>.from(json)
      ..remove('schema')
      ..['id'] = id;
    return <String, dynamic>{
      'schema': 3,
      'selectedId': json['state'] == 'active' ? id : null,
      'profiles': <Map<String, dynamic>>[entry],
    };
  }

  Future<void> _writeDocument(Map<String, dynamic> document) =>
      _store.write(_metadataKey, jsonEncode(document));

  List<Map<String, dynamic>> _entries(Map<String, dynamic> document) {
    final profiles = document['profiles'];
    if (profiles is! List) {
      throw const RutokenNativeException(
        'Сохранённые публичные данные Рутокена повреждены.',
      );
    }
    return profiles.whereType<Map<String, dynamic>>().toList();
  }

  List<Map<String, dynamic>> _activeEntries(Map<String, dynamic> document) =>
      _entries(document).where((entry) => entry['state'] == 'active').toList();

  Map<String, dynamic>? _selectedEntry(Map<String, dynamic> document) {
    final selectedId = document['selectedId'];
    if (selectedId is! String) return null;
    for (final entry in _activeEntries(document)) {
      if (entry['id'] == selectedId) return entry;
    }
    return null;
  }

  WalletAccountDescriptor _accountFromJson(Map<String, dynamic> json) =>
      WalletAccountDescriptor(
        backendId: json['backendId'] as String,
        address: json['address'] as String,
        derivationPath: json['derivationPath'] as String,
      );

  WalletAccountPublicKey _publicAccountFromJson(Map<String, dynamic> json) =>
      WalletAccountPublicKey(
        account: _accountFromJson(json),
        accountPath: json['accountPath'] as String,
        accountDepth: json['accountDepth'] as int,
        compressedPublicKey: base64Decode(
          json['compressedPublicKey'] as String,
        ),
        chainCode: base64Decode(json['chainCode'] as String),
        sourceFingerprint: json['sourceFingerprint'] as int,
        parentFingerprint: json['parentFingerprint'] as int,
      );

  RutokenCardProfile _profileFromJson(Map<String, dynamic> json) {
    try {
      return RutokenCardProfile(
        id: json['id'] as String,
        account: _accountFromJson(json),
        publicAccount: json['compressedPublicKey'] == null
            ? null
            : _publicAccountFromJson(json),
        serial: json['serial'] as String?,
        label: json['label'] as String?,
      );
    } catch (_) {
      throw const RutokenNativeException(
        'Сохранённый публичный профиль Рутокена повреждён.',
      );
    }
  }

  /// Inserts or replaces one profile, keeping registration order. Selecting it
  /// is deliberately tied to becoming `active`: a half-written entry must never
  /// be the card an operation binds to.
  Future<void> _upsertProfile(
    Map<String, dynamic> entry, {
    required String state,
  }) async {
    final document = await _loadDocument();
    final id = entry['id'] as String;
    final profiles = _entries(document);
    final stored = Map<String, dynamic>.from(entry)..['state'] = state;
    final index = profiles.indexWhere((existing) => existing['id'] == id);
    if (index == -1) {
      profiles.add(stored);
    } else {
      profiles[index] = stored;
    }
    document['profiles'] = profiles;
    if (state == 'active') {
      document['selectedId'] = id;
    } else if (document['selectedId'] == id) {
      // Re-provisioning the selected card makes it unusable until the write
      // completes, which is what the pending marker has always meant.
      document['selectedId'] = null;
    }
    await _writeDocument(document);
  }

  Future<void> _writeAccount(
    WalletAccountDescriptor account, {
    String? serial,
    String? label,
  }) {
    return _upsertProfile(<String, dynamic>{
      'id': RutokenCardProfile.idForAddress(account.address),
      'backendId': account.backendId,
      'address': account.address,
      'derivationPath': account.derivationPath,
      'serial': ?serial,
      'label': ?label,
    }, state: 'active');
  }

  Future<void> _writeMetadata(
    WalletAccountPublicKey publicAccount, {
    required String state,
    String? serial,
    String? label,
  }) {
    return _upsertProfile(<String, dynamic>{
      'id': RutokenCardProfile.idForAddress(publicAccount.account.address),
      'backendId': publicAccount.account.backendId,
      'address': publicAccount.account.address,
      'derivationPath': publicAccount.account.derivationPath,
      'accountPath': publicAccount.accountPath,
      'accountDepth': publicAccount.accountDepth,
      'compressedPublicKey': base64Encode(publicAccount.compressedPublicKey),
      'chainCode': base64Encode(publicAccount.chainCode),
      'sourceFingerprint': publicAccount.sourceFingerprint,
      'parentFingerprint': publicAccount.parentFingerprint,
      'serial': ?serial,
      'label': ?label,
    }, state: state);
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
