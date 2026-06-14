import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';

void main() {
  const service = LocalTransactionService();
  // Well-known Anvil/Hardhat account #0 (public test key).
  const walletMaterial = WalletMaterial(
    address: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
    mnemonic: 'test test test',
    privateKeyHex:
        'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
  );

  test('prepareInboundTransaction builds a signable EIP-1559 transfer', () {
    final prepared = service.prepareInboundTransaction(
      network: EvmNetwork.ethereumMainnet,
      fromAddress: walletMaterial.address,
      toAddress: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
      valueWei: BigInt.parse('1000000000000000'),
      data: Uint8List(0),
      gasLimit: 21000,
      maxFeePerGasWei: BigInt.from(2000000000),
      maxPriorityFeePerGasWei: BigInt.from(1000000000),
    );

    expect(prepared.preview.fromAddress, walletMaterial.address);
    expect(prepared.networkConfig.network, EvmNetwork.ethereumMainnet);
    expect(prepared.transaction.maxGas, 21000);

    final signed = service.signPreparedTransfer(
      preparedTransfer: prepared,
      walletMaterial: walletMaterial,
      nonce: 0,
    );

    expect(signed.rawTransactionHex, startsWith('0x02'));
    expect(signed.rawTransactionBytes, isNotEmpty);
    expect(signed.transactionHashHex, startsWith('0x'));
  });
}
