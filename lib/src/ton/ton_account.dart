import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:ton_dart/ton_dart.dart';

import '../errors/app_error.dart';
import '../key_storage/key_storage_backend.dart';
import 'ton_network.dart';

/// The first Wallet V5R1 account derived from a public key on a specific network.
final class TonAccount {
  TonAccount(List<int> bytes, {this.network = TonNetwork.testnet})
    : publicKey = _validatePublicKey(bytes) {
    wallet = WalletV5R1.create(
      publicKey: publicKey,
      context: V5R1ClientContext(
        chainId: network.chainId,
        workchain: TonWorkChain.basechain,
        subwalletNumber: 0,
      ),
    );
  }

  final Uint8List publicKey;
  final TonNetwork network;
  late final WalletV5R1 wallet;

  String get publicKeyHex => hex.encode(publicKey);
  String get address => wallet.address.address;
  String get rawAddress => wallet.address.toRawAddress();

  TonAccount onNetwork(TonNetwork target) =>
      target == network ? this : TonAccount(publicKey, network: target);

  void checkRecoveryAddress(String? address) {
    final expected = address?.trim();
    if (expected == null || expected.isEmpty) return;
    try {
      final candidate = TonAddress(expected);
      if (network.accepts(candidate) &&
          candidate.workchain == wallet.address.workchain &&
          hex.encode(candidate.hash) == hex.encode(wallet.address.hash)) {
        return;
      }
    } catch (_) {
      // An invalid checksum or address is also a mismatch.
    }
    throw const VaultFailure.coded(AppErrorCode.tonRestoreAddressMismatch);
  }

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
