import 'network_config.dart';

class BlockchainFailure implements Exception {
  const BlockchainFailure(this.message);

  final String message;

  @override
  String toString() => 'BlockchainFailure: $message';
}

class WalletChainSnapshot {
  const WalletChainSnapshot({
    required this.network,
    required this.address,
    required this.nativeBalanceWei,
    required this.nativeBalanceFormatted,
    required this.baseFeeGwei,
    required this.providerLabel,
    required this.fetchedAtUtc,
    required this.tokenBalances,
    required this.recentTransactions,
    this.loadedFromCache = false,
  });

  final EvmNetwork network;
  final String address;
  final BigInt nativeBalanceWei;
  final String nativeBalanceFormatted;
  final double? baseFeeGwei;
  final String providerLabel;
  final DateTime fetchedAtUtc;
  final List<TokenBalanceSnapshot> tokenBalances;
  final List<RecentTransactionSnapshot> recentTransactions;
  final bool loadedFromCache;
}

class TokenBalanceSnapshot {
  const TokenBalanceSnapshot({
    required this.symbol,
    required this.name,
    required this.balanceFormatted,
    required this.rawBalance,
    required this.decimals,
    required this.contractAddress,
  });

  final String symbol;
  final String name;
  final String balanceFormatted;
  final BigInt rawBalance;
  final int decimals;
  final String contractAddress;
}

class RecentTransactionSnapshot {
  const RecentTransactionSnapshot({
    required this.hash,
    required this.timestampUtc,
    required this.directionLabel,
    required this.counterparty,
    required this.valueFormatted,
    required this.statusLabel,
  });

  final String hash;
  final DateTime? timestampUtc;
  final String directionLabel;
  final String counterparty;
  final String valueFormatted;
  final String statusLabel;
}
