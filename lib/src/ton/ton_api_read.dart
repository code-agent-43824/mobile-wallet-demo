part of 'ton_center_client.dart';

extension _TonApiReads on TonCenterClient {
  Future<Map<String, dynamic>> _tonApi(
    TonNetwork network,
    String path, [
    Map<String, String>? query,
  ]) => _jsonRequest(Uri.https(network.tonApiHost, '/v2/$path', query));

  Future<TonWalletState> _apiWallet(
    String address, {
    required bool forSigning,
    required TonNetwork network,
  }) async {
    final result = await _jsonRequest(
      Uri.https(network.tonApiHost, '/v2/blockchain/accounts/$address'),
      allowNotFound: true,
    );
    if (result['error'] == 'entity not found') {
      return TonWalletState(
        balance: BigInt.zero,
        status: 'nonexist',
        seqno: null,
      );
    }
    final status = _accountStatus(result['status']);
    final balance = _nonNegativeAmount(result['balance']);
    int? seqno;
    if (forSigning && status == 'active') {
      try {
        final code = Cell.fromHex(result['code'] as String);
        final data = Cell.fromHex(result['data'] as String).beginParse();
        if (hex.encode(code.hash()) !=
                hex.encode(WalletVersion.v5R1.getCode().hash()) ||
            !data.loadBit()) {
          throw const FormatException('Unsupported V5R1 account');
        }
        seqno = data.loadUint32();
        final walletId = data.loadUint32();
        final publicKey = data.loadBuffer(32);
        final wallet = WalletV5R1.create(
          publicKey: publicKey,
          context: V5R1ClientContext(
            chainId: network.chainId,
            workchain: TonWorkChain.basechain,
            subwalletNumber: 0,
          ),
        );
        final expectedId = wallet.state!.initialData().beginParse()
          ..loadBit()
          ..loadUint32();
        if (walletId != expectedId.loadUint32() ||
            wallet.address.toRawAddress() !=
                TonAddress(address).toRawAddress()) {
          throw const FormatException('Wallet address mismatch');
        }
      } catch (_) {
        throw const TransactionFailure.coded(
          AppErrorCode.tonAccountUnavailable,
        );
      }
    }
    return TonWalletState(balance: balance, status: status, seqno: seqno);
  }

  Future<List<Map<String, dynamic>>> _apiTransactions(
    String address,
    TonNetwork network,
  ) async {
    final reply = await _tonApi(
      network,
      'blockchain/accounts/$address/transactions',
      {'limit': '20'},
    );
    try {
      return [
        for (final row in _rows(reply['transactions']))
          {
            'utime': row['utime'] as int,
            'hash': _base64Hash(row['hash']),
            'data': base64Encode(hex.decode(row['raw'] as String)),
            'in_msg': _apiMessage(row['in_msg']),
            'out_msgs': [
              for (final message in _rows(row['out_msgs']))
                _apiMessage(message),
            ],
          },
      ];
    } catch (_) {
      throw const TransactionFailure.coded(AppErrorCode.tonApiUnavailable);
    }
  }
}

Map<String, dynamic>? _apiMessage(Object? value) {
  if (value == null) return null;
  final message = value as Map<String, dynamic>;
  final body = message['raw_body'];
  return {
    'source': _addressField(message['source']),
    'destination': _addressField(message['destination']),
    'value': message['value'],
    'hash': _base64Hash(message['hash']),
    if (body is String && body.isNotEmpty)
      'body_hash': base64Encode(Cell.fromHex(body).hash()),
  };
}

String? _addressField(Object? value) => switch (value) {
  final String address => address,
  {'address': final String address} => address,
  _ => null,
};

String _base64Hash(Object? value) {
  final bytes = hex.decode(value as String);
  if (bytes.length != 32) {
    throw const FormatException('Invalid TON hash');
  }
  return base64Encode(bytes);
}

String _accountStatus(Object? value) => switch (value) {
  'active' => 'active',
  'uninitialized' || 'uninit' => 'uninitialized',
  'nonexist' => 'nonexist',
  'frozen' => 'frozen',
  _ => throw const TransactionFailure.coded(AppErrorCode.tonApiUnavailable),
};

BigInt _nonNegativeAmount(Object? value) {
  final amount = BigInt.tryParse(value.toString());
  if (amount == null || amount.isNegative) {
    throw const TransactionFailure.coded(AppErrorCode.tonApiUnavailable);
  }
  return amount;
}

List<Map<String, dynamic>> _rows(Object? value) {
  if (value is! List || value.any((item) => item is! Map<String, dynamic>)) {
    throw const TransactionFailure.coded(AppErrorCode.tonApiUnavailable);
  }
  return value.cast<Map<String, dynamic>>();
}
