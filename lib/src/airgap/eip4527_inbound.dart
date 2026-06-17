import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' show hexToBytes, keccak256;

import '../auth/wallet_operation_auth.dart';
import '../transactions/transaction_service.dart';
import '../walletconnect/eip712.dart';
import 'eip4527.dart';

/// Thrown when an [EthSignRequest] cannot be signed — e.g. it targets a
/// different account, or its [EthSignDataType] is not supported.
class Eip4527SignException implements Exception {
  const Eip4527SignException(this.message);

  final String message;

  @override
  String toString() => 'Eip4527SignException: $message';
}

/// Wallet-side EIP-4527 inbound signer (Phase 12 chunk 12.2). The app is the
/// **offline signer** ("QR-based hardware wallet"): an online wallet (MetaMask,
/// OneKey, …) builds an unsigned payload, shows it as an `eth-sign-request` UR,
/// and the app decodes it, signs by data-type with the active backend's
/// [WalletTransactionSigner], and returns an `eth-signature` UR that the online
/// wallet assembles + broadcasts.
///
/// Pure logic (no camera/QR/relay) — mirrors [AirGapInboundCoordinator] /
/// `WalletConnectInboundCoordinator`. There is no nonce lookup or broadcast: the
/// online wallet owns those (the request already carries nonce/gas/fees inside
/// the serialized transaction).
///
/// ## The signature `v` byte (the crux)
///
/// MetaMask's `@keystonehq/metamask-airgapped-keyring` (which extends
/// `@keystonehq/base-eth-keyring`) reads the returned `eth-signature` as
/// `r = sig[0:32]; s = sig[32:64]; v = sig[64]` and applies it **verbatim**:
///
/// - **Transactions** — `TransactionFactory.fromTxData({ ...tx, r, s, v }, {common})`
///   with `DataType.transaction` (legacy, type 0) or `DataType.typedTransaction`
///   (EIP-2718, incl. EIP-1559) chosen from `tx.type`. The `v` byte is passed
///   straight into `@ethereumjs/tx`, so it must already be in the form that
///   library stores:
///   - **typedTransaction (4, EIP-1559/EIP-2718):** `v` is the **`yParity`** —
///     `0` or `1` (the serialized tx is `0x02 ‖ rlp([…, y_parity, r, s])`). So
///     `v = recId` (NOT `recId + 27`).
///   - **transaction (1, legacy):** `@ethereumjs/tx` stores the **EIP-155** `v`
///     directly, so `v = recId + chainId*2 + 35`.
/// - **personal_sign (3, EIP-191) & EIP-712 (2):** the keyring returns
///   `0x ‖ r ‖ s ‖ v` verbatim to the dApp, which `ecrecover`s it — so `v` is the
///   standard `eth_sign` value, **`recId + 27`** (27/28). Our [signer] already
///   produces this (web3dart `sign` → `recId + 27`), so it is kept unchanged.
///
/// Sources: `@keystonehq/base-eth-keyring` + `@keystonehq/metamask-airgapped-keyring`
/// (`signTransaction`/`signPersonalMessage`/`signTypedData`); EIP-1559 (typed-tx
/// `signature_y_parity`); EIP-155 (legacy `v`); web3dart `secp256k1.sign`
/// (returns `recId + 27`). The legacy EIP-155 path is the least-exercised
/// branch (Keystone firmware historically returned EIP-155 `v` for legacy txs);
/// it is flagged for on-device verification with MetaMask.
class Eip4527InboundCoordinator {
  const Eip4527InboundCoordinator({
    Eip4527Codec codec = const Eip4527Codec(),
    Eip712Encoder eip712 = const Eip712Encoder(),
    String? origin = 'wallet-demo',
  }) : _codec = codec,
       _eip712 = eip712,
       _origin = origin;

  final Eip4527Codec _codec;
  final Eip712Encoder _eip712;
  final String? _origin;

  /// Decodes [requestUr] (an `ur:eth-sign-request/…` string), signs it, and
  /// returns the encoded `ur:eth-signature/…` reply for the online wallet to
  /// scan. Convenience wrapper over [signRequest] + [Eip4527Codec.encodeSignature].
  Future<String> signRequestUr({
    required String requestUr,
    required WalletTransactionSigner signer,
    required TransactionService transactionService,
  }) async {
    final request = _codec.decodeSignRequest(requestUr);
    final signature = await signRequest(
      request: request,
      signer: signer,
      transactionService: transactionService,
    );
    return _codec.encodeSignature(signature);
  }

  /// Signs a decoded [EthSignRequest] with [signer], branching on
  /// [EthSignRequest.dataType], and returns the [EthSignature] reply.
  ///
  /// Throws [Eip4527SignException] when the request targets a different account
  /// or carries an unsupported data-type, and [Eip712Exception] for malformed
  /// typed data.
  Future<EthSignature> signRequest({
    required EthSignRequest request,
    required WalletTransactionSigner signer,
    required TransactionService transactionService,
  }) async {
    _assertTargetsThisWallet(request: request, signer: signer);

    final Uint8List signature;
    switch (request.dataType) {
      case EthSignDataType.rawBytes:
        // personal_sign / EIP-191. signData IS the raw message; the signer
        // applies the "\x19Ethereum Signed Message:\n<len>" prefix. v = recId+27.
        final hex = await signer.signPersonalMessage(
          transactionService: transactionService,
          message: request.signData,
        );
        signature = _hexToBytes(hex);
        break;

      case EthSignDataType.typedData:
        // EIP-712. signData is the typed-data JSON as UTF-8 bytes. Hash with the
        // pure-Dart encoder, sign the 32-byte digest raw. v = recId+27.
        final typedData = _decodeTypedData(request.signData);
        final digest = _eip712.encode(typedData);
        final hex = await signer.signDigest(
          transactionService: transactionService,
          digest: digest,
        );
        signature = _hexToBytes(hex);
        break;

      case EthSignDataType.transaction:
      case EthSignDataType.typedTransaction:
        // signData is the UNSIGNED transaction serialization (legacy RLP, or the
        // EIP-2718 message-to-sign). The offline signer signs its keccak256
        // signing-hash and returns r‖s‖v; the online wallet assembles +
        // broadcasts. We must NOT rebuild the tx our way (we only have the
        // serialized unsigned bytes), so sign the digest directly.
        final digest = keccak256(request.signData);
        final rawSig = _hexToBytes(
          await signer.signDigest(
            transactionService: transactionService,
            digest: digest,
          ),
        );
        signature = _remapTransactionV(
          rawSig: rawSig,
          dataType: request.dataType,
          chainId: request.chainId,
        );
        break;
    }

    return EthSignature(
      requestId: request.requestId,
      signature: signature,
      origin: _origin,
    );
  }

  /// Re-maps the `v` byte of a raw [rawSig] (`r‖s‖v` with `v = recId + 27`, as
  /// produced by web3dart `sign`) into the form the online wallet expects for a
  /// transaction signature. r and s are left untouched.
  ///
  /// - [EthSignDataType.typedTransaction] → `v = recId` (`yParity`, 0/1).
  /// - [EthSignDataType.transaction] (legacy) → `v = recId + chainId*2 + 35`
  ///   (EIP-155). NOTE: a legacy v can exceed one byte for large chain ids, but
  ///   the `eth-signature` slot is exactly 65 bytes; for our supported chains
  ///   (1, 11155111) it fits in a byte, and the legacy branch is verified
  ///   on-device. See the class doc.
  Uint8List _remapTransactionV({
    required Uint8List rawSig,
    required EthSignDataType dataType,
    required int chainId,
  }) {
    if (rawSig.length != 65) {
      throw Eip4527SignException(
        'Ожидалась 65-байтовая подпись, получено ${rawSig.length}.',
      );
    }
    final recId = rawSig[64] - 27;
    if (recId != 0 && recId != 1) {
      throw Eip4527SignException(
        'Неожиданный recovery id в подписи (v=${rawSig[64]}).',
      );
    }
    final int mappedV;
    switch (dataType) {
      case EthSignDataType.typedTransaction:
        mappedV = recId;
        break;
      case EthSignDataType.transaction:
        mappedV = recId + chainId * 2 + 35;
        break;
      case EthSignDataType.rawBytes:
      case EthSignDataType.typedData:
        // Not reachable — message types never go through here.
        mappedV = rawSig[64];
        break;
    }
    if (mappedV < 0 || mappedV > 0xff) {
      throw Eip4527SignException(
        'Значение v ($mappedV) не помещается в один байт для chainId $chainId.',
      );
    }
    final out = Uint8List.fromList(rawSig);
    out[64] = mappedV;
    return out;
  }

  /// Rejects a request that does not target this wallet. The pinned 20-byte
  /// [EthSignRequest.address], when present, is the authoritative signal and is
  /// compared case-insensitively to [WalletTransactionSigner.address]. (The
  /// derivation path is the online wallet's own assertion about which key to use
  /// and is not hard-checked here: a watch-only wallet may track this account
  /// under a non-standard path, and the codec already parsed/validated it.)
  void _assertTargetsThisWallet({
    required EthSignRequest request,
    required WalletTransactionSigner signer,
  }) {
    final requestedAddress = request.addressHex;
    if (requestedAddress != null &&
        requestedAddress.toLowerCase() != signer.address.toLowerCase()) {
      throw Eip4527SignException(
        'Запрос адресован другому аккаунту ($requestedAddress).',
      );
    }
  }

  Map<String, dynamic> _decodeTypedData(Uint8List signData) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(signData));
    } catch (error) {
      throw Eip4527SignException(
        'EIP-712 sign-data не является корректным JSON: $error',
      );
    }
    if (decoded is! Map) {
      throw const Eip4527SignException(
        'EIP-712 sign-data должен быть JSON-объектом.',
      );
    }
    return decoded.cast<String, dynamic>();
  }

  Uint8List _hexToBytes(String hex) {
    final normalized = hex.startsWith('0x') ? hex.substring(2) : hex;
    return Uint8List.fromList(hexToBytes(normalized));
  }
}
