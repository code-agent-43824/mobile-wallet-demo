import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' show bytesToHex, hexToBytes;

/// The two ERC-20 calls a signer most needs to read: moving tokens, and
/// letting someone else move them.
enum Erc20CallKind { transfer, approve }

/// A transaction's data decoded as ERC-20 `transfer` or `approve`, so a
/// preview can say what the call does instead of showing a bare selector.
///
/// The token's decimals and symbol live in the token contract, which a
/// preview does not query, so [amount] stays in the token's smallest units.
class Erc20Call {
  const Erc20Call({
    required this.kind,
    required this.counterparty,
    required this.amount,
  });

  /// `transfer(address,uint256)`; its selector is checked against the
  /// signature's Keccak-256 in the tests.
  static const String transferSelector = 'a9059cbb';

  /// `approve(address,uint256)`.
  static const String approveSelector = '095ea7b3';

  static final BigInt maxUint256 = (BigInt.one << 256) - BigInt.one;

  final Erc20CallKind kind;

  /// The recipient of a transfer, or the spender of an approval, as
  /// lowercase 0x-hex.
  final String counterparty;

  /// In the token's smallest units.
  final BigInt amount;

  /// An approval of the largest amount: the spender may take every token the
  /// sender holds, now and later.
  bool get isUnlimited => kind == Erc20CallKind.approve && amount == maxUint256;

  /// Calldata for `transfer(recipient, amount)`.
  static Uint8List encodeTransfer({
    required Uint8List recipient,
    required BigInt amount,
  }) {
    final hexAmount = amount.toRadixString(16).padLeft(64, '0');
    return Uint8List.fromList(<int>[
      ...hexToBytes(transferSelector),
      ...Uint8List(12),
      ...recipient,
      ...hexToBytes(hexAmount),
    ]);
  }

  /// Decodes [data] as `transfer` or `approve`. Anything else — another
  /// function, missing or extra bytes, an address word whose padding is not
  /// zero — is null, and the preview falls back to the selector.
  static Erc20Call? tryDecode(Uint8List data) {
    if (data.length != 4 + 32 + 32) {
      return null;
    }
    final kind = switch (bytesToHex(data.sublist(0, 4))) {
      transferSelector => Erc20CallKind.transfer,
      approveSelector => Erc20CallKind.approve,
      _ => null,
    };
    if (kind == null || data.sublist(4, 16).any((byte) => byte != 0)) {
      return null;
    }
    var amount = BigInt.zero;
    for (final byte in data.sublist(36)) {
      amount = (amount << 8) | BigInt.from(byte);
    }
    return Erc20Call(
      kind: kind,
      counterparty: bytesToHex(data.sublist(16, 36), include0x: true),
      amount: amount,
    );
  }
}
