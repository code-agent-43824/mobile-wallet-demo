import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_preflight.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_service.dart';

const String _wallet = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

class _MethodTransport implements JsonRpcTransport {
  _MethodTransport(this.responses);

  final Map<String, Map<String, dynamic>> responses;
  final List<Map<String, dynamic>> calls = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> post({
    required Uri uri,
    required Map<String, dynamic> payload,
  }) async {
    calls.add(payload);
    return responses[payload['method']] ??
        <String, dynamic>{
          'jsonrpc': '2.0',
          'id': 1,
          'error': <String, Object?>{
            'code': -32000,
            'message': 'unexpected ${payload['method']}',
          },
        };
  }
}

WalletConnectRequest _request({required Map<String, Object?> transaction}) {
  return WalletConnectRequest(
    id: 42,
    topic: 'topic-1',
    chainId: 'eip155:11155111',
    method: 'eth_sendTransaction',
    params: <Object?>[transaction],
  );
}

void main() {
  test(
    'live preflight simulates and estimates missing gas/EIP-1559 fees',
    () async {
      final transport = _MethodTransport(<String, Map<String, dynamic>>{
        'eth_call': <String, dynamic>{'result': '0x'},
        'eth_estimateGas': <String, dynamic>{'result': '0x186a0'}, // 100,000
        'eth_maxPriorityFeePerGas': <String, dynamic>{
          'result': '0x3b9aca00', // 1 gwei
        },
        'eth_getBlockByNumber': <String, dynamic>{
          'result': <String, Object?>{'baseFeePerGas': '0x77359400'}, // 2 gwei
        },
      });
      final preflight = PublicRpcWalletConnectTransactionPreflight(
        rpcTransport: transport,
      );

      final preview = await preflight.inspect(
        request: _request(
          transaction: <String, Object?>{
            'from': _wallet,
            'to': '0x1111111111111111111111111111111111111111',
            'value': '0x0',
            'data': '0x12345678aabb',
          },
        ),
        walletAddress: _wallet,
      );

      expect(preview.wasSimulated, isTrue);
      expect(preview.gasWasEstimated, isTrue);
      expect(preview.feesWereEstimated, isTrue);
      expect(preview.gasLimit, 120000); // RPC estimate + documented 20% margin
      expect(preview.maxPriorityFeePerGasWei, BigInt.from(1000000000));
      expect(preview.maxFeePerGasWei, BigInt.from(5000000000));
      expect(preview.calldataSelector, '0x12345678');
      expect(transport.calls.map((call) => call['method']), <String>[
        'eth_call',
        'eth_estimateGas',
        'eth_maxPriorityFeePerGas',
        'eth_getBlockByNumber',
      ]);
    },
  );

  test(
    'live preflight preserves supplied gas/fees but still simulates',
    () async {
      final transport = _MethodTransport(<String, Map<String, dynamic>>{
        'eth_call': <String, dynamic>{'result': '0x'},
      });
      final preview =
          await PublicRpcWalletConnectTransactionPreflight(
            rpcTransport: transport,
          ).inspect(
            request: _request(
              transaction: <String, Object?>{
                'from': _wallet,
                'to': '0x1111111111111111111111111111111111111111',
                'value': '0x1',
                'data': '0x',
                'gas': '0x5208',
                'maxFeePerGas': '0x77359400',
                'maxPriorityFeePerGas': '0x3b9aca00',
              },
            ),
            walletAddress: _wallet,
          );

      expect(preview.gasLimit, 21000);
      expect(preview.maxFeePerGasWei, BigInt.from(2000000000));
      expect(preview.maxPriorityFeePerGasWei, BigInt.from(1000000000));
      expect(preview.gasWasEstimated, isFalse);
      expect(preview.feesWereEstimated, isFalse);
      expect(transport.calls.map((call) => call['method']), <String>[
        'eth_call',
      ]);
    },
  );

  test('RPC simulation failure blocks preflight', () async {
    final transport = _MethodTransport(<String, Map<String, dynamic>>{
      'eth_call': <String, dynamic>{
        'error': <String, Object?>{
          'code': 3,
          'message': 'execution reverted: expired',
        },
      },
    });

    await expectLater(
      PublicRpcWalletConnectTransactionPreflight(
        rpcTransport: transport,
      ).inspect(
        request: _request(
          transaction: <String, Object?>{
            'from': _wallet,
            'to': '0x1111111111111111111111111111111111111111',
            'data': '0x12345678',
            'gas': '0x5208',
            'maxFeePerGas': '0x77359400',
            'maxPriorityFeePerGas': '0x3b9aca00',
          },
        ),
        walletAddress: _wallet,
      ),
      throwsA(
        isA<WalletConnectPreflightFailure>().having(
          (error) => error.message,
          'message',
          allOf(contains('execution reverted'), contains('publicnode.com')),
        ),
      ),
    );
  });

  test(
    'offline seam refuses missing fields instead of using constants',
    () async {
      await expectLater(
        const RequestFieldsWalletConnectTransactionPreflight().inspect(
          request: _request(
            transaction: <String, Object?>{
              'from': _wallet,
              'to': '0x1111111111111111111111111111111111111111',
              'data': '0x',
            },
          ),
          walletAddress: _wallet,
        ),
        throwsA(
          isA<WalletConnectPreflightFailure>().having(
            (error) => error.message,
            'message',
            contains('live RPC preflight'),
          ),
        ),
      );
    },
  );
}
