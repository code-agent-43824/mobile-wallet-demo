import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';

class _FakeJsonRpcTransport implements JsonRpcTransport {
  _FakeJsonRpcTransport(this._responsesByHost);

  final Map<String, List<Object>> _responsesByHost;

  @override
  Future<Map<String, dynamic>> post({
    required Uri uri,
    required Map<String, dynamic> payload,
  }) async {
    final queue = _responsesByHost[uri.host];
    if (queue == null || queue.isEmpty) {
      throw const BlockchainFailure('No fake response configured.');
    }

    final next = queue.removeAt(0);
    if (next is Exception) {
      throw next;
    }
    if (next is Error) {
      throw next;
    }

    return next as Map<String, dynamic>;
  }
}

class _FakeJsonApiTransport implements JsonApiTransport {
  _FakeJsonApiTransport(this._responsesByPath);

  final Map<String, Object> _responsesByPath;

  @override
  Future<dynamic> get({required Uri uri}) async {
    final key = uri.toString();
    final response = _responsesByPath[key];
    if (response == null) {
      throw const BlockchainFailure('No fake explorer response configured.');
    }
    if (response is Exception) {
      throw response;
    }
    if (response is Error) {
      throw response;
    }
    return response;
  }
}

void main() {
  test('falls back to the next RPC endpoint when the first one fails', () async {
    final provider = PublicRpcBlockchainProvider(
      rpcTransport: _FakeJsonRpcTransport(<String, List<Object>>{
        'cloudflare-eth.com': <Object>[
          const BlockchainFailure('Primary RPC is down.'),
        ],
        'rpc.ankr.com': <Object>[
          <String, dynamic>{'jsonrpc': '2.0', 'id': 1, 'result': '0x0'},
          <String, dynamic>{
            'jsonrpc': '2.0',
            'id': 1,
            'result': <String, dynamic>{'baseFeePerGas': '0x3b9aca00'},
          },
        ],
      }),
      apiTransport: _FakeJsonApiTransport(<String, Object>{
        'https://eth.blockscout.com/api/v2/addresses/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266/transactions':
            <String, dynamic>{
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'hash': '0xabc',
                  'timestamp': '2026-04-25T15:32:00Z',
                  'value': '100000000000000000',
                  'result': 'success',
                  'status': 'ok',
                  'from': <String, dynamic>{'hash': '0xfeed'},
                  'to': <String, dynamic>{
                    'hash': '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
                  },
                },
              ],
            },
        'https://eth.blockscout.com/api/v2/addresses/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266/token-balances':
            <Map<String, dynamic>>[
              <String, dynamic>{
                'value': '42500000',
                'token': <String, dynamic>{
                  'symbol': 'USDC',
                  'name': 'USD Coin',
                  'decimals': '6',
                  'address_hash': '0xToken',
                },
              },
            ],
      }),
    );

    final snapshot = await provider.loadSnapshot(
      network: EvmNetwork.ethereumMainnet,
      address: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
    );

    expect(snapshot.providerLabel, 'rpc.ankr.com');
    expect(snapshot.nativeBalanceFormatted, '0');
    expect(snapshot.baseFeeGwei, 1);
    expect(snapshot.tokenBalances.single.symbol, 'USDC');
    expect(snapshot.recentTransactions.single.directionLabel, 'Входящая');
  });

  test('returns cached snapshot when live RPC endpoints fail', () async {
    final store = InMemorySecureKeyValueStore();
    final provider = PublicRpcBlockchainProvider(
      rpcTransport: _FakeJsonRpcTransport(<String, List<Object>>{
        'cloudflare-eth.com': <Object>[const BlockchainFailure('down')],
        'rpc.ankr.com': <Object>[const BlockchainFailure('down')],
      }),
      apiTransport: _FakeJsonApiTransport(<String, Object>{}),
      cacheStore: store,
    );

    await store.write(
      'wallet_snapshot.ethereumMainnet.0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266',
      '{"address":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","nativeBalanceWei":"1230000000000000000","nativeBalanceFormatted":"1.23","baseFeeGwei":12.3,"providerLabel":"fake-cache","fetchedAtUtc":"2026-04-25T15:32:00.000Z","tokenBalances":[{"symbol":"USDC","name":"USD Coin","balanceFormatted":"42.5","contractAddress":"0xToken"}],"recentTransactions":[{"hash":"0xabc","timestampUtc":"2026-04-25T15:30:00.000Z","directionLabel":"Входящая","counterparty":"0xfeed","valueFormatted":"0.1 ETH","statusLabel":"Confirmed"}]}',
    );

    final snapshot = await provider.loadSnapshot(
      network: EvmNetwork.ethereumMainnet,
      address: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
    );

    expect(snapshot.loadedFromCache, isTrue);
    expect(snapshot.providerLabel, 'fake-cache');
    expect(snapshot.tokenBalances.single.symbol, 'USDC');
    expect(snapshot.recentTransactions.single.hash, '0xabc');
  });
}
