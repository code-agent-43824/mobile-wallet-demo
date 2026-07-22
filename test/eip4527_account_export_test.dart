import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/airgap/account_export.dart';
import 'package:mobile_wallet_demo/src/airgap/eip4527.dart';
import 'package:mobile_wallet_demo/src/key_storage/custody_backend.dart';
import 'package:web3dart/web3dart.dart' show EthPrivateKey, bytesToHex;

// Hardhat/Anvil account #0 — the same wallet material the rest of the suite
// uses. Its mnemonic, account-level (m/44'/60'/0') export, and
// m/44'/60'/0'/0/0 address are all well-known and deterministic.
const String _mnemonic =
    'test test test test test test test test test test test junk';
const String _walletAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

// Account-level (m/44'/60'/0') values for [_mnemonic], derived independently
// with bip32/bip39 (see the offline derivation that produced these).
const String _accountPubKeyHex =
    '0206b81bac860f5a7442a85664d339809955b3ac9a5782200095127ac78aab71f5';
const String _accountChainCodeHex =
    '2258179af5cec58ce793fba06d3ef8ac640d481802e0ae39c9cc3fc5a8ce1812';
const int _masterFingerprint = 0x16a93ed0; // fingerprint of m
const int _parentFingerprint = 0x86968b77; // fingerprint of m/44'/60'

// Regression pin of OUR `crypto-hdkey` encoding for [_mnemonic] (not an
// external Keystone vector — none is published for this seed). Guards the CBOR
// key order / tag emission against silent drift.
const String _expectedUr =
    'ur:crypto-hdkey/onaxhdclaoamrocwpslnbshtjyfwpdhfieteeslanlgoqdpsnyhglf'
    'cxaemdbgknstlepyjsykaahdcxcphdchnyyktosklkvdmuzonbjnfmyapsiebtfdcsaovt'
    'plessosffhskpdtocsbgahtaadehoyadcsfnamtaaddyotadlncsdwykcsfnykaeykaocy'
    'cmptfmtiaxaxaycylnmtluktbzdsprec';

const AccountExportDeriver _deriver = AccountExportDeriver();
const Eip4527Codec _codec = Eip4527Codec();

String _hex(List<int> bytes) => bytesToHex(bytes);

void main() {
  group('account export (crypto-hdkey)', () {
    final CryptoHDKey accountExport = _deriver.deriveAccountExport(
      mnemonic: _mnemonic,
    );

    test('exports the account-level extended public key + metadata', () {
      // Public material only — never a private key.
      expect(accountExport.isPrivate, isFalse);
      expect(accountExport.isMaster, isFalse);

      expect(accountExport.keyData.length, 33);
      expect(_hex(accountExport.keyData), _accountPubKeyHex);
      expect(accountExport.chainCode, isNotNull);
      expect(accountExport.chainCode!.length, 32);
      expect(_hex(accountExport.chainCode!), _accountChainCodeHex);

      // ETH use-info (coin type 60, mainnet).
      expect(accountExport.useInfo, isNotNull);
      expect(accountExport.useInfo!.type, 60);
      expect(accountExport.useInfo!.network, 0);

      // origin = M/44'/60'/0' with the master fingerprint + depth 3.
      expect(accountExport.origin, isNotNull);
      expect(accountExport.origin!.toPathString(), "M/44'/60'/0'");
      expect(accountExport.origin!.components, <PathComponent>[
        (index: 44, hardened: true),
        (index: 60, hardened: true),
        (index: 0, hardened: true),
      ]);
      expect(accountExport.origin!.sourceFingerprint, _masterFingerprint);
      expect(accountExport.origin!.depth, 3);

      expect(accountExport.parentFingerprint, _parentFingerprint);
      // No children pattern is exported for the single-account form.
      expect(accountExport.children, isNull);
    });

    test('encodes to the expected ur:crypto-hdkey string', () {
      final ur = _codec.encodeHdKey(accountExport);
      expect(ur, startsWith('ur:crypto-hdkey/'));
      expect(ur, _expectedUr);
    });

    test('builds the identical export from hardware public data only', () {
      final hardwareExport = _deriver.deriveFromPublicAccount(
        publicAccount: WalletAccountPublicKey(
          account: const WalletAccountDescriptor(
            backendId: 'rutoken_nfc',
            address: _walletAddress,
            derivationPath: "m/44'/60'/0'/0/0",
          ),
          accountPath: "m/44'/60'/0'",
          accountDepth: 3,
          compressedPublicKey: Uint8List.fromList(accountExport.keyData),
          chainCode: Uint8List.fromList(accountExport.chainCode!),
          sourceFingerprint: _masterFingerprint,
          parentFingerprint: _parentFingerprint,
        ),
      );

      expect(_codec.encodeHdKey(hardwareExport), _expectedUr);
    });

    test('round-trips through encode/decode', () {
      final decoded = _codec.decodeHdKey(_codec.encodeHdKey(accountExport));
      expect(_hex(decoded.keyData), _accountPubKeyHex);
      expect(_hex(decoded.chainCode!), _accountChainCodeHex);
      expect(decoded.useInfo!.type, 60);
      expect(decoded.origin!.components, accountExport.origin!.components);
      expect(decoded.origin!.sourceFingerprint, _masterFingerprint);
      expect(decoded.origin!.depth, 3);
      expect(decoded.parentFingerprint, _parentFingerprint);
    });

    test(
      'MetaMask derivation M/0/0 from the exported xpub yields this wallet',
      () {
        // Reconstruct the watch-only account node from ONLY the exported public
        // key + chain code — exactly what MetaMask has after a scan.
        final accountNode = bip32.BIP32.fromPublicKey(
          accountExport.keyData,
          accountExport.chainCode!,
        );
        // MetaMask derives external addresses at M/0/i; index 0 is the wallet.
        final leafPub = accountNode.derive(0).derive(0).publicKey;

        // The same leaf via the private path must produce the same pubkey and
        // the canonical wallet address.
        final seed = bip39.mnemonicToSeed(_mnemonic);
        final leaf = bip32.BIP32.fromSeed(seed).derivePath("m/44'/60'/0'/0/0");
        expect(_hex(leafPub), _hex(leaf.publicKey));

        final address = EthPrivateKey.fromHex(
          bytesToHex(leaf.privateKey!),
        ).address.eip55With0x;
        expect(address, _walletAddress);
      },
    );

    test('decodeHdKey rejects a non-crypto-hdkey UR', () {
      // An eth-signature UR is a different type — must not decode as an hdkey.
      final wrongType = _codec.encodeSignature(
        EthSignature(
          requestId: '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
          signature: Uint8List(65),
        ),
      );
      expect(
        () => _codec.decodeHdKey(wrongType),
        throwsA(isA<Eip4527Exception>()),
      );
    });

    test('a custom account name is carried into the encoding', () {
      final named = _deriver.deriveAccountExport(
        mnemonic: _mnemonic,
        name: 'Wallet Demo',
      );
      expect(named.name, 'Wallet Demo');
      final decoded = _codec.decodeHdKey(_codec.encodeHdKey(named));
      expect(decoded.name, 'Wallet Demo');
    });
  });
}
