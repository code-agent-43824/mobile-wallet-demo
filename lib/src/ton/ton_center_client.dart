import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ton_dart/ton_dart.dart';

import '../errors/app_error.dart';
import '../transactions/transaction_service.dart';

class TonWalletState {
  const TonWalletState({
    required this.balance,
    required this.status,
    required this.seqno,
  });

  final BigInt balance;
  final String status;
  final int? seqno;

  bool get active => status == 'active';
  bool get canDeploy => status == 'uninitialized' || status == 'nonexist';
}

class TonCenterClient {
  TonCenterClient({
    http.Client? client,
    Duration requestInterval = const Duration(milliseconds: 1100),
  }) : _client = client ?? http.Client(),
       _requestInterval = requestInterval;

  static const _testnetHost = 'testnet.toncenter.com';
  static const _timeout = Duration(seconds: 15);
  final http.Client _client;
  final Duration _requestInterval;
  final Stopwatch _clock = Stopwatch()..start();
  Duration _nextRequest = Duration.zero;
  Future<void> _queue = Future<void>.value();

  Future<TonWalletState> wallet(
    String address, {
    required bool forSigning,
  }) async {
    final result = await _request<Map<String, dynamic>>(
      forSigning ? 'getWalletInformation' : 'getAddressInformation',
      query: {'address': address},
    );
    final status = result['account_state'] ?? result['state'];
    final balance = BigInt.tryParse(result['balance'].toString());
    if (status is! String || balance == null || balance.isNegative) {
      throw const TransactionFailure.coded(AppErrorCode.tonApiUnavailable);
    }
    final seqno = result['seqno'];
    if (forSigning &&
        status == 'active' &&
        (seqno is! int ||
            seqno < 0 ||
            seqno > 0xffffffff ||
            result['wallet_type'] != 'wallet v5 r1' ||
            result['is_signature_allowed'] == false)) {
      throw const TransactionFailure.coded(AppErrorCode.tonAccountUnavailable);
    }
    return TonWalletState(
      balance: balance,
      status: status,
      seqno: seqno is int ? seqno : null,
    );
  }

  Future<List<Map<String, dynamic>>> transactions(String address) async {
    final reply = await _request<List<dynamic>>(
      'getTransactions',
      query: {'address': address, 'limit': '20', 'archival': 'true'},
    );
    return reply.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<BigInt> estimateFee({
    required String sender,
    required Cell unsignedBody,
    required StateInit? init,
  }) async {
    final result = await _request<Map<String, dynamic>>(
      'estimateFee',
      body: {
        'address': sender,
        'body': unsignedBody.toBase64(),
        'ignore_chksig': true,
        if (init?.code != null) 'init_code': init!.code!.toBase64(),
        if (init?.data != null) 'init_data': init!.data!.toBase64(),
      },
    );
    final fees = result['source_fees'];
    if (fees is! Map) {
      throw const TransactionFailure.coded(AppErrorCode.tonApiUnavailable);
    }
    var total = BigInt.zero;
    for (final name in ['in_fwd_fee', 'storage_fee', 'gas_fee', 'fwd_fee']) {
      final value = BigInt.tryParse(fees[name].toString());
      if (value == null || value.isNegative) {
        throw const TransactionFailure.coded(AppErrorCode.tonApiUnavailable);
      }
      total += value;
    }
    if (total == BigInt.zero) {
      throw const TransactionFailure.coded(AppErrorCode.tonApiUnavailable);
    }
    return total;
  }

  Future<void> broadcast(String boc) async {
    await _request<Object>('sendBoc', body: {'boc': boc});
  }

  Future<T> _request<T>(
    String method, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) {
    final turn = _queue.then((_) async {
      final delay = _nextRequest - _clock.elapsed;
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      _nextRequest = _clock.elapsed + _requestInterval;
      try {
        final uri = Uri.https(_testnetHost, '/api/v2/$method', query);
        final response =
            await (body == null
                    ? _client.get(uri)
                    : _client.post(
                        uri,
                        headers: {'content-type': 'application/json'},
                        body: jsonEncode(body),
                      ))
                .timeout(_timeout);
        final json = jsonDecode(response.body);
        if (response.statusCode != 200 || json is! Map || json['ok'] != true) {
          throw const FormatException('TON Center response failed');
        }
        return json['result'] as T;
      } catch (_) {
        throw const TransactionFailure.coded(AppErrorCode.tonApiUnavailable);
      }
    });
    _queue = turn.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return turn;
  }

  void close() => _client.close();
}
