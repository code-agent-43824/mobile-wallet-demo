import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/ton/ton_account.dart';
import 'package:mobile_wallet_demo/src/ton/ton_assets.dart';
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
final _jettonMaster = '0:${'22' * 32}';
final _jettonWallet = '0:${'33' * 32}';

http.Response _json(Map<String, dynamic> result) =>
    http.Response(jsonEncode(result), 200);

void main() {
  test(
    'TonAPI reports a missing account without treating it as an outage',
    () async {
      final client = TonCenterClient(
        requestInterval: Duration.zero,
        client: MockClient(
          (request) async => request.url.host == 'tonapi.io'
              ? http.Response('{"error":"entity not found"}', 404)
              : http.Response('{}', 503),
        ),
      );
      addTearDown(client.close);
      final account = await client.wallet(
        _account.rawAddress,
        network: TonNetwork.mainnet,
        forSigning: true,
      );
      expect(account.balance, BigInt.zero);
      expect(account.status, 'nonexist');
      expect(account.canDeploy, isTrue);
    },
  );

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

  test(
    'Jetton indexing falls back to TON Center and keeps last known data through an outage',
    () async {
      var outage = false;
      final network = _account.network;
      final owner = _account.rawAddress;
      final store = InMemorySecureKeyValueStore();
      final fixture = TonCenterClient(
        requestInterval: Duration.zero,
        client: MockClient((request) async {
          final uri = request.url;
          if (uri.path == '/api/v2/getAddressInformation') {
            return _json({
              'ok': true,
              'result': {'state': 'nonexist', 'balance': '0'},
            });
          }
          if (uri.host == network.tonApiHost || outage) {
            return http.Response('{}', 503);
          }
          expect(uri.host, network.tonCenterHost);
          expect(uri.queryParameters['owner_address'], owner);
          final metadata = {
            _jettonMaster.toUpperCase(): {
              'token_info': [
                {
                  'type': 'jetton_masters',
                  'valid': true,
                  'symbol': 'JET',
                  'name': 'Demo jetton',
                  'extra': {'decimals': '6'},
                },
              ],
            },
          };
          if (uri.path.endsWith('/wallets')) {
            return _json({
              'metadata': metadata,
              'jetton_wallets': [
                {
                  'owner': owner.toUpperCase(),
                  'address': _jettonWallet,
                  'jetton': _jettonMaster,
                  'balance': '2300000',
                },
              ],
            });
          }
          expect(uri.path, '/api/v3/jetton/transfers');
          return _json({
            'metadata': metadata,
            'jetton_transfers': [
              {
                'transaction_aborted': false,
                'transaction_now': 1795809000,
                'source': _otherAddress,
                'destination': owner,
                'amount': '800000',
                'jetton_master': _jettonMaster,
              },
              {'transaction_aborted': true},
            ],
          });
        }),
      );
      addTearDown(fixture.close);
      final service = TonTransferService(client: fixture, store: store);
      final live = (await service.loadJettons(_account))!;
      expect(live.fromCache, isFalse);
      expect(live.balances.single.jetton.master, _jettonMaster);
      expect(live.balances.single.jetton.name, 'Demo jetton');
      expect(live.balances.single.jetton.symbol, 'JET');
      expect(
        formatTonAmount(
          live.balances.single.amount,
          live.balances.single.jetton.decimals,
        ),
        '2.3',
      );
      expect(live.activity.single.incoming, isTrue);
      expect(
        live.activity.single.counterparty,
        network.friendly(TonAddress(_otherAddress)),
      );
      outage = true;
      final restarted = TonTransferService(client: fixture, store: store);
      final cached = (await restarted.loadJettons(_account))!;
      expect(cached.fromCache, isTrue);
      expect(cached.fetchedAt, live.fetchedAt);
      expect(cached.balances.single.amount, live.balances.single.amount);
      expect(cached.activity.single.jetton?.master, _jettonMaster);
      expect(cached.activity.single.amount, live.activity.single.amount);
      expect(
        await restarted.cachedJettons(_account.onNetwork(TonNetwork.testnet)),
        isNull,
      );
      expect((await restarted.load(_account)).fromCache, isFalse);
    },
  );

  test(
    'Jetton getters use TonAPI TVM cells and numbers when TON Center fails',
    () async {
      final owner = _account.rawAddress;
      final network = _account.network;
      Object cell(String address) => {
        'type': 'cell',
        'cell': hex.encode(
          beginCell().storeAddress(TonAddress(address)).endCell().toBoc(),
        ),
      };
      final fixture = TonCenterClient(
        requestInterval: Duration.zero,
        client: MockClient((request) async {
          if (request.url.host == network.tonCenterHost) {
            return http.Response('{}', 503);
          }
          expect(request.url.host, network.tonApiHost);
          final method = request.url.pathSegments.last;
          final stack = switch (method) {
            'get_wallet_address' => [cell(_jettonWallet)],
            'get_wallet_data' => [
              {'type': 'num', 'num': '0x123'},
              cell(owner),
              cell(_jettonMaster),
            ],
            _ => throw StateError('Unexpected getter'),
          };
          if (method == 'get_wallet_address') {
            expect(request.url.pathSegments[3], _jettonMaster);
            expect(request.url.queryParameters['args'], owner);
          } else {
            expect(request.url.pathSegments[3], _jettonWallet);
          }
          return _json({'success': true, 'exit_code': 0, 'stack': stack});
        }),
      );
      addTearDown(fixture.close);
      final wallet = await fixture.jettonWalletAddress(
        master: TonAddress(_jettonMaster),
        owner: _account.wallet.address,
        network: network,
      );
      expect(wallet.toRawAddress(), _jettonWallet);
      final data = await fixture.jettonWalletData(
        wallet: wallet,
        network: network,
      );
      expect(data.balance, BigInt.from(0x123));
      expect(data.owner.toRawAddress(), owner);
      expect(data.master.toRawAddress(), _jettonMaster);
    },
  );
}
