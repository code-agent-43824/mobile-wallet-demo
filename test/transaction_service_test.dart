import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';

void main() {
  const service = ReadOnlyTransactionService();
  const network = EvmNetwork.ethereumMainnet;

  WalletChainSnapshot buildSnapshot() {
    return WalletChainSnapshot(
      network: network,
      address: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      nativeBalanceWei: BigInt.parse('1230000000000000000'),
      nativeBalanceFormatted: '1.23',
      baseFeeGwei: 12.0,
      providerLabel: 'fake-rpc.local',
      fetchedAtUtc: DateTime.utc(2026, 4, 25, 15, 32),
      tokenBalances: <TokenBalanceSnapshot>[
        TokenBalanceSnapshot(
          symbol: 'USDC',
          name: 'USD Coin',
          balanceFormatted: '42.5',
          rawBalance: BigInt.from(42500000),
          decimals: 6,
          contractAddress: '0xToken',
        ),
      ],
      recentTransactions: const <RecentTransactionSnapshot>[],
    );
  }

  test('builds native transfer preview with gas estimate', () {
    final snapshot = buildSnapshot();
    final asset = service
        .availableAssets(
          snapshot: snapshot,
          networkConfig: evmNetworkConfigs[network]!,
        )
        .first;

    final preview = service.preparePreview(
      snapshot: snapshot,
      fromAddress: snapshot.address,
      toAddress: '0x1111111111111111111111111111111111111111',
      amountText: '0.1',
      asset: asset,
    );

    expect(preview.gasLimit, 21000);
    expect(preview.amountFormatted, '0.1 ETH');
    expect(preview.estimatedNetworkFeeNativeFormatted, contains('ETH'));
  });

  test('builds token transfer preview with separate native fee', () {
    final snapshot = buildSnapshot();
    final asset = service
        .availableAssets(
          snapshot: snapshot,
          networkConfig: evmNetworkConfigs[network]!,
        )
        .last;

    final preview = service.preparePreview(
      snapshot: snapshot,
      fromAddress: snapshot.address,
      toAddress: '0x1111111111111111111111111111111111111111',
      amountText: '2.5',
      asset: asset,
    );

    expect(preview.gasLimit, 65000);
    expect(preview.amountFormatted, '2.5 USDC');
    expect(preview.totalDebitFormatted, contains('ETH fee'));
  });

  test('rejects invalid recipient address', () {
    final snapshot = buildSnapshot();
    final asset = service
        .availableAssets(
          snapshot: snapshot,
          networkConfig: evmNetworkConfigs[network]!,
        )
        .first;

    expect(
      () => service.preparePreview(
        snapshot: snapshot,
        fromAddress: snapshot.address,
        toAddress: '0xabc',
        amountText: '0.1',
        asset: asset,
      ),
      throwsA(isA<TransactionFailure>()),
    );
  });
}
