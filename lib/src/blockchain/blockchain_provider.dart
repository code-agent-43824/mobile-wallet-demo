import 'dart:convert';
import 'dart:io';

import '../key_storage/secure_key_value_store.dart';
import 'blockchain_models.dart';
import 'explorer_client.dart';
import 'network_config.dart';
import 'snapshot_cache.dart';

export 'blockchain_models.dart';
export 'explorer_client.dart';

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

class PublicRpcBlockchainProvider implements BlockchainProvider {
  PublicRpcBlockchainProvider({
    JsonRpcTransport? rpcTransport,
    JsonApiTransport? apiTransport,
    SecureKeyValueStore? cacheStore,
  }) : _rpcTransport = rpcTransport ?? HttpJsonRpcTransport(),
       _explorer = BlockscoutExplorerClient(transport: apiTransport),
       _cache = cacheStore == null ? null : SnapshotCache(cacheStore);

  final JsonRpcTransport _rpcTransport;
  final BlockscoutExplorerClient _explorer;
  final SnapshotCache? _cache;

  @override
  Future<WalletChainSnapshot> loadSnapshot({
    required EvmNetwork network,
    required String address,
  }) async {
    final config = evmNetworkConfigs[network]!;
    BlockchainFailure? lastFailure;
    final cachedSnapshot = await _cache?.read(
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
        final explorerData = await _explorer.load(
          config: config,
          address: address,
          fallbackTokenBalances: cachedSnapshot?.tokenBalances ?? const [],
          fallbackTransactions: cachedSnapshot?.recentTransactions ?? const [],
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
        await _cache?.write(snapshot);

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
