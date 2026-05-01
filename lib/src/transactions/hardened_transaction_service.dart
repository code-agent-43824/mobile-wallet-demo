import '../blockchain/blockchain_provider.dart';
import '../blockchain/network_config.dart';
import '../key_storage/key_storage_backend.dart';
import 'transaction_service.dart';
import 'transaction_tracker.dart';

abstract interface class HardenedTransactionService
    implements TransactionService {
  Future<HardenedSubmitResult> submitTransferFlow({
    required WalletChainSnapshot snapshot,
    required String fromAddress,
    required String toAddress,
    required String amountText,
    required TransferAssetOption asset,
    required WalletMaterial walletMaterial,
    required TransactionBroadcaster broadcaster,
    required NonceProvider nonceProvider,
    required TransactionTracker tracker,
    int maxAttempts = 3,
    double gasBumpMultiplier = 1.15,
  });
}

class HardenedTransactionServiceImplementation
    implements HardenedTransactionService {
  const HardenedTransactionServiceImplementation();

  @override
  List<TransferAssetOption> availableAssets({
    required WalletChainSnapshot snapshot,
    required EvmNetworkConfig networkConfig,
  }) {
    return const ReadOnlyTransactionService().availableAssets(
      snapshot: snapshot,
      networkConfig: networkConfig,
    );
  }

  @override
  TransferPreview preparePreview({
    required WalletChainSnapshot snapshot,
    required String fromAddress,
    required String toAddress,
    required String amountText,
    required TransferAssetOption asset,
  }) {
    return const ReadOnlyTransactionService().preparePreview(
      snapshot: snapshot,
      fromAddress: fromAddress,
      toAddress: toAddress,
      amountText: amountText,
      asset: asset,
    );
  }

  @override
  PreparedTransfer prepareTransfer({
    required WalletChainSnapshot snapshot,
    required String fromAddress,
    required String toAddress,
    required String amountText,
    required TransferAssetOption asset,
    double gasMultiplier = 1.0,
  }) {
    return const ReadOnlyTransactionService().prepareTransfer(
      snapshot: snapshot,
      fromAddress: fromAddress,
      toAddress: toAddress,
      amountText: amountText,
      asset: asset,
      gasMultiplier: gasMultiplier,
    );
  }

  @override
  SignedTransfer signPreparedTransfer({
    required PreparedTransfer preparedTransfer,
    required WalletMaterial walletMaterial,
    required int nonce,
  }) {
    return const ReadOnlyTransactionService().signPreparedTransfer(
      preparedTransfer: preparedTransfer,
      walletMaterial: walletMaterial,
      nonce: nonce,
    );
  }

  @override
  Future<SubmittedTransfer> submitSignedTransfer({
    required SignedTransfer signedTransfer,
    required TransactionBroadcaster broadcaster,
  }) {
    return const ReadOnlyTransactionService().submitSignedTransfer(
      signedTransfer: signedTransfer,
      broadcaster: broadcaster,
    );
  }

  @override
  Future<TransactionReceipt> trackTransaction({
    required SubmittedTransfer submittedTransfer,
    required JsonRpcTransport rpcTransport,
  }) {
    final tracker = TransactionTracker(rpcTransport: rpcTransport);
    return tracker.waitForReceipt(
      networkConfig: submittedTransfer.signedTransfer.networkConfig,
      transactionHash: submittedTransfer.networkTransactionHash,
    );
  }

  @override
  Future<HardenedSubmitResult> submitTransferFlow({
    required WalletChainSnapshot snapshot,
    required String fromAddress,
    required String toAddress,
    required String amountText,
    required TransferAssetOption asset,
    required WalletMaterial walletMaterial,
    required TransactionBroadcaster broadcaster,
    required NonceProvider nonceProvider,
    required TransactionTracker tracker,
    int maxAttempts = 3,
    double gasBumpMultiplier = 1.15,
  }) async {
    var attempts = 0;
    var gasMultiplier = 1.0;
    var replacementUsed = false;

    while (true) {
      attempts += 1;
      final preparedTransfer = prepareTransfer(
        snapshot: snapshot,
        fromAddress: fromAddress,
        toAddress: toAddress,
        amountText: amountText,
        asset: asset,
        gasMultiplier: gasMultiplier,
      );
      final loadedNonce = await nonceProvider.loadNextNonce(
        networkConfig: preparedTransfer.networkConfig,
        address: fromAddress,
      );
      final signedTransfer = signPreparedTransfer(
        preparedTransfer: preparedTransfer,
        walletMaterial: walletMaterial,
        nonce: loadedNonce.nonce,
      );

      try {
        final submittedTransfer = await submitSignedTransfer(
          signedTransfer: signedTransfer,
          broadcaster: broadcaster,
        );

        final trackingFuture = tracker.waitForReceipt(
          networkConfig: signedTransfer.networkConfig,
          transactionHash: submittedTransfer.networkTransactionHash,
        );

        return HardenedSubmitResult(
          preparedTransfer: preparedTransfer,
          loadedNonce: loadedNonce,
          signedTransfer: signedTransfer,
          submittedTransfer: submittedTransfer,
          trackingFuture: trackingFuture,
          attempts: attempts,
          gasMultiplierUsed: gasMultiplier,
          replacementUsed: replacementUsed,
        );
      } on TransactionFailure catch (error) {
        if (!isRetryableNonceFailureMessage(error.message) ||
            attempts >= maxAttempts) {
          rethrow;
        }

        if (isUnderpricedFailureMessage(error.message)) {
          replacementUsed = true;
          gasMultiplier *= gasBumpMultiplier;
        }
      }
    }
  }
}

class HardenedSubmitResult {
  final PreparedTransfer preparedTransfer;
  final LoadedNonce loadedNonce;
  final SignedTransfer signedTransfer;
  final SubmittedTransfer submittedTransfer;
  final Future<TransactionReceipt> trackingFuture;
  final int attempts;
  final double gasMultiplierUsed;
  final bool replacementUsed;

  HardenedSubmitResult({
    required this.preparedTransfer,
    required this.loadedNonce,
    required this.signedTransfer,
    required this.submittedTransfer,
    required this.trackingFuture,
    required this.attempts,
    required this.gasMultiplierUsed,
    required this.replacementUsed,
  });
}
