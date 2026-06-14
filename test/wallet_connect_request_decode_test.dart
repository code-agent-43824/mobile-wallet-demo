import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_v2.dart';

void main() {
  const codec = WalletConnectV2RequestCodec();

  test('isTransactionMethod recognises send/sign tx methods', () {
    expect(codec.isTransactionMethod('eth_sendTransaction'), isTrue);
    expect(codec.isTransactionMethod('eth_signTransaction'), isTrue);
    expect(codec.isTransactionMethod('personal_sign'), isFalse);
  });

  test('decodes a full eth_sendTransaction tx object', () {
    final request = codec.decodeTransactionRequest(<Object?>[
      <String, Object?>{
        'from': '0xFrom',
        'to': '0xTo',
        'value': '0xde0b6b3a7640000',
        'data': '0xabcd',
        'nonce': '0x7',
        'gas': '0x5208',
        'maxFeePerGas': '0x3b9aca00',
        'maxPriorityFeePerGas': '0x5f5e100',
      },
    ]);

    expect(request.fromAddress, '0xFrom');
    expect(request.toAddress, '0xTo');
    expect(request.valueWei, BigInt.parse('1000000000000000000'));
    expect(request.data, Uint8List.fromList(<int>[0xab, 0xcd]));
    expect(request.nonce, 7);
    expect(request.gasLimit, 21000);
    expect(request.maxFeePerGasWei, BigInt.from(1000000000));
    expect(request.maxPriorityFeePerGasWei, BigInt.from(100000000));
  });

  test('decodes a minimal tx object (from/to only) with defaults', () {
    final request = codec.decodeTransactionRequest(<Object?>[
      <String, Object?>{'from': '0xFrom', 'to': '0xTo'},
    ]);

    expect(request.valueWei, BigInt.zero);
    expect(request.data, isEmpty);
    expect(request.nonce, isNull);
    expect(request.gasLimit, isNull);
    expect(request.maxFeePerGasWei, isNull);
    expect(request.maxPriorityFeePerGasWei, isNull);
  });

  test('throws when the tx object or required fields are missing', () {
    expect(
      () => codec.decodeTransactionRequest(const <Object?>[]),
      throwsA(isA<WalletConnectCodecException>()),
    );
    expect(
      () => codec.decodeTransactionRequest(<Object?>[
        <String, Object?>{'to': '0xTo'},
      ]),
      throwsA(isA<WalletConnectCodecException>()),
    );
  });
}
