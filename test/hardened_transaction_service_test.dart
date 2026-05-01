import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/transactions/hardened_transaction_service.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_tracker.dart';

void main() {
  const service = HardenedTransactionServiceImplementation();
  const network = EvmNetwork.ethereumMainnet;
  const sender = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
  const recipient = '0x1111111111111111111111111111111111111111';

  WalletChainSnapshot buildSnapshot() {
    return WalletChainSnapshot(
      network: network,
      address: sender,
      nativeBalanceWei: BigInt.parse('1230000000000000000'),
      nativeBalanceFormatted: '1.23',
      baseFeeGwei: 12.0,
      providerLabel: 'fake-rpc.local',
      fetchedAtUtc: DateTime.utc(2026, 5, 1, 6, 42),
      tokenBalances: const <TokenBalanceSnapshot>[],
      recentTransactions: const <RecentTransactionSnapshot>[],
    );
  }

  const walletMaterial = WalletMaterial(
    address: sender,
    mnemonic: 'test test test test test test test test test test test junk',
    privateKeyHex:
        'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
  );

  test(
    'retries underpriced submission with gas bump and replacement flag',
    () async {
      final attempts = <SignedTransfer>[];
      final tracker = TransactionTracker(
        rpcTransport: _FakeTrackingTransport(),
        pollInterval: Duration.zero,
        maxAttempts: 1,
      );

      final result = await service.submitTransferFlow(
        snapshot: buildSnapshot(),
        fromAddress: sender,
        toAddress: recipient,
        amountText: '0.1',
        asset: service
            .availableAssets(
              snapshot: buildSnapshot(),
              networkConfig: evmNetworkConfigs[network]!,
            )
            .first,
        walletMaterial: walletMaterial,
        broadcaster: _RecordingBroadcaster(attempts),
        nonceProvider: _StaticNonceProvider(),
        tracker: tracker,
      );

      expect(result.attempts, 2);
      expect(result.replacementUsed, isTrue);
      expect(result.gasMultiplierUsed, greaterThan(1.0));
      expect(attempts, hasLength(2));
      expect(
        attempts.first.rawTransactionHex,
        isNot(equals(attempts.last.rawTransactionHex)),
      );
    },
  );

  test(
    'treats already known response as successful submission with local hash',
    () async {
      final snapshot = buildSnapshot();
      final asset = service
          .availableAssets(
            snapshot: snapshot,
            networkConfig: evmNetworkConfigs[network]!,
          )
          .first;
      final prepared = service.prepareTransfer(
        snapshot: snapshot,
        fromAddress: sender,
        toAddress: recipient,
        amountText: '0.1',
        asset: asset,
      );
      final signed = service.signPreparedTransfer(
        preparedTransfer: prepared,
        walletMaterial: walletMaterial,
        nonce: 7,
      );

      final submitted = await service.submitSignedTransfer(
        signedTransfer: signed,
        broadcaster: PublicRpcTransactionBroadcaster(
          rpcTransport: _AlreadyKnownTransport(),
        ),
      );

      expect(submitted.networkTransactionHash, signed.transactionHashHex);
    },
  );
}

class _StaticNonceProvider implements NonceProvider {
  @override
  Future<LoadedNonce> loadNextNonce({
    required EvmNetworkConfig networkConfig,
    required String address,
  }) async {
    return LoadedNonce(
      network: networkConfig.network,
      address: address,
      nonce: 7,
      providerLabel: 'nonce.fake',
      loadedAtUtc: DateTime.utc(2026, 5, 1, 6, 43),
    );
  }
}

class _RecordingBroadcaster implements TransactionBroadcaster {
  _RecordingBroadcaster(this.attempts);

  final List<SignedTransfer> attempts;
  var _callCount = 0;

  @override
  Future<SubmittedTransfer> submit({
    required SignedTransfer signedTransfer,
  }) async {
    attempts.add(signedTransfer);
    _callCount += 1;
    if (_callCount == 1) {
      throw const TransactionFailure(
        'RPC fake rejected signed transaction with a retryable nonce/pricing issue: replacement transaction underpriced',
      );
    }

    return SubmittedTransfer(
      signedTransfer: signedTransfer,
      providerLabel: 'broadcast.fake',
      networkTransactionHash: signedTransfer.transactionHashHex,
      submittedAtUtc: DateTime.utc(2026, 5, 1, 6, 44),
    );
  }
}

class _FakeTrackingTransport implements JsonRpcTransport {
  @override
  Future<Map<String, dynamic>> post({
    required Uri uri,
    required Map<String, dynamic> payload,
  }) async {
    return <String, dynamic>{
      'jsonrpc': '2.0',
      'id': 1,
      'result': <String, dynamic>{
        'status': '0x1',
        'blockNumber': '0x10',
        'gasUsed': '0x5208',
      },
    };
  }
}

class _AlreadyKnownTransport implements JsonRpcTransport {
  @override
  Future<Map<String, dynamic>> post({
    required Uri uri,
    required Map<String, dynamic> payload,
  }) async {
    return <String, dynamic>{
      'jsonrpc': '2.0',
      'id': 1,
      'error': 'already known',
    };
  }
}
