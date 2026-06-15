import 'dart:typed_data';

import 'package:web3dart/crypto.dart';

import '../auth/wallet_operation_auth.dart';
import '../blockchain/network_config.dart';
import '../transactions/transaction_service.dart';
import 'airgap_signing.dart';

/// Wallet-side AirGap inbound (Phase 9 chunk 9.5): decode an offline
/// `airgap-tx:` request payload → build a [PreparedTransfer] → sign with the
/// active account → encode the `airgap-sig:` response payload the online device
/// scans back. Pure logic (no camera/QR); the screen layer handles paste/scan.
/// Offline by definition: the request carries the nonce/gas/fees, so there is no
/// nonce lookup or broadcast here — the online side broadcasts the response.
class AirGapInboundCoordinator {
  const AirGapInboundCoordinator({
    AirGapPayloadCodec codec = const AirGapPayloadCodec(),
  }) : _codec = codec;

  final AirGapPayloadCodec _codec;

  /// Decodes [requestPayload], signs it with [signer], and returns the encoded
  /// `airgap-sig:` response payload. Throws [AirGapPayloadException] for a
  /// malformed payload, an unsupported chain, or a wrong-account request.
  Future<String> signRequestPayload({
    required String requestPayload,
    required TransactionService transactionService,
    required WalletTransactionSigner signer,
  }) async {
    final request = _codec.decodeRequest(requestPayload);

    final network = _networkForChainId(request.chainId);
    if (network == null) {
      throw AirGapPayloadException(
        'Сеть ${request.chainId} не поддерживается.',
      );
    }

    if (request.fromAddress.toLowerCase() != signer.address.toLowerCase()) {
      throw AirGapPayloadException(
        'Запрос адресован другому аккаунту (${request.fromAddress}).',
      );
    }

    final prepared = transactionService.prepareInboundTransaction(
      network: network,
      fromAddress: signer.address,
      toAddress: request.toAddress,
      valueWei: _hexToBigInt(request.valueWeiHex),
      data: _hexToBytes(request.dataHex),
      gasLimit: request.gasLimit,
      maxFeePerGasWei: _hexToBigInt(request.maxFeePerGasWeiHex),
      maxPriorityFeePerGasWei: _hexToBigInt(request.maxPriorityFeePerGasWeiHex),
    );

    final signed = await signer.signPreparedTransfer(
      transactionService: transactionService,
      preparedTransfer: prepared,
      nonce: request.nonce,
    );

    return _codec.encodeResponse(
      AirGapSignedResponse(
        requestId: request.requestId,
        rawSignedTransactionHex: signed.rawTransactionHex,
      ),
    );
  }

  /// Maps a CAIP-2 chain id (e.g. `eip155:1`) to a supported [EvmNetwork], or
  /// null when the chain is not configured.
  EvmNetwork? _networkForChainId(String chainId) {
    final parts = chainId.split(':');
    final raw = parts.length == 2 ? parts.last : chainId;
    final id = int.tryParse(raw);
    if (id == null) {
      return null;
    }
    for (final entry in evmNetworkConfigs.entries) {
      if (entry.value.chainId == id) {
        return entry.key;
      }
    }
    return null;
  }

  BigInt _hexToBigInt(String hex) {
    final normalized = hex.startsWith('0x') ? hex.substring(2) : hex;
    return normalized.isEmpty
        ? BigInt.zero
        : BigInt.parse(normalized, radix: 16);
  }

  Uint8List _hexToBytes(String hex) {
    final normalized = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (normalized.isEmpty) {
      return Uint8List(0);
    }
    return Uint8List.fromList(hexToBytes(normalized));
  }
}
