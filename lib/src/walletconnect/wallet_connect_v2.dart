import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' show bytesToHex, hexToBytes;

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

/// A decoded incoming `eth_sendTransaction` / `eth_signTransaction` request —
/// the inverse of [WalletConnectV2RequestCodec.encodeSignTransaction]. Optional
/// fields (nonce/gas/fees) are null when the dApp didn't supply them; the wallet
/// fills them in before signing.
class WalletConnectTransactionRequest {
  const WalletConnectTransactionRequest({
    required this.fromAddress,
    required this.toAddress,
    required this.valueWei,
    required this.data,
    this.nonce,
    this.gasLimit,
    this.maxFeePerGasWei,
    this.maxPriorityFeePerGasWei,
  });

  final String fromAddress;
  final String toAddress;
  final BigInt valueWei;
  final Uint8List data;
  final int? nonce;
  final int? gasLimit;
  final BigInt? maxFeePerGasWei;
  final BigInt? maxPriorityFeePerGasWei;
}

/// A decoded `personal_sign` / `eth_sign` request: which account should sign,
/// the raw message bytes to sign (the EIP-191 prefix is added by the signer),
/// and a best-effort human-readable rendering for the approval UI.
class WalletConnectMessageRequest {
  const WalletConnectMessageRequest({
    required this.address,
    required this.message,
    required this.displayText,
  });

  final String address;
  final Uint8List message;
  final String displayText;
}

/// Maps the app's prepared transfer to/from the WalletConnect v2 wire format.
/// This is the WC v2 mapping contract reused by the Phase 9 wallet-side flow;
/// here it is pure serialization (no relay/SDK).
class WalletConnectV2RequestCodec {
  const WalletConnectV2RequestCodec();

  static const String signTransactionMethod = 'eth_signTransaction';
  static const String sendTransactionMethod = 'eth_sendTransaction';
  static const String personalSignMethod = 'personal_sign';
  static const String ethSignMethod = 'eth_sign';

  /// Whether [method] is a transaction request this codec can decode.
  bool isTransactionMethod(String method) =>
      method == signTransactionMethod || method == sendTransactionMethod;

  /// Whether [method] is an EIP-191 message-signing request.
  bool isMessageSignMethod(String method) =>
      method == personalSignMethod || method == ethSignMethod;

  /// Decodes a `personal_sign` (`[message, address]`) or `eth_sign`
  /// (`[address, message]`) request. The message param is hex (`0x…`) bytes or
  /// a plain UTF-8 string.
  WalletConnectMessageRequest decodeMessageRequest(
    String method,
    List<Object?> params,
  ) {
    if (params.length < 2) {
      throw const WalletConnectCodecException(
        'Запрос на подпись сообщения должен содержать сообщение и адрес.',
      );
    }
    final Object? messageParam;
    final Object? addressParam;
    if (method == personalSignMethod) {
      messageParam = params[0];
      addressParam = params[1];
    } else {
      addressParam = params[0];
      messageParam = params[1];
    }
    if (addressParam is! String || addressParam.isEmpty) {
      throw const WalletConnectCodecException(
        'В запросе на подпись отсутствует адрес.',
      );
    }
    if (messageParam is! String) {
      throw const WalletConnectCodecException(
        'В запросе на подпись отсутствует сообщение.',
      );
    }
    final bytes = _messageBytes(messageParam);
    return WalletConnectMessageRequest(
      address: addressParam,
      message: bytes,
      displayText: _messageDisplay(messageParam, bytes),
    );
  }

  Uint8List _messageBytes(String message) {
    if (message.startsWith('0x')) {
      final hex = message.substring(2);
      return hex.isEmpty ? Uint8List(0) : Uint8List.fromList(hexToBytes(hex));
    }
    return Uint8List.fromList(utf8.encode(message));
  }

  String _messageDisplay(String raw, Uint8List bytes) {
    if (!raw.startsWith('0x')) {
      return raw;
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return raw; // non-UTF8 payload: show the hex
    }
  }

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

  /// Decodes the transaction object from an incoming `eth_sendTransaction` /
  /// `eth_signTransaction` request's [params] (the first element is the tx
  /// object). Inverse of [encodeSignTransaction].
  WalletConnectTransactionRequest decodeTransactionRequest(
    List<Object?> params,
  ) {
    if (params.isEmpty || params.first is! Map) {
      throw const WalletConnectCodecException(
        'WalletConnect-запрос не содержит объект транзакции.',
      );
    }
    final tx = (params.first as Map).cast<String, Object?>();
    final from = tx['from'] as String?;
    final to = tx['to'] as String?;
    if (from == null || from.isEmpty) {
      throw const WalletConnectCodecException(
        'В транзакции отсутствует поле from.',
      );
    }
    if (to == null || to.isEmpty) {
      throw const WalletConnectCodecException(
        'В транзакции отсутствует поле to.',
      );
    }
    return WalletConnectTransactionRequest(
      fromAddress: from,
      toAddress: to,
      valueWei: _hexToBigInt(tx['value']) ?? BigInt.zero,
      data: _hexToBytes(tx['data']),
      nonce: _hexToInt(tx['nonce']),
      gasLimit: _hexToInt(tx['gas']),
      maxFeePerGasWei: _hexToBigInt(tx['maxFeePerGas']),
      maxPriorityFeePerGasWei: _hexToBigInt(tx['maxPriorityFeePerGas']),
    );
  }

  BigInt? _hexToBigInt(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    final normalized = value.startsWith('0x') ? value.substring(2) : value;
    if (normalized.isEmpty) {
      return null;
    }
    return BigInt.tryParse(normalized, radix: 16);
  }

  int? _hexToInt(Object? value) => _hexToBigInt(value)?.toInt();

  Uint8List _hexToBytes(Object? value) {
    if (value is! String) {
      return Uint8List(0);
    }
    final normalized = value.startsWith('0x') ? value.substring(2) : value;
    if (normalized.isEmpty) {
      return Uint8List(0);
    }
    return Uint8List.fromList(hexToBytes(normalized));
  }

  String _toHex(BigInt value) => '0x${value.toRadixString(16)}';
}
