import 'dart:typed_data';

import 'key_storage_backend.dart';
import 'rutoken_biometric_pin_store.dart';

/// Public identity of one custody-backed EVM account. It is safe to keep while
/// the signer is locked: no seed or private key is represented here.
class WalletAccountDescriptor {
  const WalletAccountDescriptor({
    required this.backendId,
    required this.address,
    required this.derivationPath,
  });

  final String backendId;
  final String address;
  final String derivationPath;
}

/// Public account-level BIP-32 data used by EIP-4527 `crypto-hdkey` export.
/// For Rutoken this is software-retained provisioning metadata: the minimal
/// PKCS#11 signing adapter does not expose an account xpub or chain code.
class WalletAccountPublicKey {
  WalletAccountPublicKey({
    required this.account,
    required this.accountPath,
    required this.accountDepth,
    required Uint8List compressedPublicKey,
    required Uint8List chainCode,
    required this.sourceFingerprint,
    required this.parentFingerprint,
  }) : compressedPublicKey = Uint8List.fromList(compressedPublicKey),
       chainCode = Uint8List.fromList(chainCode) {
    if (this.compressedPublicKey.length != 33) {
      throw ArgumentError.value(
        this.compressedPublicKey.length,
        'compressedPublicKey',
        'Expected a 33-byte compressed secp256k1 public key.',
      );
    }
    if (this.chainCode.length != 32) {
      throw ArgumentError.value(
        this.chainCode.length,
        'chainCode',
        'Expected a 32-byte BIP-32 chain code.',
      );
    }
  }

  final WalletAccountDescriptor account;
  final String accountPath;
  final int accountDepth;
  final Uint8List compressedPublicKey;
  final Uint8List chainCode;
  final int sourceFingerprint;
  final int parentFingerprint;
}

/// Raw PKCS#11 `CKM_ECDSA` result. Rutoken is expected to return `r || s`
/// without a recovery id; the EVM layer validates, canonicalizes, and recovers
/// it against [WalletAccountDescriptor.address].
class RawEcdsaSignature {
  RawEcdsaSignature({required Uint8List r, required Uint8List s})
    : r = Uint8List.fromList(r),
      s = Uint8List.fromList(s) {
    if (this.r.length != 32 || this.s.length != 32) {
      throw ArgumentError('ECDSA r and s must each be exactly 32 bytes.');
    }
  }

  factory RawEcdsaSignature.fromBytes(Uint8List bytes) {
    if (bytes.length != 64) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'Expected raw 64-byte r || s signature.',
      );
    }
    return RawEcdsaSignature(
      r: Uint8List.sublistView(bytes, 0, 32),
      s: Uint8List.sublistView(bytes, 32, 64),
    );
  }

  final Uint8List r;
  final Uint8List s;

  Uint8List toBytes() => Uint8List.fromList(<int>[...r, ...s]);
}

/// One authenticated custody operation. Implementations own the native/NFC
/// session and must make [close] idempotent.
abstract interface class CustodySigningSession {
  WalletAccountDescriptor get account;

  Future<RawEcdsaSignature> signDigest(Uint8List digest);

  Future<void> close();
}

/// Secret-free backend capability consumed by app orchestration. The eventual
/// Rutoken backend implements this without implementing `unlock() ->
/// WalletMaterial`.
abstract interface class WalletCustodyBackend implements WalletBackend {
  Future<WalletAccountDescriptor> readAccountDescriptor({required String pin});

  Future<CustodySigningSession> openSigningSession({required String pin});

  Future<WalletAccountPublicKey> readAccountPublicKey({required String pin});
}

/// Native boundary to be implemented by the Android Kotlin and iOS Swift
/// wrappers around the vendor PC/SC + PKCS#11 stack.
abstract interface class RutokenNativeAdapter {
  Future<RutokenNativeSession> openSession({required String pin});

  /// Cancels the currently pending NFC discovery, if any. Native signing and
  /// PKCS#11 calls that already started remain atomic.
  Future<void> cancelPendingOperation();

  Future<WalletAccountDescriptor?> readAccountDescriptor(
    RutokenNativeSession session,
  );

  Future<RawEcdsaSignature> signDigest({
    required RutokenNativeSession session,
    required String derivationPath,
    required Uint8List digest,
  });

  /// `C_CreateObject` import of the BIP-32 master private key + chain code
  /// derived in software from an imported or newly generated mnemonic. This is
  /// the only provisioning primitive demonstrated by the Android reference.
  /// The adapter must not retain the input buffers after the call.
  Future<WalletAccountDescriptor> importWallet({
    required RutokenNativeSession session,
    required Uint8List masterPrivateKey,
    required Uint8List chainCode,
  });

  Future<void> closeSession(RutokenNativeSession session);
}

class RutokenNativeSession {
  const RutokenNativeSession({
    required this.id,
    required this.openedAtUtc,
    this.serial,
    this.label,
    this.model,
  });

  final String id;
  final DateTime openedAtUtc;

  /// Token identity reported when the session opened. Null when the transport
  /// does not report it (a test fake, or a platform whose bridge predates it).
  /// [serial] is what tells two otherwise-identical cards apart in the picker;
  /// it is public token metadata, not key material.
  final String? serial;
  final String? label;
  final String? model;
}

/// Hardware backend implementation independent of Flutter platform channels.
/// Inject a Kotlin/Swift-backed [RutokenNativeAdapter] when the vendor binaries
/// arrive; tests inject a pure-Dart fake.
class RutokenCustodyBackend implements WalletCustodyBackend {
  const RutokenCustodyBackend({
    required RutokenNativeAdapter adapter,
    WalletAccountPublicKey? publicAccountMetadata,
    Future<WalletAccountPublicKey?> Function()? publicAccountLoader,
    Future<WalletAccountDescriptor?> Function()? accountLoader,
    RutokenBiometricPinStore? biometricPinStore,
    this.backendId = 'rutoken_nfc',
  }) : _adapter = adapter,
       _publicAccountMetadata = publicAccountMetadata,
       _publicAccountLoader = publicAccountLoader,
       _accountLoader = accountLoader,
       _biometricPinStore = biometricPinStore;

  final RutokenNativeAdapter _adapter;
  final WalletAccountPublicKey? _publicAccountMetadata;
  final Future<WalletAccountPublicKey?> Function()? _publicAccountLoader;
  final Future<WalletAccountDescriptor?> Function()? _accountLoader;
  final RutokenBiometricPinStore? _biometricPinStore;
  @override
  final String backendId;

  @override
  bool get isUnlocked => false;

  Future<WalletAccountPublicKey?> _loadPublicAccount() async {
    final metadata = _publicAccountMetadata;
    if (metadata != null) {
      return metadata;
    }
    return _publicAccountLoader?.call();
  }

  Future<WalletAccountDescriptor?> _loadRegisteredAccount() async {
    final account = await _accountLoader?.call();
    if (account != null) {
      return account;
    }
    return (await _loadPublicAccount())?.account;
  }

  @override
  Future<bool> hasWallet() async => await _loadRegisteredAccount() != null;

  @override
  Future<StoredWalletSummary?> getWalletSummary() async {
    final account = await _loadRegisteredAccount();
    if (account == null) {
      return null;
    }
    return StoredWalletSummary(
      address: account.address,
      backendId: backendId,
      // v1 public metadata intentionally did not persist a creation timestamp.
      // The dashboard does not expose it; keep a stable sentinel rather than
      // inventing a new time on every app start.
      createdAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  @override
  Future<bool> isBiometricUnlockAvailable() async {
    return await _biometricPinStore?.isAvailable() ?? false;
  }

  @override
  Future<bool> isBiometricUnlockEnabled() async {
    final account = await _loadRegisteredAccount();
    if (account == null) {
      return false;
    }
    return await _biometricPinStore?.isEnabled(account.address) ?? false;
  }

  @override
  void lock() {}

  @override
  Future<WalletAccountDescriptor> readAccountDescriptor({
    required String pin,
  }) async {
    final native = await _adapter.openSession(pin: pin);
    Object? primaryFailure;
    try {
      final account = await _adapter.readAccountDescriptor(native);
      if (account == null) {
        throw StateError('Rutoken does not contain a configured wallet.');
      }
      await _verifyRegisteredAccount(account);
      return account;
    } catch (error) {
      primaryFailure = error;
      rethrow;
    } finally {
      try {
        await _adapter.closeSession(native);
      } catch (_) {
        if (primaryFailure == null) rethrow;
      }
    }
  }

  @override
  Future<CustodySigningSession> openSigningSession({
    required String pin,
  }) async {
    final native = await _adapter.openSession(pin: pin);
    try {
      final account = await _adapter.readAccountDescriptor(native);
      if (account == null) {
        throw StateError('Rutoken does not contain a configured wallet.');
      }
      await _verifyRegisteredAccount(account);
      return _RutokenCustodySigningSession(
        adapter: _adapter,
        native: native,
        account: account,
      );
    } catch (error, stackTrace) {
      try {
        await _adapter.closeSession(native);
      } catch (_) {
        // Preserve the address-read/binding failure; teardown is best effort
        // and must not hide why no signature was produced.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<WalletAccountPublicKey> readAccountPublicKey({
    required String pin,
  }) async {
    final metadata = await _loadPublicAccount();
    if (metadata == null) {
      throw StateError(
        'Для этой готовой карты на телефоне нет account xpub: '
        'AirGap export доступен только после создания или импорта ключа '
        'через Wallet Demo.',
      );
    }
    return metadata;
  }

  Future<bool> shouldOfferBiometricPin() async {
    final account = await _loadRegisteredAccount();
    if (account == null) {
      return false;
    }
    return await _biometricPinStore?.shouldOffer(account.address) ?? false;
  }

  Future<void> enableBiometricPin(String pin) async {
    final account = await _requireRegisteredAccount();
    final store = _biometricPinStore;
    if (store == null) {
      throw const BiometricUnavailableFailure();
    }
    await store.enable(address: account.address, pin: pin);
  }

  Future<void> declineBiometricPin() async {
    final account = await _requireRegisteredAccount();
    await _biometricPinStore?.decline(account.address);
  }

  Future<String> retrievePinWithBiometrics() async {
    final account = await _requireRegisteredAccount();
    final store = _biometricPinStore;
    if (store == null) {
      throw const BiometricUnavailableFailure();
    }
    return store.retrieve(account.address);
  }

  Future<WalletAccountDescriptor> _requireRegisteredAccount() async {
    final account = await _loadRegisteredAccount();
    if (account == null) {
      throw StateError('Rutoken does not have a registered public profile.');
    }
    return account;
  }

  Future<void> _verifyRegisteredAccount(WalletAccountDescriptor actual) async {
    final expected = await _loadRegisteredAccount();
    if (expected == null) {
      return;
    }
    if (actual.derivationPath != expected.derivationPath ||
        actual.address.toLowerCase() != expected.address.toLowerCase()) {
      throw const VaultFailure(
        'Поднесён другой Рутокен: адрес карты не совпадает с активным кошельком.',
      );
    }
  }
}

class _RutokenCustodySigningSession implements CustodySigningSession {
  _RutokenCustodySigningSession({
    required RutokenNativeAdapter adapter,
    required RutokenNativeSession native,
    required this.account,
  }) : _adapter = adapter,
       _native = native;

  final RutokenNativeAdapter _adapter;
  final RutokenNativeSession _native;
  bool _closed = false;

  @override
  final WalletAccountDescriptor account;

  @override
  Future<RawEcdsaSignature> signDigest(Uint8List digest) {
    if (_closed) {
      throw StateError('Rutoken signing session is already closed.');
    }
    if (digest.length != 32) {
      throw ArgumentError.value(
        digest.length,
        'digest',
        'Rutoken CKM_ECDSA expects a precomputed 32-byte digest.',
      );
    }
    return _adapter.signDigest(
      session: _native,
      derivationPath: account.derivationPath,
      digest: digest,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _adapter.closeSession(_native);
  }
}
