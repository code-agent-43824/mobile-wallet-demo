import '../key_storage/key_storage_backend.dart';
import '../transactions/transaction_service.dart';

enum WalletAuthMethod { pin, biometric, externalDevice }

abstract interface class WalletTransactionSigner {
  String get backendId;
  String get address;

  SignedTransfer signPreparedTransfer({
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
  SignedTransfer signPreparedTransfer({
    required TransactionService transactionService,
    required PreparedTransfer preparedTransfer,
    required int nonce,
  }) {
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

  void _assertUnlocked({
    required KeyStorageBackend backend,
    required WalletMaterial? walletMaterial,
  }) {
    if (!backend.isUnlocked || walletMaterial == null) {
      throw const VaultFailure('Wallet backend is locked for signing.');
    }
  }
}
