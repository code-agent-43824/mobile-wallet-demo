import 'dart:typed_data';

import '../key_storage/key_storage_backend.dart';
import '../transactions/transaction_service.dart';

enum WalletAuthMethod { pin, biometric, externalDevice, remoteSession }

abstract interface class WalletTransactionSigner {
  String get backendId;
  String get address;

  Future<SignedTransfer> signPreparedTransfer({
    required TransactionService transactionService,
    required PreparedTransfer preparedTransfer,
    required int nonce,
  });
}

class AuthorizedWalletOperation {
  const AuthorizedWalletOperation({
    required this.backendId,
    required this.address,
    required this.authMethod,
    required this.signer,
  });

  final String backendId;
  final String address;
  final WalletAuthMethod authMethod;
  final WalletTransactionSigner signer;
}

/// Base for signers that hold local [WalletMaterial] and produce the signature
/// in-process. Both the phone-vault path and the (simulated) external-device
/// path use this in the demo. A real hardware integration would add a signer
/// that routes the prepared transaction to the device and returns the device's
/// signature instead of signing locally.
abstract class WalletMaterialTransactionSigner
    implements WalletTransactionSigner {
  const WalletMaterialTransactionSigner({
    required this.backendId,
    required this.walletMaterial,
  });

  @override
  final String backendId;
  final WalletMaterial walletMaterial;

  @override
  String get address => walletMaterial.address;

  @override
  Future<SignedTransfer> signPreparedTransfer({
    required TransactionService transactionService,
    required PreparedTransfer preparedTransfer,
    required int nonce,
  }) async {
    // Local signing is synchronous; the async contract lets remote/external
    // signers (WalletConnect, AirGap) implement the same seam.
    return transactionService.signPreparedTransfer(
      preparedTransfer: preparedTransfer,
      walletMaterial: walletMaterial,
      nonce: nonce,
    );
  }
}

class LocalKeyMaterialTransactionSigner
    extends WalletMaterialTransactionSigner {
  const LocalKeyMaterialTransactionSigner({
    required super.backendId,
    required super.walletMaterial,
  });
}

/// Used when the active backend is the (simulated) external device. In this
/// demo it still signs from locally held key material; the device session is
/// exercised separately through the PKCS#11 sign operation before signing, and
/// a real SDK would move signing onto the device entirely.
class ExternalDeviceTransactionSigner extends WalletMaterialTransactionSigner {
  const ExternalDeviceTransactionSigner({
    required super.backendId,
    required super.walletMaterial,
  });
}

/// Obtains a signed transaction from an external party (a connected
/// WalletConnect wallet, an offline AirGap device, ...). It never holds the
/// private key: it hands the prepared transaction to the external signer and
/// returns the raw signed transaction bytes. WalletConnect (chunk C) and AirGap
/// (chunk D) will provide concrete implementations.
abstract interface class RemoteSigningTransport {
  /// Short label of the transport, e.g. `walletconnect` or `airgap`.
  String get label;

  Future<Uint8List> requestSignedTransaction({
    required PreparedTransfer preparedTransfer,
    required int nonce,
    required String fromAddress,
  });
}

/// Async signer backed by a [RemoteSigningTransport]. Holds no key material; it
/// asks the transport to sign and assembles the resulting [SignedTransfer] via
/// [TransactionService.assembleSignedTransfer].
class RemoteWalletTransactionSigner implements WalletTransactionSigner {
  const RemoteWalletTransactionSigner({
    required this.backendId,
    required this.address,
    required this.transport,
  });

  @override
  final String backendId;

  @override
  final String address;

  final RemoteSigningTransport transport;

  @override
  Future<SignedTransfer> signPreparedTransfer({
    required TransactionService transactionService,
    required PreparedTransfer preparedTransfer,
    required int nonce,
  }) async {
    final rawSigned = await transport.requestSignedTransaction(
      preparedTransfer: preparedTransfer,
      nonce: nonce,
      fromAddress: address,
    );
    return transactionService.assembleSignedTransfer(
      preparedTransfer: preparedTransfer,
      rawSignedTransaction: rawSigned,
      signingNote:
          'Транзакция подписана внешним signer через ${transport.label}.',
    );
  }
}

class WalletOperationAuthorizer {
  const WalletOperationAuthorizer();

  AuthorizedWalletOperation authorizeUnlockedLocalSigning({
    required KeyStorageBackend backend,
    required WalletMaterial? walletMaterial,
    required WalletAuthMethod authMethod,
  }) {
    _assertUnlocked(backend: backend, walletMaterial: walletMaterial);

    return AuthorizedWalletOperation(
      backendId: backend.backendId,
      address: walletMaterial!.address,
      authMethod: authMethod,
      signer: LocalKeyMaterialTransactionSigner(
        backendId: backend.backendId,
        walletMaterial: walletMaterial,
      ),
    );
  }

  AuthorizedWalletOperation authorizeUnlockedExternalDeviceSigning({
    required ExternalDeviceKeyStorageBackend backend,
    required WalletMaterial? walletMaterial,
  }) {
    _assertUnlocked(backend: backend, walletMaterial: walletMaterial);

    return AuthorizedWalletOperation(
      backendId: backend.backendId,
      address: walletMaterial!.address,
      authMethod: WalletAuthMethod.externalDevice,
      signer: ExternalDeviceTransactionSigner(
        backendId: backend.backendId,
        walletMaterial: walletMaterial,
      ),
    );
  }

  /// Authorizes signing through an external session-driven signer (WalletConnect
  /// / AirGap). Unlike the local/external-device paths this does not unlock a
  /// local vault — the key lives with the remote party, and connection-state
  /// checks belong to the transport's own session model.
  AuthorizedWalletOperation authorizeRemoteSigning({
    required String backendId,
    required String address,
    required RemoteSigningTransport transport,
  }) {
    return AuthorizedWalletOperation(
      backendId: backendId,
      address: address,
      authMethod: WalletAuthMethod.remoteSession,
      signer: RemoteWalletTransactionSigner(
        backendId: backendId,
        address: address,
        transport: transport,
      ),
    );
  }

  void _assertUnlocked({
    required KeyStorageBackend backend,
    required WalletMaterial? walletMaterial,
  }) {
    if (!backend.isUnlocked || walletMaterial == null) {
      throw const VaultFailure('Wallet backend is locked for signing.');
    }
  }
}
