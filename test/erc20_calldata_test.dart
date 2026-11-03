import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/transactions/erc20_calldata.dart';
import 'package:web3dart/web3dart.dart' show bytesToHex, hexToBytes, keccak256;

const _recipient = '0x2222222222222222222222222222222222222222';

Uint8List _call(String selector, String addressWord, BigInt amount) =>
    Uint8List.fromList(
      hexToBytes(
        selector + addressWord + amount.toRadixString(16).padLeft(64, '0'),
      ),
    );

String _addressWord(String address) => address.substring(2).padLeft(64, '0');

void main() {
  test('selectors are the Keccak-256 prefixes of their signatures', () {
    String selectorOf(String signature) => bytesToHex(
      keccak256(Uint8List.fromList(utf8.encode(signature))).sublist(0, 4),
    );

    expect(Erc20Call.transferSelector, selectorOf('transfer(address,uint256)'));
    expect(Erc20Call.approveSelector, selectorOf('approve(address,uint256)'));
  });

  test('decodes the calldata it encodes for a transfer', () {
    final data = Erc20Call.encodeTransfer(
      recipient: Uint8List.fromList(hexToBytes(_recipient)),
      amount: BigInt.from(1500000),
    );

    final call = Erc20Call.tryDecode(data)!;

    expect(call.kind, Erc20CallKind.transfer);
    expect(call.counterparty, _recipient);
    expect(call.amount, BigInt.from(1500000));
    expect(call.isUnlimited, isFalse);
  });

  test('an approval of the largest amount is unlimited', () {
    final unlimited = Erc20Call.tryDecode(
      _call('095ea7b3', _addressWord(_recipient), Erc20Call.maxUint256),
    )!;
    final bounded = Erc20Call.tryDecode(
      _call('095ea7b3', _addressWord(_recipient), BigInt.from(10)),
    )!;

    expect(unlimited.kind, Erc20CallKind.approve);
    expect(unlimited.counterparty, _recipient);
    expect(unlimited.isUnlimited, isTrue);
    expect(bounded.isUnlimited, isFalse);
  });

  test('anything but a well-formed transfer or approve stays undecoded', () {
    final word = _addressWord(_recipient);
    final one = BigInt.one;

    // Another function with the same argument shape.
    expect(Erc20Call.tryDecode(_call('23b872dd', word, one)), isNull);
    // An extra or a missing byte.
    expect(
      Erc20Call.tryDecode(
        Uint8List.fromList(<int>[..._call('a9059cbb', word, one), 0]),
      ),
      isNull,
    );
    expect(
      Erc20Call.tryDecode(_call('a9059cbb', word, one).sublist(0, 67)),
      isNull,
    );
    // An address word with dirty padding is not an ABI address.
    expect(
      Erc20Call.tryDecode(_call('a9059cbb', 'ff${word.substring(2)}', one)),
      isNull,
    );
    expect(Erc20Call.tryDecode(Uint8List(0)), isNull);
  });
}
