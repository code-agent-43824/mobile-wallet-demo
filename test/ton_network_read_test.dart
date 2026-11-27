import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/ton/ton_account.dart';
import 'package:mobile_wallet_demo/src/ton/ton_center_client.dart';
import 'package:mobile_wallet_demo/src/ton/ton_network.dart';
import 'package:mobile_wallet_demo/src/ton/ton_transfer_service.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';
import 'package:ton_dart/ton_dart.dart' hide TonAccount;

final _account = TonAccount(
  hex.decode(
    'f6c450a16bb1c514e22f1977e390a3025599aa1e7b00068a6aacf2119484c1bd',
  ),
  network: TonNetwork.mainnet,
);
final _otherAddress = '0:${'11' * 32}';

http.Response _json(Map<String, dynamic> result) =>
    http.Response(jsonEncode(result), 200);

void main() {
  test(
    'Mainnet uses TonAPI for V5R1 state and history after a TON Center failure',
    () async {
      final state = _account.wallet.state!.initialState();
      final hash = '11' * 32;
      final body = beginCell().storeUint32(1).endCell();
      final checkedHosts = <String>[];
      final client = TonCenterClient(
        requestInterval: Duration.zero,
        client: MockClient((request) async {
          checkedHosts.add(request.url.host);
          if (request.url.host == 'toncenter.com') {
            return http.Response('{}', 503);
          }
          expect(request.url.host, 'tonapi.io');
          if (request.url.path.endsWith('/transactions')) {
            return _json({
              'transactions': [
                {
                  'hash': hash,
                  'utime': 1795809000,
                  'raw': hex.encode(body.toBoc()),
                  'in_msg': {
                    'source': {'address': _otherAddress},
                    'value': 9000,
                    'hash': hash,
                    'raw_body': hex.encode(body.toBoc()),
                  },
                  'out_msgs': [],
                },
              ],
            });
          }
          return _json({
            'balance': 100000,
            'status': 'active',
            'code': hex.encode(state.code!.toBoc()),
            'data': hex.encode(state.data!.toBoc()),
          });
        }),
      );
      addTearDown(client.close);
      final stateRead = await client.wallet(
        _account.rawAddress,
        network: TonNetwork.mainnet,
        forSigning: true,
      );
      expect(stateRead.balance, BigInt.from(100000));
      expect(stateRead.seqno, 0);
      final history = await client.transactions(
        _account.rawAddress,
        network: TonNetwork.mainnet,
      );
      expect(history.single['in_msg']['hash'], base64Encode(hex.decode(hash)));
      expect(history.single['in_msg']['body_hash'], base64Encode(body.hash()));
      expect(checkedHosts, [
        'toncenter.com',
        'tonapi.io',
        'toncenter.com',
        'tonapi.io',
      ]);
    },
  );

  test(
    'offline snapshots survive restart and are isolated by network and account',
    () async {
      var offline = false;
      final store = InMemorySecureKeyValueStore();
      final fixture = TonCenterClient(
        requestInterval: Duration.zero,
        client: MockClient((request) async {
          if (offline) return http.Response('{}', 503);
          final result = request.url.path.endsWith('/getAddressInformation')
              ? {'balance': '123000', 'state': 'uninitialized'}
              : [
                  {
                    'utime': 1795809000,
                    'in_msg': {'value': '123000', 'source': _otherAddress},
                    'out_msgs': [],
                  },
                ];
          return _json({'ok': true, 'result': result});
        }),
      );
      addTearDown(fixture.close);
      final service = TonTransferService(client: fixture, store: store);
      final live = await service.load(_account);
      expect(live.fromCache, isFalse);
      offline = true;
      final restarted = TonTransferService(client: fixture, store: store);
      final cached = await restarted.load(_account);
      expect(cached.fromCache, isTrue);
      expect(cached.fetchedAt, live.fetchedAt);
      expect(cached.balance, live.balance);
      expect(cached.activity.single.amount, live.activity.single.amount);
      await expectLater(
        restarted.load(_account.onNetwork(TonNetwork.testnet)),
        throwsA(isA<TransactionFailure>()),
      );
      final anotherKey = await Ed25519().newKeyPairFromSeed(List.filled(32, 7));
      final publicKey = await anotherKey.extractPublicKey();
      final other = TonAccount(publicKey.bytes, network: TonNetwork.mainnet);
      expect(await restarted.cached(other), isNull);
    },
  );
}
