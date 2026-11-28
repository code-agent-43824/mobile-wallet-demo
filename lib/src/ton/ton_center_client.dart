import 'dart:async';
import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:http/http.dart' as http;
import 'package:ton_dart/ton_dart.dart';

import '../errors/app_error.dart';
import '../transactions/transaction_service.dart';
import 'ton_assets.dart';
import 'ton_network.dart';

part 'ton_api_read.dart';
part 'ton_jetton_read.dart';

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

  static const _timeout = Duration(seconds: 15);
  static const _maxRetryWait = Duration(seconds: 8);
  static const _defaultRateLimitWait = Duration(seconds: 2);
  final http.Client _client;
  final Duration _requestInterval;
  final Stopwatch _clock = Stopwatch()..start();
  final Map<String, _TonRequestQueue> _queues = {};

  Future<TonWalletState> wallet(
    String address, {
    required bool forSigning,
    TonNetwork network = TonNetwork.testnet,
  }) => _withFallback(
    () => _centerWallet(address, forSigning: forSigning, network: network),
    () => _apiWallet(address, forSigning: forSigning, network: network),
  );

  Future<TonWalletState> _centerWallet(
    String address, {
    required bool forSigning,
    required TonNetwork network,
  }) async {
    final result = await _request<Map<String, dynamic>>(
      forSigning ? 'getWalletInformation' : 'getAddressInformation',
      network: network,
      query: {'address': address},
    );
    final status = _accountStatus(result['account_state'] ?? result['state']);
    final balance = _nonNegativeAmount(result['balance']);
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

  Future<List<Map<String, dynamic>>> transactions(
    String address, {
    TonNetwork network = TonNetwork.testnet,
  }) => _withFallback(() async {
    final reply = await _request<List<dynamic>>(
      'getTransactions',
      network: network,
      query: {'address': address, 'limit': '20', 'archival': 'true'},
    );
    return _rows(reply);
  }, () => _apiTransactions(address, network));

  Future<List<TonJettonHolding>> jettonBalances(
    String owner, {
    required TonNetwork network,
  }) => _withFallback(
    () => _apiJettonBalances(owner, network),
    () => _centerJettonBalances(owner, network),
  );

  Future<List<TonActivity>> jettonActivity(
    String owner, {
    required TonNetwork network,
  }) => _withFallback(
    () => _apiJettonActivity(owner, network),
    () => _centerJettonActivity(owner, network),
  );

  Future<TonAddress> jettonWalletAddress({
    required TonAddress master,
    required TonAddress owner,
    required TonNetwork network,
  }) => _jettonGetter(
    network,
    master,
    'get_wallet_address',
    owner: owner,
    parse: (stack) => _stackCell(stack, 0).beginParse().loadAddress(),
  );

  Future<TonJettonWalletData> jettonWalletData({
    required TonAddress wallet,
    required TonNetwork network,
  }) => _jettonGetter(
    network,
    wallet,
    'get_wallet_data',
    parse: (stack) => TonJettonWalletData(
      _nonNegativeAmount(_stackNumber(stack, 0)),
      _stackCell(stack, 1).beginParse().loadAddress(),
      _stackCell(stack, 2).beginParse().loadAddress(),
    ),
  );

  Future<BigInt> estimateFee({
    required String sender,
    required Cell unsignedBody,
    required StateInit? init,
    TonNetwork network = TonNetwork.testnet,
  }) async {
    final result = await _request<Map<String, dynamic>>(
      'estimateFee',
      network: network,
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

  Future<void> broadcast(
    String boc, {
    TonNetwork network = TonNetwork.testnet,
  }) async {
    await _request<Object>('sendBoc', network: network, body: {'boc': boc});
  }

  Future<T> _request<T>(
    String method, {
    required TonNetwork network,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final result = await _jsonRequest(
      Uri.https(network.tonCenterHost, '/api/v2/$method', query),
      body: body,
      retryRateLimit: method != 'sendBoc',
    );
    final payload = result['result'];
    if (result['ok'] != true || payload is! T) {
      throw const TransactionFailure.coded(AppErrorCode.tonApiUnavailable);
    }
    return payload;
  }

  Future<Map<String, dynamic>> _jsonRequest(
    Uri uri, {
    Map<String, dynamic>? body,
    bool retryRateLimit = true,
    bool allowNotFound = false,
  }) {
    final queue = _queues.putIfAbsent(uri.host, _TonRequestQueue.new);
    final turn = queue.tail.then((_) async {
      try {
        var response = await _send(uri, body, queue);
        if (response.statusCode == 429) {
          final delay = _applyRateLimit(response, queue);
          if (retryRateLimit && delay <= _maxRetryWait) {
            response = await _send(uri, body, queue);
            if (response.statusCode == 429) _applyRateLimit(response, queue);
          }
        }
        final json = jsonDecode(response.body);
        final ok =
            response.statusCode == 200 ||
            (allowNotFound &&
                response.statusCode == 404 &&
                json is Map &&
                json['error'] == 'entity not found');
        if (!ok || json is! Map<String, dynamic>) {
          throw const FormatException('TON API response failed');
        }
        return json;
      } catch (_) {
        throw const TransactionFailure.coded(AppErrorCode.tonApiUnavailable);
      }
    });
    queue.tail = turn.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return turn;
  }

  Future<http.Response> _send(
    Uri uri,
    Map<String, dynamic>? body,
    _TonRequestQueue queue,
  ) async {
    final delay = queue.next - _clock.elapsed;
    if (delay > _maxRetryWait) {
      throw const TransactionFailure.coded(AppErrorCode.tonApiUnavailable);
    }
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    try {
      return await (body == null
              ? _client.get(uri)
              : _client.post(
                  uri,
                  headers: {'content-type': 'application/json'},
                  body: jsonEncode(body),
                ))
          .timeout(_timeout);
    } finally {
      queue.next = _clock.elapsed + _requestInterval;
    }
  }

  Duration _applyRateLimit(http.Response response, _TonRequestQueue queue) {
    final seconds = int.tryParse(response.headers['retry-after'] ?? '');
    final wait = seconds == null || seconds < 0
        ? _defaultRateLimitWait
        : Duration(seconds: seconds.clamp(0, 86400));
    final next = _clock.elapsed + wait;
    if (next > queue.next) queue.next = next;
    return wait;
  }

  void close() => _client.close();
}

class _TonRequestQueue {
  Future<void> tail = Future<void>.value();
  Duration next = Duration.zero;
}

Future<T> _withFallback<T>(
  Future<T> Function() primary,
  Future<T> Function() backup,
) async {
  try {
    return await primary();
  } on TransactionFailure catch (failure) {
    if (failure.errorCode != AppErrorCode.tonApiUnavailable) rethrow;
  }
  return backup();
}
