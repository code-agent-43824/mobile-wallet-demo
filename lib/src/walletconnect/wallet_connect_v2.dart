import 'dart:typed_data';

import 'package:web3dart/crypto.dart';

import '../transactions/transaction_service.dart';

/// Raised when a WalletConnect payload can't be parsed/serialized by the codec.
class WalletConnectCodecException implements Exception {
  const WalletConnectCodecException(this.message);

  final String message;

  @override
  String toString() => 'WalletConnectCodecException: $message';
}

/// A WalletConnect v2 JSON-RPC request. This is just the wire shape — there is
/// no relay/SDK here.
class WalletConnectRpcRequest {
  const WalletConnectRpcRequest({
    required this.chainId,
    required this.method,
    required this.params,
  });

  /// CAIP-2 chain id, e.g. `eip155:1`.
  final String chainId;

  /// JSON-RPC method, e.g. `eth_signTransaction`.
  final String method;

  /// JSON-RPC params (a single transaction object for `eth_signTransaction`).
  final List<Object?> params;
}

/// Maps the app's prepared transfer to/from the WalletConnect v2 wire format.
/// This is the WC v2 mapping contract reused by the Phase 9 wallet-side flow;
/// here it is pure serialization (no relay/SDK).
class WalletConnectV2RequestCodec {
  const WalletConnectV2RequestCodec();

  static const String signTransactionMethod = 'eth_signTransaction';

  WalletConnectRpcRequest encodeSignTransaction({
    required PreparedTransfer preparedTransfer,
    required int nonce,
    required String fromAddress,
  }) {
    final preview = preparedTransfer.preview;
    final isNative = preview.asset.kind == TransferAssetKind.native;
    final to = isNative ? preview.toAddress : preview.asset.contractAddress!;
    final value = isNative ? preparedTransfer.amountUnits : BigInt.zero;
    final data = preparedTransfer.transaction.data ?? Uint8List(0);

    final txObject = <String, Object?>{
      'from': fromAddress,
      'to': to,
      'data': bytesToHex(data, include0x: true),
      'nonce': _toHex(BigInt.from(nonce)),
      'value': _toHex(value),
      'gas': _toHex(BigInt.from(preview.gasLimit)),
      'maxFeePerGas': _toHex(preparedTransfer.maxFeePerGasWei),
      'maxPriorityFeePerGas': _toHex(preparedTransfer.maxPriorityFeePerGasWei),
    };

    return WalletConnectRpcRequest(
      chainId: 'eip155:${preparedTransfer.networkConfig.chainId}',
      method: signTransactionMethod,
      params: <Object?>[txObject],
    );
  }

  /// Decodes a wallet's `eth_signTransaction` response (a raw signed-tx hex
  /// string) into bytes the app can broadcast itself.
  Uint8List decodeSignedTransaction(String responseHex) {
    final normalized = responseHex.startsWith('0x')
        ? responseHex.substring(2)
        : responseHex;
    if (normalized.isEmpty) {
      throw const WalletConnectCodecException(
        'WalletConnect вернул пустую подпись.',
      );
    }
    return Uint8List.fromList(hexToBytes(normalized));
  }

  String _toHex(BigInt value) => '0x${value.toRadixString(16)}';
}
