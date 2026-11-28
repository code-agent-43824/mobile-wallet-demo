part of 'ton_transfer_service.dart';

class _TonSnapshotCache {
  const _TonSnapshotCache(this._store);

  final SecureKeyValueStore _store;

  String _key(TonAccount account, String kind) =>
      'wallet.ton.$kind.v1.${account.network.name}.${account.rawAddress}';

  Future<TonSnapshot?> read(TonAccount account) async {
    try {
      final stored = await _read(account, 'snapshot');
      if (stored == null) return null;
      return TonSnapshot(
        BigInt.parse(stored['balance'] as String),
        [
          for (final row in stored['activity'] as List)
            _activityFromJson(row as Map<String, dynamic>, account.network),
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

  Future<TonJettonSnapshot?> readJettons(TonAccount account) async {
    try {
      final stored = await _read(account, 'jettons');
      if (stored == null) return null;
      return TonJettonSnapshot(
        balances: [
          for (final row in stored['balances'] as List)
            TonJettonHolding(
              _jettonFromJson(
                row['jetton'] as Map<String, dynamic>,
                account.network,
              ),
              BigInt.parse(row['amount'] as String),
            ),
        ],
        activity: [
          for (final row in stored['activity'] as List)
            _activityFromJson(row as Map<String, dynamic>, account.network),
        ],
        fetchedAt: DateTime.parse(stored['fetchedAt'] as String),
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(TonAccount account, TonSnapshot snapshot) =>
      _write(account, 'snapshot', {
        'balance': snapshot.balance.toString(),
        'fetchedAt': snapshot.fetchedAt.toIso8601String(),
        'lastSubmission': snapshot.lastSubmission?.name,
        'activity': snapshot.activity.map(_activityToJson).toList(),
      });

  Future<void> writeJettons(TonAccount account, TonJettonSnapshot snapshot) =>
      _write(account, 'jettons', {
        'fetchedAt': snapshot.fetchedAt.toIso8601String(),
        'balances': [
          for (final row in snapshot.balances)
            {
              'jetton': _jettonToJson(row.jetton),
              'amount': row.amount.toString(),
            },
        ],
        'activity': snapshot.activity.map(_activityToJson).toList(),
      });

  Future<Map<String, dynamic>?> _read(TonAccount account, String kind) async {
    final raw = await _store.read(_key(account, kind));
    if (raw == null) return null;
    final stored = jsonDecode(raw) as Map<String, dynamic>;
    return stored['network'] == account.network.name &&
            stored['address'] == account.rawAddress
        ? stored
        : null;
  }

  Future<void> _write(
    TonAccount account,
    String kind,
    Map<String, Object?> payload,
  ) async {
    try {
      await _store.write(
        _key(account, kind),
        jsonEncode({
          'network': account.network.name,
          'address': account.rawAddress,
          ...payload,
        }),
      );
    } catch (_) {
      // A storage error must not discard a successful live response.
    }
  }
}

Map<String, Object?> _activityToJson(TonActivity row) => {
  'amount': row.amount.toString(),
  'counterparty': row.counterparty,
  'time': row.time.toIso8601String(),
  'incoming': row.incoming,
  if (row.jetton case final TonJetton jetton) 'jetton': _jettonToJson(jetton),
};

TonActivity _activityFromJson(Map<String, dynamic> row, TonNetwork network) =>
    TonActivity(
      amount: BigInt.parse(row['amount'] as String),
      counterparty: row['counterparty'] as String,
      time: DateTime.parse(row['time'] as String),
      incoming: row['incoming'] as bool,
      jetton: switch (row['jetton']) {
        final Map<String, dynamic> jetton => _jettonFromJson(jetton, network),
        _ => null,
      },
    );

Map<String, Object?> _jettonToJson(TonJetton jetton) => {
  'master': jetton.master,
  'symbol': jetton.symbol,
  'name': jetton.name,
  'decimals': jetton.decimals,
};

TonJetton _jettonFromJson(Map<String, dynamic> row, TonNetwork network) =>
    TonJetton(
      network: network,
      master: row['master'] as String,
      symbol: row['symbol'],
      name: row['name'],
      decimals: row['decimals'],
    );
