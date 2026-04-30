import '../blockchain/blockchain_provider.dart';
import '../blockchain/network_config.dart';
import '../key_storage/key_storage_backend.dart';
import 'transaction_service.dart';
import 'transaction_tracker.dart';

abstract interface class HardenedTransactionService implements TransactionService {
  Future<HardenedSubmitResult> submitSignedTransferWithTracking({
    required SignedTransfer signedTransfer,
    required TransactionBroadcaster broadcaster,
    required TransactionTracker tracker,
  });
}

class HardenedTransactionServiceImplementation implements HardenedTransactionService {
  final HardenedSubmitResult? lastSubmitResult;

  const HardenedTransactionServiceImplementation({
    this.lastSubmitResult,
  });

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
  }) {
    return const ReadOnlyTransactionService().prepareTransfer(
      snapshot: snapshot,
      fromAddress: fromAddress,
      toAddress: toAddress,
      amountText: amountText,
      asset: asset,
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
  Future<HardenedSubmitResult> submitSignedTransferWithTracking({
    required SignedTransfer signedTransfer,
    required TransactionBroadcaster broadcaster,
    required TransactionTracker tracker,
  }) async {
    // First submit the transaction
    final submittedTransfer = await submitSignedTransfer(
      signedTransfer: signedTransfer,
      broadcaster: broadcaster,
    );

    // Then start tracking
    final trackingFuture = tracker.waitForReceipt(
      networkConfig: signedTransfer.networkConfig,
      transactionHash: submittedTransfer.networkTransactionHash,
    );

    return HardenedSubmitResult(
      submittedTransfer: submittedTransfer,
      trackingFuture: trackingFuture,
    );
  }
}

class HardenedSubmitResult {
  final SubmittedTransfer submittedTransfer;
  final Future<TransactionReceipt> trackingFuture;

  HardenedSubmitResult({
    required this.submittedTransfer,
    required this.trackingFuture,
  });
}

class HardenedTransactionBroadcaster implements TransactionBroadcaster {
  final TransactionBroadcaster _delegate;
  final NonceProvider _nonceProvider;

  HardenedTransactionBroadcaster({
    required TransactionBroadcaster delegate,
    required NonceProvider nonceProvider,
  }) : _delegate = delegate,
       _nonceProvider = nonceProvider;

  @override
  Future<SubmittedTransfer> submit({
    required SignedTransfer signedTransfer,
  }) async {
    try {
      return await _delegate.submit(signedTransfer: signedTransfer);
    } on TransactionFailure catch (error) {
      // Check if it's a nonce-related error
      if (error.message.contains('nonce too low') ||
          error.message.toLowerCase().contains('nonce') ||
          error.message.toLowerCase().contains('invalid')) {
        // Try to recover by getting a fresh nonce and retrying
        final nonce = await _nonceProvider.loadNextNonce(
          networkConfig: signedTransfer.networkConfig,
          address: signedTransfer.preview.fromAddress,
        );

        // Resign with the fresh nonce (this would normally be done by the caller)
        // For now, just throw a more detailed error
        throw TransactionFailure(
          'Transaction failed due to nonce issue. Fresh nonce loaded: ${nonce.nonce}. '
          'Consider retrying the transaction with the updated nonce.',
        );
      }
      // Re-throw non-nonce related errors
      rethrow;
    }
  }
}