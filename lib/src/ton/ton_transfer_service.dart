import 'dart:convert';
import 'dart:typed_data';

import 'package:ton_dart/ton_dart.dart' hide TonAccount;

import '../errors/app_error.dart';
import '../key_storage/secure_key_value_store.dart';
import '../transactions/transaction_service.dart';
import 'ton_account.dart';
import 'ton_center_client.dart';
import 'ton_network.dart';

final _gramScale = BigInt.from(1000000000);

String formatGram(BigInt amount) {
  final fraction = (amount.abs() % _gramScale)
      .toString()
      .padLeft(9, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  final whole = (amount.abs() ~/ _gramScale).toString();
  final sign = amount.isNegative ? '-' : '';
  return fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction';
}

enum TonTransferStatus { pending, confirmed, failed, unknown }

class TonActivity {
  const TonActivity({
    required this.amount,
    required this.counterparty,
    required this.time,
    required this.incoming,
  });

  final BigInt amount;
  final String counterparty;
  final DateTime time;
  final bool incoming;
}

class TonSnapshot {
  const TonSnapshot(this.balance, this.activity, this.lastSubmission);

  final BigInt balance;
  final List<TonActivity> activity;
  final TonTransferStatus? lastSubmission;
}

class TonTransferQuote {
  const TonTransferQuote._({
    required this.account,
    required this.destination,
    required this.amount,
    required this.fee,
    required this.seqno,
    required this.validUntil,
    required Cell request,
    required StateInit? init,
  }) : _request = request,
       _init = init;

  final TonAccount account;
  final String destination;
  final BigInt amount;
  final BigInt fee;
  final int seqno;
  final int validUntil;
  final Cell _request;
  final StateInit? _init;

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
       _now = now ?? DateTime.now;

  final TonCenterClient _client;
  final SecureKeyValueStore _store;
  final DateTime Function() _now;
  bool _signing = false;

  int get _nowSeconds => _now().millisecondsSinceEpoch ~/ 1000;

  String _submissionKey(TonAccount account) =>
      'wallet.ton_${account.network.name}.submission.${account.rawAddress}';

  Future<TonSnapshot> load(TonAccount account) async {
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
        : await _resolveSubmission(submission, transactions, network);
    final activity = <TonActivity>[];
    for (final transaction in transactions) {
      final time = transaction['utime'];
      if (time is! int) continue;
      final incoming = _message(transaction['in_msg']);
      final outgoing = _outMessages(transaction);
      for (final message in [incoming, ...outgoing]) {
        if (message == null) continue;
        final received = identical(message, incoming);
        final address = _parseAddress(
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
    return TonSnapshot(state.balance, activity, status);
  }

  Future<TonTransferQuote> prepare({
    required TonAccount account,
    required String recipient,
    required String amount,
  }) async {
    final destination = _parseAddress(recipient.trim());
    final network = account.network;
    if (destination == null) {
      throw const TransactionFailure.coded(AppErrorCode.txRecipientInvalid);
    }
    if (!network.accepts(destination)) {
      throw const TransactionFailure.coded(AppErrorCode.tonOtherNetwork);
    }
    final value = _parseAmount(amount.trim());
    await _assertNoPending(account);
    final sender = await _client.wallet(
      account.rawAddress,
      forSigning: true,
      network: network,
    );
    final target = await _client.wallet(
      _canonicalAddress(destination),
      forSigning: false,
      network: network,
    );
    if ((!sender.active && !sender.canDeploy) ||
        (!target.active && !target.canDeploy) ||
        (destination.isFriendly &&
            destination.isBounceable &&
            !target.active)) {
      throw const TransactionFailure.coded(AppErrorCode.tonAccountUnavailable);
    }
    final seqno = sender.active ? sender.seqno! : 0;
    final init = sender.active ? null : account.wallet.state!.initialState();
    final validUntil = _nowSeconds + 180;
    final message = MessageRelaxed(
      info: CommonMessageInfoRelaxedInternal(
        ihrDisabled: true,
        bounce:
            target.active &&
            (destination.isBounceable || !destination.isFriendly),
        bounced: false,
        dest: destination,
        value: CurrencyCollection(coins: value),
        ihrFee: BigInt.zero,
        forwardFee: BigInt.zero,
        createdLt: BigInt.zero,
        createdAt: 0,
      ),
      body: beginCell().endCell(),
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
    _requireFunds(sender.balance, value, fee);
    return TonTransferQuote._(
      account: account,
      destination: network.friendly(destination),
      amount: value,
      fee: fee,
      seqno: seqno,
      validUntil: validUntil,
      request: request,
      init: init,
    );
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
      _requireFunds(state.balance, quote.amount, quote.fee);
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
          'recipient': _canonicalAddress(TonAddress(quote.destination)),
          'amount': quote.amount.toString(),
          'validUntil': quote.validUntil,
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
    if (await _resolveSubmission(recorded, transactions, account.network) ==
        TonTransferStatus.pending) {
      throw const TransactionFailure.coded(AppErrorCode.tonTransferPending);
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
        final target = _parseAddress(outbound['destination']);
        final outboundHash = outbound['hash'];
        if (target == null ||
            outboundHash is! String ||
            _canonicalAddress(target) != recorded['recipient'] ||
            outbound['value'].toString() != recorded['amount']) {
          continue;
        }
        final targetTransactions = await _client.transactions(
          recorded['recipient'] as String,
          network: network,
        );
        for (final incoming in targetTransactions) {
          if (_message(incoming['in_msg'])?['hash'] != outboundHash) {
            continue;
          }
          final data = incoming['data'];
          if (data is! String || data.length > 65536) break;
          try {
            final chainTransaction = TonTransaction.deserialize(
              Cell.fromBase64(data).beginParse(),
            );
            final description = chainTransaction.description;
            if (description is TransactionDescriptionGeneric) {
              return description.bouncePhase != null
                  ? TonTransferStatus.failed
                  : TonTransferStatus.confirmed;
            }
          } catch (_) {
            return _waitingStatus(recorded);
          }
        }
        return _waitingStatus(recorded);
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

  static BigInt _parseAmount(String value) {
    if (value.isEmpty) {
      throw const TransactionFailure.coded(AppErrorCode.txAmountEmpty);
    }
    if (value.length > 38 ||
        !RegExp(r'^[0-9]+([.,][0-9]+)?$').hasMatch(value)) {
      throw const TransactionFailure.coded(AppErrorCode.txAmountFormat);
    }
    final parts = value.replaceAll(',', '.').split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.length > 9) {
      throw const TransactionFailure.coded(
        AppErrorCode.txAmountTooManyDecimals,
        {'decimals': 9},
      );
    }
    final amount =
        BigInt.parse(parts.first) * _gramScale +
        BigInt.parse(fraction.padRight(9, '0'));
    if (amount <= BigInt.zero || amount.bitLength > 120) {
      throw const TransactionFailure.coded(AppErrorCode.txAmountFormat);
    }
    return amount;
  }

  static String _canonicalAddress(TonAddress address) => TonAddress.fromBytes(
    hash: address.hash,
    config: TonAddressConfing.raw(address.workchain),
  ).address;

  static TonAddress? _parseAddress(Object? value) {
    if (value is! String || value.isEmpty || value.length > 70) return null;
    try {
      return TonAddress(value);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _message(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  static Iterable<Map<String, dynamic>> _outMessages(
    Map<String, dynamic> transaction,
  ) => (transaction['out_msgs'] as List? ?? const [])
      .whereType<Map<String, dynamic>>();
}
