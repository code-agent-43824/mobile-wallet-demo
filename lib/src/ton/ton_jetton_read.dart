part of 'ton_center_client.dart';

class TonJettonWalletData {
  const TonJettonWalletData(this.balance, this.owner, this.master);

  final BigInt balance;
  final TonAddress owner;
  final TonAddress master;
}

extension _JettonReads on TonCenterClient {
  Future<List<TonJettonHolding>> _apiJettonBalances(
    String owner,
    TonNetwork network,
  ) async {
    final reply = await _tonApi(network, 'accounts/$owner/jettons');
    final balances = <TonJettonHolding>[];
    for (final row in _rows(reply['balances'])) {
      final balance = _nonNegativeAmount(row['balance']);
      final jetton = _apiJetton(row['jetton'], network);
      if (balance > BigInt.zero) {
        balances.add(TonJettonHolding(jetton, balance));
      }
    }
    return balances;
  }

  Future<List<TonActivity>> _apiJettonActivity(
    String owner,
    TonNetwork network,
  ) async {
    final reply = await _tonApi(network, 'accounts/$owner/jettons/history', {
      'limit': '20',
    });
    return [
      for (final row in _rows(reply['operations']))
        if (row['operation'] == 'transfer')
          _jettonActivity(
            owner: owner,
            jetton: _apiJetton(row['jetton'], network),
            source: row['source'],
            destination: row['destination'],
            amount: row['amount'],
            time: row['utime'],
          ),
    ];
  }

  Future<List<TonJettonHolding>> _centerJettonBalances(
    String owner,
    TonNetwork network,
  ) async {
    final reply = await _jsonRequest(
      Uri.https(network.tonCenterHost, '/api/v3/jetton/wallets', {
        'owner_address': owner,
        'exclude_zero_balance': 'true',
        'limit': '1000',
      }),
    );
    final metadata = _centerJettonMetadata(reply);
    final balances = <TonJettonHolding>[];
    for (final row in _rows(reply['jetton_wallets'])) {
      if (_readAddress(row['owner']) != owner) throw _jettonReadFailed;
      final balance = _nonNegativeAmount(row['balance']);
      if (balance > BigInt.zero) {
        balances.add(
          TonJettonHolding(
            _centerJetton(row['jetton'], metadata, network),
            balance,
          ),
        );
      }
    }
    return balances;
  }

  Future<List<TonActivity>> _centerJettonActivity(
    String owner,
    TonNetwork network,
  ) async {
    final reply = await _jsonRequest(
      Uri.https(network.tonCenterHost, '/api/v3/jetton/transfers', {
        'owner_address': owner,
        'sort': 'desc',
        'limit': '20',
      }),
    );
    final metadata = _centerJettonMetadata(reply);
    return [
      for (final row in _rows(reply['jetton_transfers']))
        if (row['transaction_aborted'] == false)
          _jettonActivity(
            owner: owner,
            jetton: _centerJetton(row['jetton_master'], metadata, network),
            source: row['source'],
            destination: row['destination'],
            amount: row['amount'],
            time: row['transaction_now'],
          ),
    ];
  }

  Future<T> _jettonGetter<T>(
    TonNetwork network,
    TonAddress contract,
    String method, {
    TonAddress? owner,
    required T Function(List<dynamic>) parse,
  }) {
    final address = rawTonAddress(contract);
    return _withFallback(
      () async {
        final reply = await _request<Map<String, dynamic>>(
          'runGetMethod',
          network: network,
          body: {
            'address': address,
            'method': method,
            'stack': [
              if (owner != null)
                [
                  'tvm.Slice',
                  beginCell().storeAddress(owner).endCell().toBase64(),
                ],
            ],
          },
        );
        return _parseGetter(reply, parse);
      },
      () async {
        final reply = await _tonApi(
          network,
          'blockchain/accounts/$address/methods/$method',
          owner == null ? null : {'args': rawTonAddress(owner)},
        );
        return _parseGetter(reply, parse);
      },
    );
  }
}

const _jettonReadFailed = TransactionFailure.coded(
  AppErrorCode.tonApiUnavailable,
);

String _readAddress(Object? value) {
  final address = parseTonAddress(_addressField(value));
  if (address == null) throw _jettonReadFailed;
  return rawTonAddress(address);
}

TonJetton _apiJetton(Object? value, TonNetwork network) {
  if (value is! Map<String, dynamic>) throw _jettonReadFailed;
  return TonJetton(
    network: network,
    master: _readAddress(value['address']),
    symbol: value['symbol'],
    name: value['name'],
    decimals: value['decimals'],
  );
}

Map<String, Map<String, dynamic>> _centerJettonMetadata(
  Map<String, dynamic> reply,
) {
  final metadata = reply['metadata'];
  if (metadata is! Map<String, dynamic>) return const {};
  return {
    for (final entry in metadata.entries)
      if (parseTonAddress(entry.key) case final TonAddress address)
        if (entry.value case {'token_info': final List tokens})
          for (final token in tokens.whereType<Map<String, dynamic>>())
            if (token['type'] == 'jetton_masters' && token['valid'] != false)
              rawTonAddress(address): token,
  };
}

TonJetton _centerJetton(
  Object? value,
  Map<String, Map<String, dynamic>> metadata,
  TonNetwork network,
) {
  final master = _readAddress(value);
  final info = metadata[master];
  final extra = info?['extra'];
  return TonJetton(
    network: network,
    master: master,
    symbol: info?['symbol'],
    name: info?['name'],
    decimals: extra is Map ? extra['decimals'] : null,
  );
}

TonActivity _jettonActivity({
  required String owner,
  required TonJetton jetton,
  required Object? source,
  required Object? destination,
  required Object? amount,
  required Object? time,
}) {
  final sender = _readAddress(source);
  final recipient = _readAddress(destination);
  if ((sender != owner && recipient != owner) ||
      time is! int ||
      time < 0 ||
      time > 0xffffffff) {
    throw _jettonReadFailed;
  }
  final incoming = recipient == owner;
  final network = jetton.network;
  return TonActivity(
    amount: _nonNegativeAmount(amount),
    counterparty: network.friendly(TonAddress(incoming ? sender : recipient)),
    time: DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true),
    incoming: incoming,
    jetton: jetton,
  );
}

T _parseGetter<T>(
  Map<String, dynamic> result,
  T Function(List<dynamic>) parse,
) {
  final exitCode = result['exit_code'];
  if (exitCode is! int) throw _jettonReadFailed;
  if ((exitCode != 0 && exitCode != 1) || result['success'] == false) {
    throw const TransactionFailure.coded(AppErrorCode.tonJettonUnavailable);
  }
  try {
    return parse(result['stack'] as List);
  } catch (_) {
    throw _jettonReadFailed;
  }
}

Cell _stackCell(List<dynamic> stack, int index) => switch (stack[index]) {
  ['cell' || 'slice', {'bytes': final String bytes}] => Cell.fromBase64(bytes),
  {'type': 'cell' || 'slice', 'cell': final String boc} => Cell.fromHex(boc),
  _ => throw const FormatException('Invalid Jetton getter cell'),
};

Object _stackNumber(List<dynamic> stack, int index) => switch (stack[index]) {
  ['num', final Object number] ||
  {'type': 'num', 'num': final Object number} => number,
  _ => throw const FormatException('Invalid Jetton getter number'),
};
