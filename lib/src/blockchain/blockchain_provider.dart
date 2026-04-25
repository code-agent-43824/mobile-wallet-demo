import 'dart:convert';
import 'dart:io';

import '../key_storage/secure_key_value_store.dart';
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

abstract interface class BlockchainProvider {
  Future<WalletChainSnapshot> loadSnapshot({
    required EvmNetwork network,
    required String address,
  });
}

abstract interface class JsonRpcTransport {
  Future<Map<String, dynamic>> post({
    required Uri uri,
    required Map<String, dynamic> payload,
  });
}

abstract interface class JsonApiTransport {
  Future<dynamic> get({required Uri uri});
}

class HttpJsonRpcTransport implements JsonRpcTransport {
  HttpJsonRpcTransport({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<Map<String, dynamic>> post({
    required Uri uri,
    required Map<String, dynamic> payload,
  }) async {
    final request = await _client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));
    final response = await request.close();
    final body = await utf8.decodeStream(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BlockchainFailure(
        'RPC endpoint ${uri.host} returned HTTP ${response.statusCode}.',
      );
    }

    return jsonDecode(body) as Map<String, dynamic>;
  }
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

class PublicRpcBlockchainProvider implements BlockchainProvider {
  PublicRpcBlockchainProvider({
    JsonRpcTransport? rpcTransport,
    JsonApiTransport? apiTransport,
    SecureKeyValueStore? cacheStore,
  }) : _rpcTransport = rpcTransport ?? HttpJsonRpcTransport(),
       _apiTransport = apiTransport ?? HttpJsonApiTransport(),
       _cacheStore = cacheStore;

  final JsonRpcTransport _rpcTransport;
  final JsonApiTransport _apiTransport;
  final SecureKeyValueStore? _cacheStore;

  @override
  Future<WalletChainSnapshot> loadSnapshot({
    required EvmNetwork network,
    required String address,
  }) async {
    final config = evmNetworkConfigs[network]!;
    BlockchainFailure? lastFailure;
    final cachedSnapshot = await _readCachedSnapshot(
      network: network,
      address: address,
    );

    for (final rpcUrl in config.rpcUrls) {
      final uri = Uri.parse(rpcUrl);
      try {
        final balanceResponse = await _rpcCall(
          uri: uri,
          method: 'eth_getBalance',
          params: <dynamic>[address, 'latest'],
        );
        final latestBlockResponse = await _rpcCall(
          uri: uri,
          method: 'eth_getBlockByNumber',
          params: <dynamic>['latest', false],
        );

        final balanceWei = _hexToBigInt(balanceResponse['result'] as String?);
        final block = latestBlockResponse['result'] as Map<String, dynamic>?;
        final baseFeeHex = block?['baseFeePerGas'] as String?;
        final explorerData = await _loadExplorerData(
          config: config,
          address: address,
          cachedSnapshot: cachedSnapshot,
        );

        final snapshot = WalletChainSnapshot(
          network: network,
          address: address,
          nativeBalanceWei: balanceWei,
          nativeBalanceFormatted: _formatNativeBalance(balanceWei),
          baseFeeGwei: _parseGwei(baseFeeHex),
          providerLabel: uri.host,
          fetchedAtUtc: DateTime.now().toUtc(),
          tokenBalances: explorerData.tokenBalances,
          recentTransactions: explorerData.recentTransactions,
        );
        await _writeCachedSnapshot(snapshot);

        return snapshot;
      } on BlockchainFailure catch (error) {
        lastFailure = error;
      } catch (error) {
        lastFailure = BlockchainFailure(
          'RPC endpoint ${uri.host} failed: $error',
        );
      }
    }

    if (cachedSnapshot != null) {
      return WalletChainSnapshot(
        network: cachedSnapshot.network,
        address: cachedSnapshot.address,
        nativeBalanceWei: cachedSnapshot.nativeBalanceWei,
        nativeBalanceFormatted: cachedSnapshot.nativeBalanceFormatted,
        baseFeeGwei: cachedSnapshot.baseFeeGwei,
        providerLabel: cachedSnapshot.providerLabel,
        fetchedAtUtc: cachedSnapshot.fetchedAtUtc,
        tokenBalances: cachedSnapshot.tokenBalances,
        recentTransactions: cachedSnapshot.recentTransactions,
        loadedFromCache: true,
      );
    }

    throw lastFailure ??
        const BlockchainFailure('No RPC endpoints are configured.');
  }

  Future<Map<String, dynamic>> _rpcCall({
    required Uri uri,
    required String method,
    required List<dynamic> params,
  }) async {
    final response = await _rpcTransport.post(
      uri: uri,
      payload: <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        'params': params,
      },
    );

    final error = response['error'];
    if (error != null) {
      throw BlockchainFailure('RPC ${uri.host} rejected $method: $error');
    }

    return response;
  }

  Future<_ExplorerData> _loadExplorerData({
    required EvmNetworkConfig config,
    required String address,
    required WalletChainSnapshot? cachedSnapshot,
  }) async {
    try {
      final transactionsRaw = await _apiTransport.get(
        uri: Uri.parse(
          '${config.explorerApiBaseUrl}/addresses/$address/transactions',
        ),
      );
      final tokenBalancesRaw = await _apiTransport.get(
        uri: Uri.parse(
          '${config.explorerApiBaseUrl}/addresses/$address/token-balances',
        ),
      );

      final transactionsMap = transactionsRaw as Map<String, dynamic>;
      final tokenBalanceList = tokenBalancesRaw as List<dynamic>;

      return _ExplorerData(
        tokenBalances: _parseTokenBalances(tokenBalanceList),
        recentTransactions: _parseTransactions(
          items: (transactionsMap['items'] as List<dynamic>? ?? <dynamic>[]),
          address: address,
          nativeSymbol: config.nativeSymbol,
        ),
      );
    } on BlockchainFailure {
      return _ExplorerData(
        tokenBalances: cachedSnapshot?.tokenBalances ?? const [],
        recentTransactions: cachedSnapshot?.recentTransactions ?? const [],
      );
    } catch (_) {
      return _ExplorerData(
        tokenBalances: cachedSnapshot?.tokenBalances ?? const [],
        recentTransactions: cachedSnapshot?.recentTransactions ?? const [],
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

  String _cacheKey({required EvmNetwork network, required String address}) {
    return 'wallet_snapshot.${network.name}.${address.toLowerCase()}';
  }

  Future<WalletChainSnapshot?> _readCachedSnapshot({
    required EvmNetwork network,
    required String address,
  }) async {
    final store = _cacheStore;
    if (store == null) {
      return null;
    }

    final raw = await store.read(_cacheKey(network: network, address: address));
    if (raw == null) {
      return null;
    }

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return WalletChainSnapshot(
        network: network,
        address: data['address'] as String? ?? address,
        nativeBalanceWei: BigInt.parse(data['nativeBalanceWei'] as String),
        nativeBalanceFormatted:
            data['nativeBalanceFormatted'] as String? ?? '0',
        baseFeeGwei: (data['baseFeeGwei'] as num?)?.toDouble(),
        providerLabel: data['providerLabel'] as String? ?? 'cache',
        fetchedAtUtc: DateTime.parse(data['fetchedAtUtc'] as String).toUtc(),
        tokenBalances: (data['tokenBalances'] as List<dynamic>? ?? <dynamic>[])
            .map((item) => item as Map<String, dynamic>)
            .map(
              (item) => TokenBalanceSnapshot(
                symbol: item['symbol'] as String? ?? 'TOKEN',
                name: item['name'] as String? ?? 'Unknown token',
                balanceFormatted: item['balanceFormatted'] as String? ?? '0',
                rawBalance:
                    BigInt.tryParse(item['rawBalance'] as String? ?? '0') ??
                    BigInt.zero,
                decimals: item['decimals'] as int? ?? 18,
                contractAddress: item['contractAddress'] as String? ?? '—',
              ),
            )
            .toList(growable: false),
        recentTransactions:
            (data['recentTransactions'] as List<dynamic>? ?? <dynamic>[])
                .map((item) => item as Map<String, dynamic>)
                .map(
                  (item) => RecentTransactionSnapshot(
                    hash: item['hash'] as String? ?? '—',
                    timestampUtc: _tryParseTimestamp(
                      item['timestampUtc'] as String?,
                    ),
                    directionLabel:
                        item['directionLabel'] as String? ?? 'Unknown',
                    counterparty: item['counterparty'] as String? ?? '—',
                    valueFormatted: item['valueFormatted'] as String? ?? '0',
                    statusLabel: item['statusLabel'] as String? ?? 'Unknown',
                  ),
                )
                .toList(growable: false),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedSnapshot(WalletChainSnapshot snapshot) async {
    final store = _cacheStore;
    if (store == null) {
      return;
    }

    await store.write(
      _cacheKey(network: snapshot.network, address: snapshot.address),
      jsonEncode(<String, dynamic>{
        'address': snapshot.address,
        'nativeBalanceWei': snapshot.nativeBalanceWei.toString(),
        'nativeBalanceFormatted': snapshot.nativeBalanceFormatted,
        'baseFeeGwei': snapshot.baseFeeGwei,
        'providerLabel': snapshot.providerLabel,
        'fetchedAtUtc': snapshot.fetchedAtUtc.toIso8601String(),
        'tokenBalances': snapshot.tokenBalances
            .map(
              (token) => <String, dynamic>{
                'symbol': token.symbol,
                'name': token.name,
                'balanceFormatted': token.balanceFormatted,
                'rawBalance': token.rawBalance.toString(),
                'decimals': token.decimals,
                'contractAddress': token.contractAddress,
              },
            )
            .toList(growable: false),
        'recentTransactions': snapshot.recentTransactions
            .map(
              (tx) => <String, dynamic>{
                'hash': tx.hash,
                'timestampUtc': tx.timestampUtc?.toIso8601String(),
                'directionLabel': tx.directionLabel,
                'counterparty': tx.counterparty,
                'valueFormatted': tx.valueFormatted,
                'statusLabel': tx.statusLabel,
              },
            )
            .toList(growable: false),
      }),
    );
  }

  BigInt _hexToBigInt(String? value) {
    final normalized = (value ?? '0x0').replaceFirst('0x', '');
    if (normalized.isEmpty) {
      return BigInt.zero;
    }

    return BigInt.parse(normalized, radix: 16);
  }

  double? _parseGwei(String? hexValue) {
    if (hexValue == null) {
      return null;
    }

    final wei = _hexToBigInt(hexValue);
    return wei.toDouble() / 1000000000;
  }

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

class _ExplorerData {
  const _ExplorerData({
    required this.tokenBalances,
    required this.recentTransactions,
  });

  final List<TokenBalanceSnapshot> tokenBalances;
  final List<RecentTransactionSnapshot> recentTransactions;
}
