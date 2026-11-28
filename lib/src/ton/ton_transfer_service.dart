import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:ton_dart/ton_dart.dart' hide TonAccount;

import '../errors/app_error.dart';
import '../key_storage/secure_key_value_store.dart';
import '../transactions/transaction_service.dart';
import 'ton_account.dart';
import 'ton_assets.dart';
import 'ton_center_client.dart';
import 'ton_network.dart';

part 'ton_jetton_transfer.dart';
part 'ton_snapshot_cache.dart';

String formatGram(BigInt amount) => formatTonAmount(amount, gramDecimals);

enum TonTransferStatus { pending, confirmed, failed, unknown }

class TonSnapshot {
  const TonSnapshot(
    this.balance,
    this.activity,
    this.lastSubmission, {
    required this.fetchedAt,
    this.fromCache = false,
  });

  final BigInt balance;
  final List<TonActivity> activity;
  final TonTransferStatus? lastSubmission;
  final DateTime fetchedAt;
  final bool fromCache;

  TonSnapshot asCached() => TonSnapshot(
    balance,
    activity,
    lastSubmission,
    fetchedAt: fetchedAt,
    fromCache: true,
  );
}

class TonTransferQuote {
  const TonTransferQuote._({
    required this.account,
    required this.destination,
    required this.amount,
    required this.nativeAmount,
    required this.fee,
    required this.seqno,
    required this.validUntil,
    required _JettonTransfer? jetton,
    required Cell request,
    required StateInit? init,
  }) : _jetton = jetton,
       _request = request,
       _init = init;

  final TonAccount account;
  final String destination;
  final BigInt amount;
  final BigInt nativeAmount;
  final BigInt fee;
  final int seqno;
  final int validUntil;
  final _JettonTransfer? _jetton;
  final Cell _request;
  final StateInit? _init;

  TonJetton? get jetton => _jetton?.asset;

  Uint8List get signingHash => Uint8List.fromList(_request.hash());

  Cell _body(List<int> signature) => beginCell()
      .storeSlice(_request.beginParse())
      .storeBuffer(signature)
      .endCell();
}

class TonTransferService {
  TonTransferService({
    required TonCenterClient client,
    required SecureKeyValueStore store,
    DateTime Function()? now,
  }) : _client = client,
       _store = store,
       _cache = _TonSnapshotCache(store),
       _now = now ?? DateTime.now;

  final TonCenterClient _client;
  final SecureKeyValueStore _store;
  final _TonSnapshotCache _cache;
  final DateTime Function() _now;
  bool _signing = false;

  int get _nowSeconds => _now().millisecondsSinceEpoch ~/ 1000;

  String _submissionKey(TonAccount account) =>
      'wallet.ton_${account.network.name}.submission.${account.rawAddress}';

  Future<TonSnapshot?> cached(TonAccount account) => _cache.read(account);

  Future<TonJettonSnapshot?> cachedJettons(TonAccount account) =>
      _cache.readJettons(account);

  Future<TonJettonSnapshot?> loadJettons(TonAccount account) async {
    final owner = account.rawAddress;
    final network = account.network;
    try {
      final (balances, history) = await (
        _client.jettonBalances(owner, network: network),
        _client.jettonActivity(owner, network: network),
      ).wait;
      final snapshot = TonJettonSnapshot(
        balances: balances,
        activity: history,
        fetchedAt: _now().toUtc(),
      );
      await _cache.writeJettons(account, snapshot);
      return snapshot;
    } on ParallelWaitError {
      return cachedJettons(account);
    }
  }

  Future<TonSnapshot> load(TonAccount account) async {
    try {
      final snapshot = await _loadLive(account);
      await _cache.write(account, snapshot);
      return snapshot;
    } on TransactionFailure catch (failure) {
      if (failure.errorCode != AppErrorCode.tonApiUnavailable) rethrow;
      final snapshot = await cached(account);
      if (snapshot != null) return snapshot;
      rethrow;
    }
  }

  Future<TonSnapshot> _loadLive(TonAccount account) async {
    final network = account.network;
    final state = await _client.wallet(
      account.rawAddress,
      forSigning: false,
      network: network,
    );
    final transactions = state.status == 'nonexist'
        ? <Map<String, dynamic>>[]
        : await _client.transactions(account.rawAddress, network: network);
    final submission = await _readSubmission(account);
    final status = submission == null
        ? null
        : await _submissionStatus(submission, transactions, network);
    final activity = <TonActivity>[];
    for (final transaction in transactions) {
      final time = transaction['utime'];
      if (time is! int) continue;
      final incoming = _message(transaction['in_msg']);
      final outgoing = _outMessages(transaction);
      for (final message in [incoming, ...outgoing]) {
        if (message == null) continue;
        final received = identical(message, incoming);
        final address = parseTonAddress(
          message[received ? 'source' : 'destination'],
        );
        final amount = BigInt.tryParse(message['value'].toString());
        if (address == null || amount == null || amount <= BigInt.zero) {
          continue;
        }
        activity.add(
          TonActivity(
            counterparty: network.friendly(address),
            amount: amount,
            time: DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true),
            incoming: received,
          ),
        );
      }
    }
    return TonSnapshot(
      state.balance,
      activity,
      status,
      fetchedAt: _now().toUtc(),
    );
  }

  Future<TonTransferQuote> prepare({
    required TonAccount account,
    required String recipient,
    required String amount,
    TonJetton? jetton,
  }) async {
    final destination = parseTonAddress(recipient.trim());
    final network = account.network;
    if (destination == null) {
      throw const TransactionFailure.coded(AppErrorCode.txRecipientInvalid);
    }
    if (!network.accepts(destination) ||
        (jetton != null && jetton.network != network)) {
      throw const TransactionFailure.coded(AppErrorCode.tonOtherNetwork);
    }
    final decimals = jetton == null ? gramDecimals : jetton.decimals;
    if (decimals == null) {
      throw const TransactionFailure.coded(AppErrorCode.tonJettonUnavailable);
    }
    final value = _parseAmount(amount.trim(), decimals);
    await _assertNoPending(account);
    final sender = await _client.wallet(
      account.rawAddress,
      forSigning: true,
      network: network,
    );
    if (!sender.active && !sender.canDeploy) {
      throw const TransactionFailure.coded(AppErrorCode.tonAccountUnavailable);
    }
    final route = jetton == null
        ? null
        : await _prepareJetton(account, destination, jetton, value);
    final bounce = route != null || await _nativeBounce(destination, network);
    final nativeAmount = route == null ? value : _jettonAttachment;
    final seqno = sender.active ? sender.seqno! : 0;
    final init = sender.active ? null : account.wallet.state!.initialState();
    final validUntil = _nowSeconds + 180;
    final message = MessageRelaxed(
      info: CommonMessageInfoRelaxedInternal(
        ihrDisabled: true,
        bounce: bounce,
        bounced: false,
        dest: route?.senderWallet ?? destination,
        value: CurrencyCollection(coins: nativeAmount),
        ihrFee: BigInt.zero,
        forwardFee: BigInt.zero,
        createdLt: BigInt.zero,
        createdAt: 0,
      ),
      body: route?.body ?? beginCell().endCell(),
    );
    final request = beginCell()
        .storeUint32(WalletV5AuthType.external.tag)
        .store(account.wallet.state!.context)
        .storeUint32(validUntil)
        .storeUint32(seqno)
        .store(
          OutActionsV5(
            actions: [
              OutActionSendMsg(
                mode:
                    SendModeConst.payGasSeparately | SendModeConst.ignoreErrors,
                outMessage: message,
              ),
            ],
          ),
        )
        .endCell();
    final fee = await _client.estimateFee(
      sender: account.rawAddress,
      network: network,
      unsignedBody: beginCell()
          .storeSlice(request.beginParse())
          .storeBuffer(Uint8List(64))
          .endCell(),
      init: init,
    );
    _requireFunds(sender.balance, nativeAmount, fee);
    return TonTransferQuote._(
      account: account,
      destination: network.friendly(destination),
      amount: value,
      nativeAmount: nativeAmount,
      fee: fee,
      seqno: seqno,
      validUntil: validUntil,
      jetton: route,
      request: request,
      init: init,
    );
  }

  Future<bool> _nativeBounce(TonAddress destination, TonNetwork network) async {
    final target = await _client.wallet(
      rawTonAddress(destination),
      forSigning: false,
      network: network,
    );
    if ((!target.active && !target.canDeploy) ||
        (destination.isFriendly &&
            destination.isBounceable &&
            !target.active)) {
      throw const TransactionFailure.coded(AppErrorCode.tonAccountUnavailable);
    }
    return target.active &&
        (destination.isBounceable || !destination.isFriendly);
  }

  /// True means the gateway accepted the BoC. Chain confirmation is polled
  /// separately. A timeout can still leave the message in flight.
  Future<bool> submit(
    TonTransferQuote quote,
    Future<Uint8List> Function(Uint8List hash) sign,
  ) async {
    if (_signing) {
      throw const TransactionFailure.coded(AppErrorCode.tonTransferPending);
    }
    _signing = true;
    try {
      _checkExpiry(quote);
      await _assertNoPending(quote.account);
      final state = await _client.wallet(
        quote.account.rawAddress,
        forSigning: true,
        network: quote.account.network,
      );
      if ((state.active ? state.seqno : 0) != quote.seqno ||
          state.active != (quote._init == null) ||
          (!state.active && !state.canDeploy)) {
        throw const TransactionFailure.coded(AppErrorCode.tonQuoteExpired);
      }
      _requireFunds(state.balance, quote.nativeAmount, quote.fee);
      final jetton = quote._jetton;
      if (jetton != null) {
        await _requireJettons(
          quote.account,
          jetton.asset,
          jetton.senderWallet,
          quote.amount,
        );
        _checkExpiry(quote);
      }
      final signature = await sign(quote.signingHash);
      _checkExpiry(quote);
      if (!await quote.account.verify(quote.signingHash, signature)) {
        throw const TransactionFailure.coded(AppErrorCode.tonSignatureInvalid);
      }
      final body = quote._body(signature);
      final envelope = Message(
        info: CommonMessageInfoExternalIn(
          dest: quote.account.wallet.address,
          importFee: BigInt.zero,
        ),
        init: quote._init,
        body: body,
      );
      // Store the lookup identity before the request. A crash or an ambiguous
      // response must not trigger a second payment.
      await _store.write(
        _submissionKey(quote.account),
        jsonEncode({
          'bodyHash': base64Encode(body.hash()),
          'recipient': rawTonAddress(
            jetton?.senderWallet ?? TonAddress(quote.destination),
          ),
          'amount': quote.nativeAmount.toString(),
          'validUntil': quote.validUntil,
          if (jetton != null)
            'jetton': {
              'queryId': jetton.queryId.toString(),
              'amount': quote.amount.toString(),
              'owner': quote.account.rawAddress,
              'recipientWallet': rawTonAddress(jetton.recipientWallet),
              'bodyHash': base64Encode(jetton.body.hash()),
            },
        }),
      );
      try {
        await _client.broadcast(
          envelope.serialize().toBase64(),
          network: quote.account.network,
        );
        return true;
      } on TransactionFailure {
        return false;
      }
    } finally {
      _signing = false;
    }
  }

  Future<Map<String, dynamic>?> _readSubmission(TonAccount account) async {
    final raw = await _store.read(_submissionKey(account));
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _assertNoPending(TonAccount account) async {
    final recorded = await _readSubmission(account);
    if (recorded == null) return;
    final transactions = await _client.transactions(
      account.rawAddress,
      network: account.network,
    );
    if (await _submissionStatus(recorded, transactions, account.network) ==
        TonTransferStatus.pending) {
      throw const TransactionFailure.coded(AppErrorCode.tonTransferPending);
    }
  }

  Future<TonTransferStatus> _submissionStatus(
    Map<String, dynamic> recorded,
    List<Map<String, dynamic>> transactions,
    TonNetwork network,
  ) async {
    try {
      return await _resolveSubmission(recorded, transactions, network);
    } on TransactionFailure catch (failure) {
      if (failure.errorCode != AppErrorCode.tonApiUnavailable) rethrow;
      return _waitingStatus(recorded);
    }
  }

  Future<TonTransferStatus> _resolveSubmission(
    Map<String, dynamic> recorded,
    List<Map<String, dynamic>> transactions,
    TonNetwork network,
  ) async {
    for (final transaction in transactions) {
      if (_message(transaction['in_msg'])?['body_hash'] !=
          recorded['bodyHash']) {
        continue;
      }
      for (final outbound in _outMessages(transaction)) {
        final target = parseTonAddress(outbound['destination']);
        final outboundHash = outbound['hash'];
        if (target == null ||
            outboundHash is! String ||
            rawTonAddress(target) != recorded['recipient'] ||
            outbound['value'].toString() != recorded['amount']) {
          continue;
        }
        final jetton = _message(recorded['jetton']);
        if (jetton != null) {
          final bodyHash = outbound['body_hash'];
          if (bodyHash == null) return _waitingStatus(recorded);
          if (bodyHash != jetton['bodyHash']) continue;
        }
        final receipts = await _client.transactions(
          recorded['recipient'] as String,
          network: network,
        );
        final receipt = _findReceipt(receipts, outboundHash);
        final description = receipt?.transaction.description;
        if (receipt == null || description is! TransactionDescriptionGeneric) {
          return _waitingStatus(recorded);
        }
        if (description.bouncePhase != null ||
            (jetton != null && !_executedJetton(description))) {
          return TonTransferStatus.failed;
        }
        if (jetton == null) return TonTransferStatus.confirmed;
        return _resolveJetton(recorded, jetton, receipt, receipts, network);
      }
      return TonTransferStatus.failed;
    }
    return _waitingStatus(recorded);
  }

  TonTransferStatus _waitingStatus(Map<String, dynamic> recorded) =>
      _nowSeconds > (recorded['validUntil'] as int) + 90
      ? TonTransferStatus.unknown
      : TonTransferStatus.pending;

  void _checkExpiry(TonTransferQuote quote) {
    if (_nowSeconds >= quote.validUntil) {
      throw const TransactionFailure.coded(AppErrorCode.tonQuoteExpired);
    }
  }

  static void _requireFunds(BigInt balance, BigInt amount, BigInt fee) {
    if (balance < amount + fee) {
      throw const TransactionFailure.coded(
        AppErrorCode.txInsufficientNativeForAmountAndFee,
        {'symbol': 'GRAM'},
      );
    }
  }

  static BigInt _parseAmount(String value, int decimals) {
    if (value.isEmpty) {
      throw const TransactionFailure.coded(AppErrorCode.txAmountEmpty);
    }
    if (value.length > 38 + decimals ||
        !RegExp(r'^[0-9]+([.,][0-9]+)?$').hasMatch(value)) {
      throw const TransactionFailure.coded(AppErrorCode.txAmountFormat);
    }
    final parts = value.replaceAll(',', '.').split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.length > decimals) {
      throw TransactionFailure.coded(AppErrorCode.txAmountTooManyDecimals, {
        'decimals': decimals,
      });
    }
    final scale = BigInt.from(10).pow(decimals);
    final amount =
        BigInt.parse(parts.first) * scale +
        (decimals == 0
            ? BigInt.zero
            : BigInt.parse(fraction.padRight(decimals, '0')));
    if (amount <= BigInt.zero || amount.bitLength > 120) {
      throw const TransactionFailure.coded(AppErrorCode.txAmountFormat);
    }
    return amount;
  }
}

({Map<String, dynamic> row, TonTransaction transaction})? _findReceipt(
  List<Map<String, dynamic>> rows,
  String hash,
) {
  for (final row in rows) {
    if (_message(row['in_msg'])?['hash'] != hash) continue;
    final data = row['data'];
    if (data is! String || data.length > 65536) return null;
    try {
      return (
        row: row,
        transaction: TonTransaction.deserialize(
          Cell.fromBase64(data).beginParse(),
        ),
      );
    } catch (_) {
      return null;
    }
  }
  return null;
}

Map<String, dynamic>? _message(Object? value) =>
    value is Map<String, dynamic> ? value : null;

Iterable<Map<String, dynamic>> _outMessages(Map<String, dynamic> transaction) {
  final messages = transaction['out_msgs'];
  return messages is List
      ? messages.whereType<Map<String, dynamic>>()
      : const [];
}
