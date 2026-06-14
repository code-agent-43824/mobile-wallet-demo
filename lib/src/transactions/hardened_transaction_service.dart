import 'dart:typed_data';

import '../auth/wallet_operation_auth.dart';
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

  Future<HardenedSubmitResult> submitAuthorizedTransferFlow({
    required WalletChainSnapshot snapshot,
    required String fromAddress,
    required String toAddress,
    required String amountText,
    required TransferAssetOption asset,
    required WalletTransactionSigner signer,
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
    return const LocalTransactionService().availableAssets(
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
    return const LocalTransactionService().preparePreview(
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
    return const LocalTransactionService().prepareTransfer(
      snapshot: snapshot,
      fromAddress: fromAddress,
      toAddress: toAddress,
      amountText: amountText,
      asset: asset,
      gasMultiplier: gasMultiplier,
    );
  }

  @override
  PreparedTransfer prepareInboundTransaction({
    required EvmNetwork network,
    required String fromAddress,
    required String toAddress,
    required BigInt valueWei,
    required Uint8List data,
    required int gasLimit,
    required BigInt maxFeePerGasWei,
    required BigInt maxPriorityFeePerGasWei,
  }) {
    return const LocalTransactionService().prepareInboundTransaction(
      network: network,
      fromAddress: fromAddress,
      toAddress: toAddress,
      valueWei: valueWei,
      data: data,
      gasLimit: gasLimit,
      maxFeePerGasWei: maxFeePerGasWei,
      maxPriorityFeePerGasWei: maxPriorityFeePerGasWei,
    );
  }

  @override
  SignedTransfer signPreparedTransfer({
    required PreparedTransfer preparedTransfer,
    required WalletMaterial walletMaterial,
    required int nonce,
  }) {
    return const LocalTransactionService().signPreparedTransfer(
      preparedTransfer: preparedTransfer,
      walletMaterial: walletMaterial,
      nonce: nonce,
    );
  }

  @override
  SignedTransfer assembleSignedTransfer({
    required PreparedTransfer preparedTransfer,
    required Uint8List rawSignedTransaction,
    String? signingNote,
  }) {
    return const LocalTransactionService().assembleSignedTransfer(
      preparedTransfer: preparedTransfer,
      rawSignedTransaction: rawSignedTransaction,
      signingNote: signingNote,
    );
  }

  @override
  Future<SubmittedTransfer> submitSignedTransfer({
    required SignedTransfer signedTransfer,
    required TransactionBroadcaster broadcaster,
  }) {
    return const LocalTransactionService().submitSignedTransfer(
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
  }) {
    return submitAuthorizedTransferFlow(
      snapshot: snapshot,
      fromAddress: fromAddress,
      toAddress: toAddress,
      amountText: amountText,
      asset: asset,
      signer: LocalKeyMaterialTransactionSigner(
        backendId: 'phone_secure_vault',
        walletMaterial: walletMaterial,
      ),
      broadcaster: broadcaster,
      nonceProvider: nonceProvider,
      tracker: tracker,
      maxAttempts: maxAttempts,
      gasBumpMultiplier: gasBumpMultiplier,
    );
  }

  @override
  Future<HardenedSubmitResult> submitAuthorizedTransferFlow({
    required WalletChainSnapshot snapshot,
    required String fromAddress,
    required String toAddress,
    required String amountText,
    required TransferAssetOption asset,
    required WalletTransactionSigner signer,
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
      final signedTransfer = await signer.signPreparedTransfer(
        transactionService: this,
        preparedTransfer: preparedTransfer,
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
