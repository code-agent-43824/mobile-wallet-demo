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
import 'package:mobile_wallet_demo/src/ton/ton_center_client.dart';
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
}

class _Fixture {
  _Fixture() {
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
  bool deployed = true;
  int seqno = 1;
  int broadcasts = 0;
  Message? envelope;
  String? bodyHash;
  Map<String, dynamic>? estimate;
  List<Object> transactions = [];

  Future<http.Response> _reply(http.Request request) async {
    expect(request.url.host, 'testnet.toncenter.com');
    final method = request.url.pathSegments.last;
    final Object result;
    switch (method) {
      case 'getWalletInformation':
        result = {
          'balance': '9000000000',
          'account_state': deployed ? 'active' : 'uninitialized',
          'seqno': seqno,
          'wallet_type': 'wallet v5 r1',
        };
      case 'getAddressInformation':
        result = {'balance': '9000000000', 'state': 'uninitialized'};
      case 'getTransactions':
        result = transactions;
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
