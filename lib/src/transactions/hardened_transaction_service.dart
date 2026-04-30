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