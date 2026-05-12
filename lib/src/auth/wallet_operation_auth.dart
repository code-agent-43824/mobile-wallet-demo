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

class LocalKeyMaterialTransactionSigner implements WalletTransactionSigner {
  const LocalKeyMaterialTransactionSigner({
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

class ExternalDeviceTransactionSigner implements WalletTransactionSigner {
  const ExternalDeviceTransactionSigner({
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
