part of 'ton_transfer_service.dart';

class _TonSnapshotCache {
  const _TonSnapshotCache(this._store);

  final SecureKeyValueStore _store;

  String _key(TonAccount account) =>
      'wallet.ton.snapshot.v1.${account.network.name}.${account.rawAddress}';

  Future<TonSnapshot?> read(TonAccount account) async {
    try {
      final raw = await _store.read(_key(account));
      if (raw == null) return null;
      final stored = jsonDecode(raw) as Map<String, dynamic>;
      if (stored['network'] != account.network.name ||
          stored['address'] != account.rawAddress) {
        return null;
      }
      return TonSnapshot(
        BigInt.parse(stored['balance'] as String),
        [
          for (final row in stored['activity'] as List)
            TonActivity(
              amount: BigInt.parse(row['amount'] as String),
              counterparty: row['counterparty'] as String,
              time: DateTime.parse(row['time'] as String),
              incoming: row['incoming'] as bool,
            ),
        ],
        stored['lastSubmission'] == null
            ? null
            : TonTransferStatus.values.byName(
                stored['lastSubmission'] as String,
              ),
        fetchedAt: DateTime.parse(stored['fetchedAt'] as String),
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(TonAccount account, TonSnapshot snapshot) async {
    try {
      await _store.write(
        _key(account),
        jsonEncode({
          'network': account.network.name,
          'address': account.rawAddress,
          'balance': snapshot.balance.toString(),
          'fetchedAt': snapshot.fetchedAt.toIso8601String(),
          'lastSubmission': snapshot.lastSubmission?.name,
          'activity': [
            for (final row in snapshot.activity)
              {
                'amount': row.amount.toString(),
                'counterparty': row.counterparty,
                'time': row.time.toIso8601String(),
                'incoming': row.incoming,
              },
          ],
        }),
      );
    } catch (_) {
      // A storage error must not discard a successful live response.
    }
  }
}
