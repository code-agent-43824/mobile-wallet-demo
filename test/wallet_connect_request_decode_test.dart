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

  test('isMessageSignMethod recognises personal_sign / eth_sign', () {
    expect(codec.isMessageSignMethod('personal_sign'), isTrue);
    expect(codec.isMessageSignMethod('eth_sign'), isTrue);
    expect(codec.isMessageSignMethod('eth_sendTransaction'), isFalse);
  });

  test('decodes personal_sign ([message, address]) with hex + utf8', () {
    // 0x48656c6c6f = "Hello"
    final request = codec.decodeMessageRequest('personal_sign', const <Object?>[
      '0x48656c6c6f',
      '0xAbc',
    ]);

    expect(request.address, '0xAbc');
    expect(request.displayText, 'Hello');
    expect(
      request.message,
      Uint8List.fromList(<int>[0x48, 0x65, 0x6c, 0x6c, 0x6f]),
    );
  });

  test('decodes eth_sign with the [address, message] param order', () {
    final request = codec.decodeMessageRequest('eth_sign', const <Object?>[
      '0xAbc',
      'plain text',
    ]);

    expect(request.address, '0xAbc');
    expect(request.displayText, 'plain text');
  });

  test('throws when a message request is missing its address/message', () {
    expect(
      () =>
          codec.decodeMessageRequest('personal_sign', const <Object?>['0x00']),
      throwsA(isA<WalletConnectCodecException>()),
    );
  });

  test('isTypedDataMethod recognises eth_signTypedData_v4 / _v3', () {
    expect(codec.isTypedDataMethod('eth_signTypedData_v4'), isTrue);
    expect(codec.isTypedDataMethod('eth_signTypedData_v3'), isTrue);
    expect(codec.isTypedDataMethod('personal_sign'), isFalse);
  });

  test('decodeTypedDataRequest parses both a Map and a JSON string', () {
    final fromMap = codec.decodeTypedDataRequest(<Object?>[
      '0xAbc',
      <String, dynamic>{'primaryType': 'Msg'},
    ]);
    expect(fromMap.address, '0xAbc');
    expect(fromMap.typedData['primaryType'], 'Msg');

    final fromString = codec.decodeTypedDataRequest(<Object?>[
      '0xAbc',
      '{"primaryType":"Msg"}',
    ]);
    expect(fromString.typedData['primaryType'], 'Msg');
  });

  test('decodeTypedDataRequest throws without an address', () {
    expect(
      () => codec.decodeTypedDataRequest(const <Object?>['{}']),
      throwsA(isA<WalletConnectCodecException>()),
    );
  });
}
