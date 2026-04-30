import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_tracker.dart';

class _FakeTrackingTransport implements JsonRpcTransport {
  _FakeTrackingTransport(this.responses);

  final List<Map<String, dynamic>> responses;
  int _index = 0;

  @override
  Future<Map<String, dynamic>> post({
    required Uri uri,
    required Map<String, dynamic> payload,
  }) async {
    if (_index >= responses.length) {
      return <String, dynamic>{'jsonrpc': '2.0', 'id': 1, 'result': null};
    }
    return responses[_index++];
  }
}

void main() {
  test('returns confirmed receipt when RPC returns status 0x1', () async {
    final tracker = TransactionTracker(
      rpcTransport: _FakeTrackingTransport(<Map<String, dynamic>>[
        <String, dynamic>{
          'jsonrpc': '2.0',
          'id': 1,
          'result': <String, dynamic>{
            'status': '0x1',
            'blockNumber': '0x10',
            'gasUsed': '0x5208',
          },
        },
      ]),
      pollInterval: Duration.zero,
      maxAttempts: 1,
    );

    final receipt = await tracker.waitForReceipt(
      networkConfig: evmNetworkConfigs[EvmNetwork.ethereumMainnet]!,
      transactionHash: '0xabc',
    );

    expect(receipt.status, TransactionStatus.confirmed);
    expect(receipt.blockNumber, 16);
    expect(receipt.gasUsed, BigInt.from(21000));
  });

  test('returns pending receipt after timeout without receipt', () async {
    final tracker = TransactionTracker(
      rpcTransport: _FakeTrackingTransport(<Map<String, dynamic>>[
        <String, dynamic>{'jsonrpc': '2.0', 'id': 1, 'result': null},
      ]),
      pollInterval: Duration.zero,
      maxAttempts: 1,
    );

    final receipt = await tracker.waitForReceipt(
      networkConfig: evmNetworkConfigs[EvmNetwork.ethereumMainnet]!,
      transactionHash: '0xabc',
    );

    expect(receipt.status, TransactionStatus.pending);
    expect(receipt.errorMessage, contains('timeout'));
  });
}
