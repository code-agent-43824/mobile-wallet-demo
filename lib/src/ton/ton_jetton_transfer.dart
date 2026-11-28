part of 'ton_transfer_service.dart';

// The TON documentation's TEP-74 example allows 0.1 GRAM for execution and
// possible Jetton wallet deployment. Excesses go back to the sender.
final _jettonAttachment = BigInt.from(100000000);
final _queryIdRandom = Random.secure();

class _JettonTransfer {
  const _JettonTransfer({
    required this.asset,
    required this.senderWallet,
    required this.recipientWallet,
    required this.body,
    required this.queryId,
  });

  final TonJetton asset;
  final TonAddress senderWallet;
  final TonAddress recipientWallet;
  final Cell body;
  final BigInt queryId;
}

extension _JettonTransfers on TonTransferService {
  Future<_JettonTransfer> _prepareJetton(
    TonAccount account,
    TonAddress recipient,
    TonJetton jetton,
    BigInt amount,
  ) async {
    final master = parseTonAddress(jetton.master);
    if (master == null || !account.network.accepts(master)) {
      throw const TransactionFailure.coded(AppErrorCode.tonJettonUnavailable);
    }
    final network = account.network;
    final owner = account.wallet.address;
    final senderWallet = await _client.jettonWalletAddress(
      master: master,
      owner: owner,
      network: network,
    );
    await _requireJettons(account, jetton, senderWallet, amount);
    final recipientWallet = await _client.jettonWalletAddress(
      master: master,
      owner: recipient,
      network: network,
    );
    final queryId =
        (BigInt.from(_queryIdRandom.nextInt(1 << 32)) << 32) |
        BigInt.from(_queryIdRandom.nextInt(1 << 32));
    final body = JettonWalletTransfer(
      queryId: queryId,
      amount: amount,
      destination: recipient,
      responseDestination: owner,
      forwardTonAmount: BigInt.one,
    ).toBody();
    return _JettonTransfer(
      asset: jetton,
      senderWallet: senderWallet,
      recipientWallet: recipientWallet,
      body: body,
      queryId: queryId,
    );
  }

  Future<void> _requireJettons(
    TonAccount account,
    TonJetton jetton,
    TonAddress senderWallet,
    BigInt amount,
  ) async {
    final data = await _client.jettonWalletData(
      wallet: senderWallet,
      network: account.network,
    );
    if (rawTonAddress(data.owner) != account.rawAddress ||
        rawTonAddress(data.master) !=
            rawTonAddress(TonAddress(jetton.master))) {
      throw const TransactionFailure.coded(AppErrorCode.tonJettonUnavailable);
    }
    if (data.balance < amount) {
      throw TransactionFailure.coded(AppErrorCode.txInsufficientAsset, {
        'symbol': jetton.symbol,
      });
    }
  }

  Future<TonTransferStatus> _resolveJetton(
    Map<String, dynamic> recorded,
    Map<String, dynamic> jetton,
    ({Map<String, dynamic> row, TonTransaction transaction}) senderReceipt,
    List<Map<String, dynamic>> senderTransactions,
    TonNetwork network,
  ) async {
    final sender = recorded['recipient'] as String;
    final recipient = jetton['recipientWallet'] as String;
    for (final message in senderReceipt.transaction.outMessages.values) {
      if (!_matchesJettonTransfer(message, sender, recipient, jetton)) continue;
      final bodyHash = base64Encode(message.body.hash());
      for (final row in _outMessages(senderReceipt.row)) {
        final destination = parseTonAddress(row['destination']);
        final hash = row['hash'];
        if (destination == null ||
            rawTonAddress(destination) != recipient ||
            row['body_hash'] != bodyHash ||
            hash is! String) {
          continue;
        }
        final rows = recipient == sender
            ? senderTransactions
            : await _client.transactions(recipient, network: network);
        final receipt = _findReceipt(rows, hash)?.transaction;
        final incoming = receipt?.inMessage;
        final description = receipt?.description;
        if (incoming != null &&
            _matchesJettonTransfer(incoming, sender, recipient, jetton) &&
            description is TransactionDescriptionGeneric) {
          return _executedJetton(description)
              ? TonTransferStatus.confirmed
              : TonTransferStatus.failed;
        }
        return _waitingStatus(recorded);
      }
    }
    return _waitingStatus(recorded);
  }
}

bool _executedJetton(TransactionDescriptionGeneric description) =>
    !description.aborted &&
    description.bouncePhase == null &&
    description.actionPhase?.success != false &&
    switch (description.computePhase) {
      TransactionComputeVm(success: final success) => success,
      _ => false,
    };

bool _matchesJettonTransfer(
  Message message,
  String sender,
  String recipient,
  Map<String, dynamic> jetton,
) {
  final info = message.info;
  if (info is! CommonMessageInfoInternal ||
      info.bounced ||
      rawTonAddress(info.src) != sender ||
      rawTonAddress(info.dest) != recipient) {
    return false;
  }
  try {
    final body = message.body.beginParse();
    // internal_transfer#178d4519, defined by the reference Jetton wallet.
    if (body.loadUint32() != 0x178d4519 ||
        body.loadUint64().toString() != jetton['queryId'] ||
        body.loadCoins().toString() != jetton['amount']) {
      return false;
    }
    return rawTonAddress(body.loadAddress()) == jetton['owner'];
  } catch (_) {
    return false;
  }
}
