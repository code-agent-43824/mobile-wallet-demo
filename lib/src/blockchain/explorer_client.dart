import 'dart:convert';
import 'dart:io';

import 'blockchain_models.dart';
import 'network_config.dart';

abstract interface class JsonApiTransport {
  Future<dynamic> get({required Uri uri});
}

class HttpJsonApiTransport implements JsonApiTransport {
  HttpJsonApiTransport({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<dynamic> get({required Uri uri}) async {
    final request = await _client.getUrl(uri);
    final response = await request.close();
    final body = await utf8.decodeStream(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BlockchainFailure(
        'Explorer endpoint ${uri.host} returned HTTP ${response.statusCode}.',
      );
    }

    return jsonDecode(body);
  }
}

/// Parsed token balances + recent transactions for an address.
class ExplorerData {
  const ExplorerData({
    required this.tokenBalances,
    required this.recentTransactions,
  });

  final List<TokenBalanceSnapshot> tokenBalances;
  final List<RecentTransactionSnapshot> recentTransactions;
}

/// Reads token balances + recent transactions from a Blockscout-style explorer
/// API and parses them into snapshot models. On any failure it returns the
/// supplied fallbacks (the last cached values), matching the provider's
/// previous behaviour. Split out of the provider — this is the "explorer
/// parsing" concern.
class BlockscoutExplorerClient {
  BlockscoutExplorerClient({JsonApiTransport? transport})
    : _transport = transport ?? HttpJsonApiTransport();

  final JsonApiTransport _transport;

  Future<ExplorerData> load({
    required EvmNetworkConfig config,
    required String address,
    required List<TokenBalanceSnapshot> fallbackTokenBalances,
    required List<RecentTransactionSnapshot> fallbackTransactions,
  }) async {
    try {
      final transactionsRaw = await _transport.get(
        uri: Uri.parse(
          '${config.explorerApiBaseUrl}/addresses/$address/transactions',
        ),
      );
      final tokenBalancesRaw = await _transport.get(
        uri: Uri.parse(
          '${config.explorerApiBaseUrl}/addresses/$address/token-balances',
        ),
      );

      final transactionsMap = transactionsRaw as Map<String, dynamic>;
      final tokenBalanceList = tokenBalancesRaw as List<dynamic>;

      return ExplorerData(
        tokenBalances: _parseTokenBalances(tokenBalanceList),
        recentTransactions: _parseTransactions(
          items: (transactionsMap['items'] as List<dynamic>? ?? <dynamic>[]),
          address: address,
          nativeSymbol: config.nativeSymbol,
        ),
      );
    } on BlockchainFailure {
      return ExplorerData(
        tokenBalances: fallbackTokenBalances,
        recentTransactions: fallbackTransactions,
      );
    } catch (_) {
      return ExplorerData(
        tokenBalances: fallbackTokenBalances,
        recentTransactions: fallbackTransactions,
      );
    }
  }

  List<TokenBalanceSnapshot> _parseTokenBalances(List<dynamic> rawItems) {
    return rawItems
        .map((item) => item as Map<String, dynamic>)
        .map((item) {
          final token = item['token'] as Map<String, dynamic>?;
          if (token == null) {
            return null;
          }

          final valueRaw = item['value'] as String? ?? '0';
          final decimalsRaw = token['decimals'] as String? ?? '18';
          final decimals = int.tryParse(decimalsRaw) ?? 18;
          final rawBalance = BigInt.tryParse(valueRaw) ?? BigInt.zero;
          final formatted = _formatTokenAmount(
            rawValue: valueRaw,
            decimals: decimals,
          );

          if (formatted == '0') {
            return null;
          }

          return TokenBalanceSnapshot(
            symbol: token['symbol'] as String? ?? 'TOKEN',
            name: token['name'] as String? ?? 'Unknown token',
            balanceFormatted: formatted,
            rawBalance: rawBalance,
            decimals: decimals,
            contractAddress: token['address_hash'] as String? ?? '—',
          );
        })
        .whereType<TokenBalanceSnapshot>()
        .take(5)
        .toList(growable: false);
  }

  List<RecentTransactionSnapshot> _parseTransactions({
    required List<dynamic> items,
    required String address,
    required String nativeSymbol,
  }) {
    final normalizedAddress = address.toLowerCase();

    return items
        .map((item) => item as Map<String, dynamic>)
        .map((item) {
          final from = item['from'] as Map<String, dynamic>?;
          final to = item['to'] as Map<String, dynamic>?;
          final fromAddress = from?['hash'] as String? ?? '—';
          final toAddress = to?['hash'] as String? ?? '—';
          final direction = _transactionDirection(
            walletAddress: normalizedAddress,
            fromAddress: fromAddress,
            toAddress: toAddress,
          );

          return RecentTransactionSnapshot(
            hash: item['hash'] as String? ?? '—',
            timestampUtc: _tryParseTimestamp(item['timestamp'] as String?),
            directionLabel: direction,
            counterparty: direction == 'Входящая' ? fromAddress : toAddress,
            valueFormatted:
                '${_formatNativeBalance(BigInt.tryParse(item['value'] as String? ?? '0') ?? BigInt.zero)} $nativeSymbol',
            statusLabel: _statusLabel(item),
          );
        })
        .take(5)
        .toList(growable: false);
  }

  String _transactionDirection({
    required String walletAddress,
    required String fromAddress,
    required String toAddress,
  }) {
    final from = fromAddress.toLowerCase();
    final to = toAddress.toLowerCase();

    if (from == walletAddress && to == walletAddress) {
      return 'Self';
    }
    if (to == walletAddress) {
      return 'Входящая';
    }
    if (from == walletAddress) {
      return 'Исходящая';
    }
    return 'Контракт';
  }

  String _statusLabel(Map<String, dynamic> item) {
    final result = item['result'] as String?;
    if (result == 'success') {
      return 'Success';
    }

    final status = item['status'] as String?;
    if (status == 'ok') {
      return 'Confirmed';
    }

    return status ?? result ?? 'Unknown';
  }

  DateTime? _tryParseTimestamp(String? timestamp) {
    if (timestamp == null) {
      return null;
    }

    return DateTime.tryParse(timestamp)?.toUtc();
  }

  String _formatTokenAmount({required String rawValue, required int decimals}) {
    final amount = BigInt.tryParse(rawValue) ?? BigInt.zero;
    if (amount == BigInt.zero) {
      return '0';
    }

    final divisor = BigInt.from(10).pow(decimals);
    final whole = amount ~/ divisor;
    final remainder = amount.remainder(divisor);
    if (remainder == BigInt.zero) {
      return whole.toString();
    }

    final fractional = remainder
        .toString()
        .padLeft(decimals, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    final compact = fractional.length > 6
        ? fractional.substring(0, 6)
        : fractional;
    return '$whole.$compact';
  }

  // Shared wei -> ETH formatter (a private copy also lives in the provider for
  // the native balance; kept local here to avoid a cross-concern import).
  String _formatNativeBalance(BigInt wei) {
    const weiPerEth = '1000000000000000000';
    final divisor = BigInt.parse(weiPerEth);
    final whole = wei ~/ divisor;
    final remainder = wei.remainder(divisor);
    final fractional = remainder
        .toString()
        .padLeft(18, '0')
        .replaceFirst(RegExp(r'0+$'), '');

    if (fractional.isEmpty) {
      return whole.toString();
    }

    final compactFraction = fractional.length > 6
        ? fractional.substring(0, 6)
        : fractional;
    return '$whole.$compactFraction';
  }
}
