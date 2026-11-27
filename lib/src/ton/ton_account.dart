import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:ton_dart/ton_dart.dart';

/// A public, recoverable Wallet V5R1 identity for the first TON testnet account.
final class TonAccount {
  TonAccount(List<int> bytes) : publicKey = _validatePublicKey(bytes) {
    wallet = WalletV5R1.create(
      publicKey: publicKey,
      context: V5R1ClientContext(
        chainId: TonChainId.testnet,
        workchain: TonWorkChain.basechain,
        subwalletNumber: 0,
      ),
    );
  }

  final Uint8List publicKey;
  late final WalletV5R1 wallet;

  String get publicKeyHex => hex.encode(publicKey);
  String get address => wallet.address.address;
  String get rawAddress => wallet.address.toRawAddress();

  Future<bool> verify(List<int> hash, List<int> signature) {
    if (hash.length != 32 || signature.length != 64) {
      return Future.value(false);
    }
    return Ed25519().verify(
      hash,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
  }

  static Uint8List _validatePublicKey(List<int> bytes) {
    if (bytes.length != 32) {
      throw const FormatException('Invalid Ed25519 public key length');
    }
    return Uint8List.fromList(bytes).asUnmodifiableView();
  }
}
