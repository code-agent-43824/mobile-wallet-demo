import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/auth/wallet_operation_auth.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_inbound.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_service.dart';

const String _walletAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

final WalletTransactionSigner _signer = LocalKeyMaterialTransactionSigner(
  backendId: 'test',
  walletMaterial: const WalletMaterial(
    address: _walletAddress,
    mnemonic: 'test',
    privateKeyHex:
        'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
  ),
);

Map<String, Object?> _txObject({String? from}) {
  return <String, Object?>{
    'from': from ?? _walletAddress,
    'to': '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
    'value': '0x2386f26fc10000',
    'data': '0x',
    'nonce': '0x3',
    'gas': '0x5208',
    'maxFeePerGas': '0x77359400',
    'maxPriorityFeePerGas': '0x3b9aca00',
  };
}

class _FakeBroadcaster implements TransactionBroadcaster {
  @override
  Future<SubmittedTransfer> submit({
    required SignedTransfer signedTransfer,
  }) async {
    return SubmittedTransfer(
      signedTransfer: signedTransfer,
      providerLabel: 'fake-rpc',
      networkTransactionHash: '0xBROADCASThash',
      submittedAtUtc: DateTime.utc(2026, 6, 14),
    );
  }
}

class _FakeNonceProvider implements NonceProvider {
  @override
  Future<LoadedNonce> loadNextNonce({
    required EvmNetworkConfig networkConfig,
    required String address,
  }) async {
    return LoadedNonce(
      network: networkConfig.network,
      address: address,
      nonce: 11,
      providerLabel: 'fake-nonce',
      loadedAtUtc: DateTime.utc(2026, 6, 14),
    );
  }
}

WalletConnectInboundCoordinator _coordinator(FakeWalletConnectService service) {
  return WalletConnectInboundCoordinator(
    service: service,
    transactionService: const LocalTransactionService(),
    broadcaster: _FakeBroadcaster(),
    nonceProvider: _FakeNonceProvider(),
  );
}

void main() {
  test('eth_sendTransaction signs and broadcasts', () async {
    final service = FakeWalletConnectService();
    final request = service.simulateRequest(
      topic: 'topic-1',
      method: 'eth_sendTransaction',
      chainId: 'eip155:1',
      params: <Object?>[_txObject()],
    );

    await _coordinator(
      service,
    ).handleRequest(request: request, signer: _signer);

    expect(service.respondedErrors, isEmpty);
    expect(service.respondedResults.single.id, request.id);
    expect(service.respondedResults.single.result, '0xBROADCASThash');
  });

  test('eth_signTransaction returns signed hex', () async {
    final service = FakeWalletConnectService();
    final request = service.simulateRequest(
      topic: 'topic-1',
      method: 'eth_signTransaction',
      chainId: 'eip155:1',
      params: <Object?>[_txObject()],
    );

    await _coordinator(
      service,
    ).handleRequest(request: request, signer: _signer);

    expect(service.respondedErrors, isEmpty);
    expect(service.respondedResults.single.result, startsWith('0x02'));
  });

  test('rejects a request for another account', () async {
    final service = FakeWalletConnectService();
    final request = service.simulateRequest(
      topic: 'topic-1',
      method: 'eth_sendTransaction',
      chainId: 'eip155:1',
      params: <Object?>[_txObject(from: '0xother')],
    );

    await _coordinator(
      service,
    ).handleRequest(request: request, signer: _signer);

    expect(service.respondedResults, isEmpty);
    expect(service.respondedErrors.single.id, request.id);
  });

  test('rejects an unsupported method', () async {
    final service = FakeWalletConnectService();
    final request = service.simulateRequest(
      topic: 'topic-1',
      method: 'personal_sign',
      chainId: 'eip155:1',
      params: const <Object?>['0xdeadbeef', _walletAddress],
    );

    await _coordinator(
      service,
    ).handleRequest(request: request, signer: _signer);

    expect(service.respondedResults, isEmpty);
    expect(service.respondedErrors.single.id, request.id);
  });
}
