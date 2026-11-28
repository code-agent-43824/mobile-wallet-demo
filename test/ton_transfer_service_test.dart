import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_wallet_demo/src/errors/app_error.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/key_storage/ton_mnemonic.dart';
import 'package:mobile_wallet_demo/src/ton/ton_account.dart';
import 'package:mobile_wallet_demo/src/ton/ton_assets.dart';
import 'package:mobile_wallet_demo/src/ton/ton_center_client.dart';
import 'package:mobile_wallet_demo/src/ton/ton_network.dart';
import 'package:mobile_wallet_demo/src/ton/ton_transfer_service.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';
import 'package:ton_dart/ton_dart.dart' hide TonAccount;

import 'fixtures/ton_test_vectors.dart';

final _account = TonAccount(
  hex.decode(
    'f6c450a16bb1c514e22f1977e390a3025599aa1e7b00068a6aacf2119484c1bd',
  ),
);
final _recipient = '0:${'11' * 32}';
final _master = '0:${'22' * 32}';
final _senderJetton = '0:${'33' * 32}';
final _recipientJetton = '0:${'44' * 32}';

Future<Uint8List> _sign(Uint8List hash) async {
  final algorithm = Ed25519();
  final seed = await TonMnemonic.deriveSeed(tonTestMnemonic);
  try {
    final pair = await algorithm.newKeyPairFromSeed(seed);
    return Uint8List.fromList(
      (await algorithm.sign(hash, keyPair: pair)).bytes,
    );
  } finally {
    seed.fillRange(0, seed.length, 0);
  }
}

void main() {
  test(
    'Mainnet derives its own V5R1 address and uses only Mainnet endpoints',
    () async {
      final fixture = _Fixture(network: TonNetwork.mainnet);
      final account = _account.onNetwork(TonNetwork.mainnet);
      expect(
        account.address,
        'UQDSLOFVamNZzdy4LulclcCBEFkRReZ7WscBCLAw3Pg53h3h',
      );
      expect(account.rawAddress, isNot(_account.rawAddress));
      await expectLater(
        fixture.service.prepare(
          account: account,
          recipient: _account.address,
          amount: '1',
        ),
        throwsA(
          isA<TransactionFailure>().having(
            (failure) => failure.errorCode,
            'code',
            AppErrorCode.tonOtherNetwork,
          ),
        ),
      );
      final quote = await fixture.service.prepare(
        account: account,
        recipient: _recipient,
        amount: '1',
      );
      expect(TonAddress(quote.destination).isTestOnly, isFalse);
      expect(await fixture.service.submit(quote, _sign), isTrue);
      final envelope = fixture.envelope!.info as CommonMessageInfoExternalIn;
      expect(envelope.dest.toRawAddress(), account.rawAddress);
    },
  );

  test('TON Center backs off on 429 and broadcasts a BoC at most once', () async {
    var reads = 0;
    var broadcasts = 0;
    final client = TonCenterClient(
      requestInterval: Duration.zero,
      client: MockClient((request) async {
        if (request.url.pathSegments.last == 'getWalletInformation') {
          reads++;
          if (reads == 2) {
            return http.Response(
              '{"ok":true,"result":{"balance":"100","account_state":"uninitialized"}}',
              200,
            );
          }
        } else {
          broadcasts++;
        }
        return http.Response(
          '{"ok":false}',
          429,
          headers: {'retry-after': '0'},
        );
      }),
    );
    addTearDown(client.close);
    expect(
      (await client.wallet(_account.rawAddress, forSigning: true)).balance,
      BigInt.from(100),
    );
    await expectLater(
      client.broadcast('test-boc'),
      throwsA(isA<TransactionFailure>()),
    );
    expect(reads, 2);
    expect(broadcasts, 1);
  });

  test('a matching recipient transaction confirms the outgoing payment', () async {
    final fixture = _Fixture();
    final quote = await fixture.service.prepare(
      account: _account,
      recipient: _recipient,
      amount: '1.2',
    );
    await fixture.service.submit(quote, _sign);
    // Synthetic recipient transaction serialized by @ton/core.
    const inboundHash = 'ruqi5rmgk90XY/AI0+WQdTb1bfnidtT/4BGwSzmp7eI=';
    const receipt =
        'te6cckECBQEAAQEAA7FxERERERERERERERERERERERERERERERERERERERERERAAAAAAAAAA'
        'EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAa0nSAAAAAgKAEDBAEB'
        'oAIAq0gBbYbj/UPycBpPIZTv18vqRBuxKx4sUReHjZresu9r/WcABERERERERERERERERERE'
        'RERERERERERERERERERERERRHhowAAAAAAAAAAAAAAAAAABAAIJyAAAAAAAAAAAAAAAAAAAA'
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADCBIp'
        'fTxC';
    expect(
      TonTransaction.deserialize(
        Cell.fromBase64(receipt).beginParse(),
      ).description,
      isA<TransactionDescriptionGeneric>(),
    );
    fixture.transactions = [
      {
        'in_msg': {'body_hash': fixture.bodyHash},
        'out_msgs': [
          {
            'hash': inboundHash,
            'destination': _recipient,
            'value': '1200000000',
          },
        ],
      },
    ];
    fixture.recipientTransactions = [
      {
        'in_msg': {'hash': inboundHash},
        'data': receipt,
      },
    ];
    expect(
      (await fixture.service.load(_account)).lastSubmission,
      TonTransferStatus.confirmed,
    );
  });

  test(
    'a transfer matches the Wallet V5R1 reference body and reconciles a failed action',
    () async {
      final fixture = _Fixture();
      final quote = await fixture.service.prepare(
        account: _account,
        recipient: _recipient,
        amount: '1,2',
      );
      expect(quote.amount, BigInt.from(1200000000));
      expect(quote.fee, BigInt.from(10));
      expect(formatGram(quote.amount), '1.2');
      expect(await fixture.service.submit(quote, _sign), isTrue);
      final bodyHash = fixture.bodyHash!;
      expect(
        hex.encode(base64Decode(bodyHash)),
        'a28739f4bad9112c60c0e0a3dc6168b401be8143392b564705af0c38be6fba63',
      );
      expect(
        (await fixture.service.load(_account)).lastSubmission,
        TonTransferStatus.pending,
      );
      await expectLater(
        fixture.service.submit(quote, _sign),
        throwsA(
          isA<TransactionFailure>().having(
            (error) => error.errorCode,
            'code',
            AppErrorCode.tonTransferPending,
          ),
        ),
      );
      fixture.transactions = [
        {
          'in_msg': {'body_hash': bodyHash},
          'out_msgs': [],
        },
      ];
      expect(
        (await fixture.service.load(_account)).lastSubmission,
        TonTransferStatus.failed,
      );
      expect(fixture.broadcasts, 1);
    },
  );

  test(
    'the first transfer includes StateInit and has a finite deadline',
    () async {
      final fixture = _Fixture()..deployed = false;
      final quote = await fixture.service.prepare(
        account: _account,
        recipient: _recipient,
        amount: '1',
      );
      expect(quote.seqno, 0);
      expect(fixture.estimate!['init_code'], isA<String>());
      expect(fixture.estimate!['init_data'], isA<String>());
      final body = Cell.fromBase64(
        fixture.estimate!['body'] as String,
      ).beginParse();
      expect(body.loadUint32(), WalletV5AuthType.external.tag);
      body.loadUint32(); // Wallet ID.
      expect(body.loadUint32(), quote.validUntil);
      expect(await fixture.service.submit(quote, _sign), isTrue);
      expect(fixture.envelope!.init, isNotNull);
    },
  );

  test('new seqno and mainnet addresses require a new review', () async {
    final fixture = _Fixture();
    await expectLater(
      fixture.service.prepare(
        account: _account,
        recipient: TonAddress(_recipient).toFriendly(testOnly: false).address,
        amount: '1',
      ),
      throwsA(
        isA<TransactionFailure>().having(
          (error) => error.errorCode,
          'code',
          AppErrorCode.tonOtherNetwork,
        ),
      ),
    );
    final quote = await fixture.service.prepare(
      account: _account,
      recipient: _recipient,
      amount: '1',
    );
    fixture.seqno++;
    await expectLater(
      fixture.service.submit(
        quote,
        (_) async => throw StateError('Signing should not start'),
      ),
      throwsA(
        isA<TransactionFailure>().having(
          (error) => error.errorCode,
          'code',
          AppErrorCode.tonQuoteExpired,
        ),
      ),
    );
    expect(fixture.broadcasts, 0);
  });

  test(
    'Jetton confirmation requires a successful recipient wallet transaction',
    () async {
      final fixture = _Fixture(network: TonNetwork.mainnet);
      final account = _account.onNetwork(fixture.network);
      final asset = TonJetton(
        network: fixture.network,
        master: _master,
        symbol: 'JET',
        decimals: 6,
      );
      final quote = await fixture.service.prepare(
        account: account,
        recipient: _recipient,
        amount: '1,250001',
        jetton: asset,
      );
      expect(quote.amount, BigInt.from(1250001));
      expect(formatGram(quote.nativeAmount), '0.1');
      expect(quote.jetton?.master, _master);
      expect(
        quote.destination,
        TonNetwork.mainnet.friendly(TonAddress(_recipient)),
      );
      expect(await fixture.service.submit(quote, _sign), isTrue);

      final request = fixture.envelope!.body.beginParse();
      expect(request.loadUint32(), WalletV5AuthType.external.tag);
      request.loadUint32(); // Wallet ID.
      expect(request.loadUint32(), quote.validUntil);
      expect(request.loadUint32(), quote.seqno);
      final action =
          OutActionsV5.deserialize(request).actions.single as OutActionSendMsg;
      final info = action.outMessage.info as CommonMessageInfoRelaxedInternal;
      final transfer = JettonWalletTransfer.deserialize(
        action.outMessage.body.beginParse(),
      );
      expect(info.dest.toRawAddress(), _senderJetton);
      expect(info.bounce, isTrue);
      expect(info.value.coins, quote.nativeAmount);
      expect(transfer.amount, quote.amount);
      expect(transfer.destination.toRawAddress(), _recipient);
      expect(transfer.responseDestination?.toRawAddress(), account.rawAddress);
      expect(transfer.forwardTonAmount, BigInt.one);

      final firstHop = _internalMessage(
        account.rawAddress,
        _senderJetton,
        action.outMessage.body,
        quote.nativeAmount,
      );
      final secondHop = _internalMessage(
        _senderJetton,
        _recipientJetton,
        beginCell()
            .store(
              JettonMinterInternalTransfer(
                queryId: transfer.queryId,
                jettonAmount: transfer.amount,
                from: account.wallet.address,
                responseAddress: account.wallet.address,
                forwardTonAmount: BigInt.one,
              ),
            )
            .endCell(),
        BigInt.from(50000000),
      );
      fixture.transactions = [
        {
          'in_msg': {'body_hash': fixture.bodyHash},
          'out_msgs': [_messageRow(firstHop)],
        },
      ];
      fixture.jettonTransactions[_senderJetton] = [
        _receipt(firstHop, outbound: [secondHop]),
      ];
      expect(
        (await fixture.service.load(account)).lastSubmission,
        TonTransferStatus.pending,
      );
      fixture.jettonTransactions[_recipientJetton] = [
        _receipt(secondHop, aborted: true),
      ];
      expect(
        (await fixture.service.load(account)).lastSubmission,
        TonTransferStatus.failed,
      );
      fixture.jettonTransactions[_recipientJetton] = [_receipt(secondHop)];
      expect(
        (await fixture.service.load(account)).lastSubmission,
        TonTransferStatus.confirmed,
      );
      expect(fixture.broadcasts, 1);
    },
  );

  test(
    'Jetton quote checks network, precision, owner and both balances',
    () async {
      final fixture = _Fixture();
      Future<TonTransferQuote> prepare({
        String amount = '1.25',
        Object? decimals = 6,
        TonNetwork network = TonNetwork.testnet,
      }) => fixture.service.prepare(
        account: _account,
        recipient: _recipient,
        amount: amount,
        jetton: TonJetton(
          network: network,
          master: _master,
          decimals: decimals,
        ),
      );
      Matcher failsWith(AppErrorCode code) => throwsA(
        isA<TransactionFailure>().having(
          (error) => error.errorCode,
          'code',
          code,
        ),
      );

      await expectLater(
        prepare(network: TonNetwork.mainnet),
        failsWith(AppErrorCode.tonOtherNetwork),
      );
      await expectLater(
        prepare(decimals: null),
        failsWith(AppErrorCode.tonJettonUnavailable),
      );
      await expectLater(
        prepare(amount: '1.2500001'),
        failsWith(AppErrorCode.txAmountTooManyDecimals),
      );
      expect((await prepare(amount: '3', decimals: 0)).amount, BigInt.from(3));
      fixture.jettonOwner = _recipient;
      await expectLater(
        prepare(),
        failsWith(AppErrorCode.tonJettonUnavailable),
      );
      fixture.jettonOwner = null;
      fixture.jettonMaster = _recipient;
      await expectLater(
        prepare(),
        failsWith(AppErrorCode.tonJettonUnavailable),
      );
      fixture.jettonMaster = _master;
      fixture.nativeBalance = 100000000;
      await expectLater(
        prepare(),
        failsWith(AppErrorCode.txInsufficientNativeForAmountAndFee),
      );
      fixture.nativeBalance = 9000000000;
      final quote = await prepare();
      fixture.jettonBalance = 1;
      await expectLater(prepare(), failsWith(AppErrorCode.txInsufficientAsset));
      await expectLater(
        fixture.service.submit(
          quote,
          (_) async => fail('Signing should not start'),
        ),
        failsWith(AppErrorCode.txInsufficientAsset),
      );
      expect(fixture.broadcasts, 0);
    },
  );
}

Message _internalMessage(
  String source,
  String dest,
  Cell body,
  BigInt amount,
) => Message(
  info: CommonMessageInfoInternal(
    ihrDisabled: true,
    bounce: true,
    bounced: false,
    src: TonAddress(source),
    dest: TonAddress(dest),
    value: CurrencyCollection(coins: amount),
    ihrFee: BigInt.zero,
    forwardFee: BigInt.zero,
    createdLt: BigInt.one,
    createdAt: 1799999820,
  ),
  body: body,
);

Map<String, Object?> _messageRow(Message message) {
  final info = message.info as CommonMessageInfoInternal;
  return {
    'hash': base64Encode(message.serialize().hash()),
    'body_hash': base64Encode(message.body.hash()),
    'source': info.src.toRawAddress(),
    'destination': info.dest.toRawAddress(),
    'value': info.value.coins.toString(),
  };
}

Map<String, Object?> _receipt(
  Message inbound, {
  List<Message> outbound = const [],
  bool aborted = false,
}) {
  final info = inbound.info as CommonMessageInfoInternal;
  final zeros = List<int>.filled(32, 0);
  final transaction = TonTransaction(
    address: BigInt.parse(hex.encode(info.dest.hash), radix: 16),
    lt: BigInt.two,
    prevTransactionHash: BigInt.zero,
    prevTransactionLt: BigInt.zero,
    now: info.createdAt,
    outMessagesCount: outbound.length,
    oldStatus: AccountStatus.active,
    endStatus: AccountStatus.active,
    inMessage: inbound,
    outMessages: outbound.asMap(),
    totalFees: CurrencyCollection(coins: BigInt.one),
    stateUpdate: HashUpdate(oldHash: zeros, newHash: zeros),
    description: TransactionDescriptionGeneric(
      creditFirst: false,
      storagePhase: null,
      creditPhase: null,
      computePhase: TransactionComputeVm(
        success: !aborted,
        messageStateUsed: false,
        accountActivated: false,
        gasFees: BigInt.one,
        gasUsed: BigInt.one,
        gasLimit: BigInt.two,
        gasCredit: null,
        mode: 0,
        exitCode: aborted ? 42 : 0,
        exitArg: null,
        vmSteps: 1,
        vmInitStateHash: BigInt.zero,
        vmFinalStateHash: BigInt.zero,
      ),
      actionPhase: null,
      bouncePhase: null,
      aborted: aborted,
      destroyed: false,
    ),
    raw: beginCell().endCell(),
  );
  return {
    'data': beginCell().store(transaction).endCell().toBase64(),
    'in_msg': _messageRow(inbound),
    'out_msgs': outbound.map(_messageRow).toList(),
  };
}

class _Fixture {
  _Fixture({this.network = TonNetwork.testnet}) {
    service = TonTransferService(
      client: TonCenterClient(
        client: MockClient(_reply),
        requestInterval: Duration.zero,
      ),
      store: InMemorySecureKeyValueStore(),
      now: () =>
          DateTime.fromMillisecondsSinceEpoch(1799999820000, isUtc: true),
    );
  }

  late final TonTransferService service;
  final TonNetwork network;
  bool deployed = true;
  int seqno = 1;
  int broadcasts = 0;
  int nativeBalance = 9000000000;
  int jettonBalance = 9000000;
  String? jettonOwner;
  String jettonMaster = _master;
  Message? envelope;
  String? bodyHash;
  Map<String, dynamic>? estimate;
  List<Object> transactions = [];
  List<Object> recipientTransactions = [];
  final jettonTransactions = <String, List<Object>>{};

  Future<http.Response> _reply(http.Request request) async {
    expect(request.url.host, network.tonCenterHost);
    final method = request.url.pathSegments.last;
    final Object result;
    switch (method) {
      case 'getWalletInformation':
        result = {
          'balance': nativeBalance.toString(),
          'account_state': deployed ? 'active' : 'uninitialized',
          'seqno': seqno,
          'wallet_type': 'wallet v5 r1',
        };
      case 'getAddressInformation':
        result = {'balance': '9000000000', 'state': 'uninitialized'};
      case 'getTransactions':
        final address = request.url.queryParameters['address'];
        result =
            jettonTransactions[address] ??
            (address == _recipient ? recipientTransactions : transactions);
      case 'runGetMethod':
        final input = jsonDecode(request.body) as Map<String, dynamic>;
        Object addressCell(String value) => [
          'cell',
          {
            'bytes': beginCell()
                .storeAddress(TonAddress(value))
                .endCell()
                .toBase64(),
          },
        ];
        final owner = _account.onNetwork(network).rawAddress;
        switch (input['method']) {
          case 'get_wallet_address':
            expect(input['address'], _master);
            final argument = (input['stack'] as List).single as List;
            expect(argument.first, 'tvm.Slice');
            final address = Cell.fromBase64(
              argument.last as String,
            ).beginParse().loadAddress().toRawAddress();
            expect(address, anyOf(owner, _recipient));
            result = {
              'exit_code': 0,
              'stack': [
                addressCell(
                  address == owner ? _senderJetton : _recipientJetton,
                ),
              ],
            };
          case 'get_wallet_data':
            expect(input['address'], _senderJetton);
            result = {
              'exit_code': 0,
              'stack': [
                ['num', '0x${jettonBalance.toRadixString(16)}'],
                addressCell(jettonOwner ?? owner),
                addressCell(jettonMaster),
              ],
            };
          default:
            throw StateError('Unexpected getter');
        }
      case 'estimateFee':
        estimate = jsonDecode(request.body) as Map<String, dynamic>;
        expect(estimate!['ignore_chksig'], isTrue);
        result = {
          'source_fees': {
            'in_fwd_fee': 1,
            'storage_fee': 2,
            'gas_fee': 3,
            'fwd_fee': 4,
          },
        };
      case 'sendBoc':
        broadcasts++;
        final boc = (jsonDecode(request.body) as Map)['boc'] as String;
        envelope = Message.deserialize(Cell.fromBase64(boc).beginParse());
        bodyHash = base64Encode(envelope!.body.hash());
        result = {'@type': 'ok'};
      default:
        throw StateError('Unexpected API method $method');
    }
    return http.Response(jsonEncode({'ok': true, 'result': result}), 200);
  }
}
