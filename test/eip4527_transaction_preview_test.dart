import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/airgap/eip4527.dart';
import 'package:mobile_wallet_demo/src/airgap/eip4527_transaction_preview.dart';
import 'package:web3dart/web3dart.dart' show hexToBytes;

EthSignRequest _request({
  required String signDataHex,
  required int chainId,
  EthSignDataType type = EthSignDataType.typedTransaction,
}) => EthSignRequest(
  requestId: '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
  signData: Uint8List.fromList(hexToBytes(signDataHex)),
  dataType: type,
  chainId: chainId,
  derivationPath: CryptoKeypath.parse("M/44'/60'/0'/0/0"),
);

void main() {
  const decoder = Eip4527TransactionPreviewDecoder();

  test('decodes Mainnet EIP-1559 fields for user verification', () {
    final preview = decoder.decode(
      _request(
        chainId: 1,
        signDataHex:
            '02e80180843b9aca0085069db9ac0082520894'
            '11111111111111111111111111111111111111110180c0',
      ),
    );

    expect(preview.networkLabel, 'Ethereum Mainnet');
    expect(preview.transactionTypeLabel, 'EIP-1559');
    expect(preview.toAddress, '0x1111111111111111111111111111111111111111');
    expect(preview.valueWei, BigInt.one);
    expect(preview.gasLimit, BigInt.from(21000));
    expect(preview.maxFeePerGasWei, BigInt.from(28415994880));
    expect(preview.maximumFeeEth, '0.00059673589248');
    expect(preview.dataLength, 0);
  });

  test('decodes Sepolia EIP-1559 and verifies embedded chain id', () {
    final preview = decoder.decode(
      _request(
        chainId: 11155111,
        signDataHex:
            '02ef83aa36a780843b9aca0085069db9ac0082520894'
            '2222222222222222222222222222222222222222808412345678c0',
      ),
    );

    expect(preview.networkLabel, 'Sepolia');
    expect(preview.toAddress, '0x2222222222222222222222222222222222222222');
    expect(preview.valueWei, BigInt.zero);
    expect(preview.dataLength, 4);
    expect(preview.selector, '0x12345678');
  });

  test('decodes a Mainnet legacy EIP-155 transaction', () {
    final preview = decoder.decode(
      _request(
        chainId: 1,
        type: EthSignDataType.transaction,
        signDataHex:
            'f849808609184e72a00082271094'
            '000000000000000000000000000000000000000080a47f7465737432'
            '000000000000000000000000000000000000000000000000000000600057808080',
      ),
    );

    expect(preview.transactionTypeLabel, 'Legacy');
    expect(preview.networkLabel, 'Ethereum Mainnet');
    expect(preview.toAddress, '0x0000000000000000000000000000000000000000');
    expect(preview.gasLimit, BigInt.from(10000));
    expect(preview.dataLength, 36);
    expect(preview.selector, '0x7f746573');
  });

  test('rejects mismatch between outer and embedded chain ids', () {
    expect(
      () => decoder.decode(
        _request(
          chainId: 11155111,
          signDataHex:
              '02e80180843b9aca0085069db9ac0082520894'
              '11111111111111111111111111111111111111110180c0',
        ),
      ),
      throwsA(isA<Eip4527Exception>()),
    );
  });
}
