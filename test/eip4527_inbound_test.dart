import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/airgap/eip4527.dart';
import 'package:mobile_wallet_demo/src/airgap/eip4527_inbound.dart';
import 'package:mobile_wallet_demo/src/auth/wallet_operation_auth.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';
import 'package:mobile_wallet_demo/src/walletconnect/eip712.dart';
import 'package:web3dart/web3dart.dart'
    show
        MsgSignature,
        bytesToHex,
        bytesToInt,
        ecRecover,
        hexToBytes,
        keccak256,
        publicKeyToAddress;

// Well-known Anvil/Hardhat account #0 — same material the WC inbound tests use.
const String _walletAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
const String _privateKeyHex =
    'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

const TransactionService _txService = LocalTransactionService();
const Eip4527InboundCoordinator _coordinator = Eip4527InboundCoordinator();
const Eip712Encoder _eip712 = Eip712Encoder();

final WalletTransactionSigner _signer = LocalKeyMaterialTransactionSigner(
  backendId: 'test',
  walletMaterial: const WalletMaterial(
    address: _walletAddress,
    mnemonic: 'test',
    privateKeyHex: _privateKeyHex,
  ),
);

// 20-byte form of the wallet address (CDDL key 6).
final Uint8List _walletAddressBytes = Uint8List.fromList(
  hexToBytes(_walletAddress.substring(2)),
);

final CryptoKeypath _path = CryptoKeypath.parse("M/44'/60'/0'/0/0");

const String _requestId = '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d';

Uint8List _unhex(String hex) {
  final normalized = hex.startsWith('0x') ? hex.substring(2) : hex;
  return Uint8List.fromList(hexToBytes(normalized));
}

/// Recovers the signer address (lowercased `0x…` hex) from a 65-byte `r‖s‖v`
/// signature over [digest], where the [vForRecovery] byte is `recId + 27`. r/s
/// are read straight out of [sig]; only the v slot is overridden so that
/// re-mapped transaction signatures can be recovered too.
String _recover({
  required Uint8List digest,
  required Uint8List sig,
  required int vForRecovery,
}) {
  final r = bytesToInt(sig.sublist(0, 32));
  final s = bytesToInt(sig.sublist(32, 64));
  final pubKey = ecRecover(digest, MsgSignature(r, s, vForRecovery));
  return '0x${bytesToHex(publicKeyToAddress(pubKey))}';
}

/// EIP-191 prefixed digest, matching `signPersonalMessageToUint8List`.
Uint8List _personalDigest(Uint8List message) {
  final prefix = ascii.encode('Ethereum Signed Message:\n${message.length}');
  return Uint8List.fromList(keccak256(Uint8List.fromList(prefix + message)));
}

final Map<String, dynamic> _typedData = <String, dynamic>{
  'types': <String, dynamic>{
    'EIP712Domain': <dynamic>[
      <String, String>{'name': 'name', 'type': 'string'},
      <String, String>{'name': 'chainId', 'type': 'uint256'},
    ],
    'Msg': <dynamic>[
      <String, String>{'name': 'contents', 'type': 'string'},
    ],
  },
  'primaryType': 'Msg',
  'domain': <String, dynamic>{'name': 'Demo', 'chainId': 1},
  'message': <String, dynamic>{'contents': 'gm'},
};

// A real Keystone `ur-registry-eth` EthSignRequest legacy-tx RLP `sign-data`
// (the same vector as test/eip4527_test.dart). chain-id 1.
const String _legacyTxSignDataHex =
    'f849808609184e72a00082271094000000000000000000000000000000000000000080a47f7465737432000000000000000000000000000000000000000000000000000000600057808080';

// A minimal EIP-1559 (type-2) UNSIGNED serialization: 0x02 ‖ rlp([chainId,
// nonce, maxPriorityFee, maxFee, gasLimit, to, value, data, accessList]).
// chainId 1, nonce 0, tip 1 gwei, max 30 gwei, gas 21000, to 0x1111..1111,
// value 1 wei, empty data, empty access list. (Used only as opaque bytes to
// hash; the coordinator signs keccak256(signData) without re-parsing it.)
const String _eip1559TxSignDataHex =
    '02ef0180843b9aca0085069db9ac0082520894'
    '111111111111111111111111111111111111111101'
    '80c0';

EthSignRequest _request({
  required Uint8List signData,
  required EthSignDataType dataType,
  int chainId = 1,
  Uint8List? address,
}) {
  return EthSignRequest(
    requestId: _requestId,
    signData: signData,
    dataType: dataType,
    chainId: chainId,
    derivationPath: _path,
    address: address,
    origin: 'metamask',
  );
}

void main() {
  group('rawBytes (personal_sign / EIP-191)', () {
    test('signs the message and recovers to the wallet address', () async {
      final message = Uint8List.fromList(utf8.encode('Hello Keystone'));
      final signature = await _coordinator.signRequest(
        request: _request(
          signData: message,
          dataType: EthSignDataType.rawBytes,
          address: _walletAddressBytes,
        ),
        signer: _signer,
        transactionService: _txService,
      );

      expect(signature.signature.length, 65);
      expect(signature.requestId, _requestId);
      expect(signature.origin, 'wallet-demo');
      // personal_sign keeps v = recId + 27.
      expect(signature.signature[64], anyOf(27, 28));
      expect(
        _recover(
          digest: _personalDigest(message),
          sig: signature.signature,
          vForRecovery: signature.signature[64],
        ),
        _walletAddress.toLowerCase(),
      );
    });

    test('round-trips through encode/decode of the eth-signature UR', () async {
      final message = Uint8List.fromList(utf8.encode('Hello Keystone'));
      final ur = await _coordinator.signRequestUr(
        requestUr: const Eip4527Codec().encodeSignRequest(
          _request(
            signData: message,
            dataType: EthSignDataType.rawBytes,
            address: _walletAddressBytes,
          ),
        ),
        signer: _signer,
        transactionService: _txService,
      );

      final decoded = const Eip4527Codec().decodeSignature(ur);
      expect(decoded.signature.length, 65);
      expect(decoded.requestId, _requestId);
      expect(
        _recover(
          digest: _personalDigest(message),
          sig: decoded.signature,
          vForRecovery: decoded.signature[64],
        ),
        _walletAddress.toLowerCase(),
      );
    });
  });

  group('typedData (EIP-712)', () {
    test('signs the typed data and recovers to the wallet address', () async {
      final signData = Uint8List.fromList(utf8.encode(jsonEncode(_typedData)));
      final signature = await _coordinator.signRequest(
        request: _request(
          signData: signData,
          dataType: EthSignDataType.typedData,
          address: _walletAddressBytes,
        ),
        signer: _signer,
        transactionService: _txService,
      );

      expect(signature.signature.length, 65);
      expect(signature.signature[64], anyOf(27, 28));
      // Recovers against the EIP-712 digest (no extra prefix), v = recId + 27.
      expect(
        _recover(
          digest: _eip712.encode(_typedData),
          sig: signature.signature,
          vForRecovery: signature.signature[64],
        ),
        _walletAddress.toLowerCase(),
      );
    });
  });

  group('typedTransaction (EIP-1559 / EIP-2718)', () {
    test('signs keccak(signData); v is the y-parity (0/1)', () async {
      final signData = _unhex(_eip1559TxSignDataHex);
      final signature = await _coordinator.signRequest(
        request: _request(
          signData: signData,
          dataType: EthSignDataType.typedTransaction,
          address: _walletAddressBytes,
        ),
        signer: _signer,
        transactionService: _txService,
      );

      expect(signature.signature.length, 65);
      // EIP-1559: v is the y-parity, NOT recId+27.
      expect(signature.signature[64], anyOf(0, 1));
      // Validate via a deterministic (RFC-6979) re-sign of keccak256(signData)
      // rather than ecRecover (web3dart's ecRecover asserts on this specific
      // vector). This proves the coordinator signed keccak256(signData) — r‖s
      // match the raw signDigest of that hash — and remapped v to the y-parity
      // (raw recId = web3dart's v − 27).
      final rawHex = await _signer.signDigest(
        transactionService: _txService,
        digest: Uint8List.fromList(keccak256(signData)),
      );
      final rawNo0x = rawHex.startsWith('0x') ? rawHex.substring(2) : rawHex;
      expect(
        bytesToHex(signature.signature.sublist(0, 64)),
        rawNo0x.substring(0, 128),
      );
      expect(
        signature.signature[64],
        int.parse(rawNo0x.substring(128, 130), radix: 16) - 27,
      );
    });
  });

  group('transaction (legacy RLP)', () {
    test(
      'signs keccak(signData); v is EIP-155 (recId + chainId*2 + 35)',
      () async {
        final signData = _unhex(_legacyTxSignDataHex);
        const chainId = 1;
        final signature = await _coordinator.signRequest(
          request: _request(
            signData: signData,
            dataType: EthSignDataType.transaction,
            chainId: chainId,
            address: _walletAddressBytes,
          ),
          signer: _signer,
          transactionService: _txService,
        );

        expect(signature.signature.length, 65);
        // EIP-155 v for chainId 1 is 37 or 38.
        expect(signature.signature[64], anyOf(37, 38));
        final recId = signature.signature[64] - (chainId * 2 + 35);
        expect(recId, anyOf(0, 1));
        expect(
          _recover(
            digest: Uint8List.fromList(keccak256(signData)),
            sig: signature.signature,
            vForRecovery: recId + 27,
          ),
          _walletAddress.toLowerCase(),
        );
      },
    );
  });

  group('account targeting', () {
    test('throws when the pinned address is a different account', () async {
      final otherAddress = Uint8List.fromList(
        hexToBytes('70997970C51812dc3A010C7d01b50e0d17dc79C8'),
      );
      expect(
        () => _coordinator.signRequest(
          request: _request(
            signData: Uint8List.fromList(utf8.encode('hi')),
            dataType: EthSignDataType.rawBytes,
            address: otherAddress,
          ),
          signer: _signer,
          transactionService: _txService,
        ),
        throwsA(isA<Eip4527SignException>()),
      );
    });

    test('signs when no address is pinned', () async {
      final signature = await _coordinator.signRequest(
        request: _request(
          signData: Uint8List.fromList(utf8.encode('hi')),
          dataType: EthSignDataType.rawBytes,
          // address omitted — the derivation path is the wallet's own assertion.
        ),
        signer: _signer,
        transactionService: _txService,
      );
      expect(signature.signature.length, 65);
    });
  });
}
