import 'dart:convert';

import '../key_storage/secure_key_value_store.dart';
import 'blockchain_models.dart';
import 'network_config.dart';

/// Persists the last successful [WalletChainSnapshot] in the secure store and
/// reads it back, so the provider can serve a cached snapshot when every live
/// endpoint fails. Pure (de)serialization split out of the provider — no
/// network access.
class SnapshotCache {
  const SnapshotCache(this._store);

  final SecureKeyValueStore _store;

  String _cacheKey({required EvmNetwork network, required String address}) {
    return 'wallet_snapshot.${network.name}.${address.toLowerCase()}';
  }

  Future<WalletChainSnapshot?> read({
    required EvmNetwork network,
    required String address,
  }) async {
    final raw = await _store.read(
      _cacheKey(network: network, address: address),
    );
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

  Future<void> write(WalletChainSnapshot snapshot) async {
    await _store.write(
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

  DateTime? _tryParseTimestamp(String? timestamp) {
    if (timestamp == null) {
      return null;
    }

    return DateTime.tryParse(timestamp)?.toUtc();
  }
}
