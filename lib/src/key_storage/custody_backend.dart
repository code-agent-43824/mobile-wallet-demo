import 'dart:typed_data';

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
/// A Rutoken implementation reads these fields from the device; it must never
/// reconstruct them by exporting a private key.
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
abstract interface class WalletCustodyBackend {
  Future<WalletAccountDescriptor> readAccountDescriptor({required String pin});

  Future<CustodySigningSession> openSigningSession({required String pin});

  Future<WalletAccountPublicKey> readAccountPublicKey({required String pin});
}

/// Native boundary to be implemented by the Android Kotlin and iOS Swift
/// wrappers around the vendor PC/SC + PKCS#11 stack.
abstract interface class RutokenNativeAdapter {
  Future<RutokenNativeSession> openSession({required String pin});

  Future<WalletAccountDescriptor?> readAccountDescriptor(
    RutokenNativeSession session,
  );

  Future<WalletAccountPublicKey> readAccountPublicKey(
    RutokenNativeSession session,
  );

  Future<RawEcdsaSignature> signDigest({
    required RutokenNativeSession session,
    required String derivationPath,
    required Uint8List digest,
  });

  /// `CKM_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN`. [mnemonic] is populated only
  /// when the token policy explicitly allows the one-time backup display.
  Future<RutokenProvisioningResult> generateWallet({
    required RutokenNativeSession session,
    int mnemonicWordCount = 24,
    String? passphrase,
  });

  /// `C_CreateObject` import of the BIP-32 master private key + chain code
  /// derived from the user-provided mnemonic. The adapter must not retain the
  /// input buffers after the call.
  Future<WalletAccountDescriptor> importWallet({
    required RutokenNativeSession session,
    required Uint8List masterPrivateKey,
    required Uint8List chainCode,
  });

  Future<void> closeSession(RutokenNativeSession session);
}

class RutokenNativeSession {
  const RutokenNativeSession({required this.id, required this.openedAtUtc});

  final String id;
  final DateTime openedAtUtc;
}

class RutokenProvisioningResult {
  const RutokenProvisioningResult({required this.account, this.mnemonic});

  final WalletAccountDescriptor account;
  final String? mnemonic;
}

/// Hardware backend implementation independent of Flutter platform channels.
/// Inject a Kotlin/Swift-backed [RutokenNativeAdapter] when the vendor binaries
/// arrive; tests inject a pure-Dart fake.
class RutokenCustodyBackend implements WalletCustodyBackend {
  const RutokenCustodyBackend({
    required RutokenNativeAdapter adapter,
    this.backendId = 'rutoken_nfc',
  }) : _adapter = adapter;

  final RutokenNativeAdapter _adapter;
  final String backendId;

  @override
  Future<WalletAccountDescriptor> readAccountDescriptor({
    required String pin,
  }) async {
    final native = await _adapter.openSession(pin: pin);
    try {
      final account = await _adapter.readAccountDescriptor(native);
      if (account == null) {
        throw StateError('Rutoken does not contain a configured wallet.');
      }
      return account;
    } finally {
      await _adapter.closeSession(native);
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
      return _RutokenCustodySigningSession(
        adapter: _adapter,
        native: native,
        account: account,
      );
    } catch (_) {
      await _adapter.closeSession(native);
      rethrow;
    }
  }

  @override
  Future<WalletAccountPublicKey> readAccountPublicKey({
    required String pin,
  }) async {
    final native = await _adapter.openSession(pin: pin);
    try {
      return await _adapter.readAccountPublicKey(native);
    } finally {
      await _adapter.closeSession(native);
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
