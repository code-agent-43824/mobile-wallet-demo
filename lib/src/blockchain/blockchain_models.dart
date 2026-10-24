import 'network_config.dart';
import '../errors/app_error.dart';

/// Ceiling for a single network round trip.
///
/// Public RPC and explorer endpoints can accept a connection and then stall
/// indefinitely. Without a bound the snapshot load never settles, the UI stays
/// on its loading state forever, and the provider's fallback chain never gets
/// to try the next endpoint — which is exactly how a wedged screen looked after
/// a network switch.
const Duration networkRequestTimeout = Duration(seconds: 12);

class BlockchainFailure implements Exception, CodedError {
  /// A failure whose text comes from outside the app; shown as is.
  const BlockchainFailure(String message)
    : _message = message,
      errorCode = null,
      errorArgs = const <String, Object>{};

  const BlockchainFailure.coded(
    AppErrorCode this.errorCode, [
    this.errorArgs = const <String, Object>{},
  ]) : _message = null;

  final String? _message;

  @override
  final AppErrorCode? errorCode;

  @override
  final Map<String, Object> errorArgs;

  @override
  String get message => _message ?? debugDescribeError(errorCode!, errorArgs);

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

/// Which way a history entry moved value, relative to the wallet. Data, not a
/// label: the UI names it in the active language.
enum HistoryDirection { incoming, outgoing, self, contract, unknown }

/// How a history entry ended, as the explorer reports it.
enum HistoryStatus { success, failed, pending, unknown }

class RecentTransactionSnapshot {
  const RecentTransactionSnapshot({
    required this.hash,
    required this.timestampUtc,
    required this.direction,
    required this.counterparty,
    required this.valueFormatted,
    required this.status,
  });

  final String hash;
  final DateTime? timestampUtc;
  final HistoryDirection direction;
  final String counterparty;
  final String valueFormatted;
  final HistoryStatus status;
}
