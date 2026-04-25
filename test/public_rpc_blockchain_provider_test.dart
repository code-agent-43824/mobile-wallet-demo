import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';

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

void main() {
  test(
    'falls back to the next RPC endpoint when the first one fails',
    () async {
      final provider = PublicRpcBlockchainProvider(
        transport: _FakeJsonRpcTransport(<String, List<Object>>{
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
      );

      final snapshot = await provider.loadSnapshot(
        network: EvmNetwork.ethereumMainnet,
        address: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      );

      expect(snapshot.providerLabel, 'rpc.ankr.com');
      expect(snapshot.nativeBalanceFormatted, '0');
      expect(snapshot.baseFeeGwei, 1);
    },
  );
}
