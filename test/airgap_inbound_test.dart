import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/airgap/airgap_inbound.dart';
import 'package:mobile_wallet_demo/src/airgap/airgap_signing.dart';
import 'package:mobile_wallet_demo/src/auth/wallet_operation_auth.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';

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

AirGapSigningRequest _request({
  String from = _walletAddress,
  String chainId = 'eip155:1',
}) {
  return AirGapSigningRequest(
    requestId: 'req-1',
    chainId: chainId,
    fromAddress: from,
    toAddress: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
    valueWeiHex: '0x2386f26fc10000',
    dataHex: '0x',
    nonce: 3,
    gasLimit: 21000,
    maxFeePerGasWeiHex: '0x77359400',
    maxPriorityFeePerGasWeiHex: '0x3b9aca00',
  );
}

void main() {
  const codec = AirGapPayloadCodec();
  const coordinator = AirGapInboundCoordinator();

  test('signs an airgap-tx request into an airgap-sig response', () async {
    final payload = codec.encodeRequest(_request());

    final responsePayload = await coordinator.signRequestPayload(
      requestPayload: payload,
      transactionService: const LocalTransactionService(),
      signer: _signer,
    );

    final response = codec.decodeResponse(responsePayload);
    expect(response.requestId, 'req-1');
    expect(response.rawSignedTransactionHex, startsWith('0x02'));
  });

  test('rejects a request for another account', () async {
    final payload = codec.encodeRequest(_request(from: '0xother'));

    await expectLater(
      coordinator.signRequestPayload(
        requestPayload: payload,
        transactionService: const LocalTransactionService(),
        signer: _signer,
      ),
      throwsA(isA<AirGapPayloadException>()),
    );
  });

  test('rejects an unsupported chain', () async {
    final payload = codec.encodeRequest(_request(chainId: 'eip155:999'));

    await expectLater(
      coordinator.signRequestPayload(
        requestPayload: payload,
        transactionService: const LocalTransactionService(),
        signer: _signer,
      ),
      throwsA(isA<AirGapPayloadException>()),
    );
  });

  test('rejects a malformed payload', () async {
    await expectLater(
      coordinator.signRequestPayload(
        requestPayload: 'not-a-payload',
        transactionService: const LocalTransactionService(),
        signer: _signer,
      ),
      throwsA(isA<AirGapPayloadException>()),
    );
  });
}
