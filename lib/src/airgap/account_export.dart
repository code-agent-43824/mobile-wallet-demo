import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;

import 'eip4527.dart';

/// Derives the EIP-4527 / BC-UR account-export ([CryptoHDKey]) an online wallet
/// (e.g. MetaMask) imports to add this wallet **watch-only** ("pairing").
///
/// Exports the **account-level** BIP-44 node (default `m/44'/60'/0'`) as a
/// *derived public* key: its 33-byte compressed pubkey + 32-byte chain code +
/// the `origin` path (carrying the master fingerprint) + the parent fingerprint
/// + ETH `use-info` (coin type 60). The online wallet then derives addresses
/// `M/0/i` from it — index 0 is exactly this wallet's own `m/44'/60'/0'/0/0`
/// address. **Only public material is exported; the private key never leaves.**
///
/// This is the single-account "BIP44 Standard" form (a bare `crypto-hdkey`),
/// not the multi-key `crypto-account` container Keystone uses for Bitcoin /
/// Ledger-Live-style multi-account exports.
class AccountExportDeriver {
  const AccountExportDeriver();

  /// The default Ethereum BIP-44 account-level path.
  static const String defaultAccountPath = "m/44'/60'/0'";

  /// Builds the [CryptoHDKey] account export for [mnemonic] at [accountPath]
  /// (the account-level node, e.g. `m/44'/60'/0'`). [name] is an optional
  /// human-readable label for the online wallet to show.
  CryptoHDKey deriveAccountExport({
    required String mnemonic,
    String accountPath = defaultAccountPath,
    String? name,
  }) {
    final seed = bip39.mnemonicToSeed(_normalize(mnemonic));
    final master = bip32.BIP32.fromSeed(seed);
    final account = master.derivePath(accountPath);

    return CryptoHDKey(
      keyData: Uint8List.fromList(account.publicKey),
      chainCode: Uint8List.fromList(account.chainCode),
      useInfo: const CoinInfo(type: 60),
      origin: CryptoKeypath.parse(
        accountPath,
        sourceFingerprint: _asUint32(master.fingerprint),
        depth: account.depth,
      ),
      parentFingerprint: account.parentFingerprint,
      name: name,
    );
  }

  /// Reads a BIP-32 4-byte fingerprint as a big-endian `uint32`.
  int _asUint32(Uint8List fingerprint) =>
      fingerprint.buffer.asByteData().getUint32(0);

  String _normalize(String mnemonic) => mnemonic
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .join(' ');
}
