import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' show bytesToHex, hexToBytes;

import '../transactions/transaction_service.dart';
import '../errors/app_error.dart';

/// Raised when a WalletConnect payload can't be parsed/serialized by the codec.
class WalletConnectCodecException implements Exception, CodedError {
  /// A failure whose text comes from outside the app; shown as is.
  const WalletConnectCodecException(String message)
    : _message = message,
      errorCode = null,
      errorArgs = const <String, Object>{};

  const WalletConnectCodecException.coded(
    AppErrorCode this.errorCode, [
    this.errorArgs = const <String, Object>{},
  ]) : _message = null;

  final String? _message;

  @override
  final AppErrorCode? errorCode;

  @override
  final Map<String, Object> errorArgs;

  @override
  String get message => _message ?? debugDescribeError(errorCode!, errorArgs);

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

/// A decoded `eth_signTypedData_v4` / `_v3` request: which account should sign
/// and the parsed EIP-712 typed-data object ({types, primaryType, domain,
/// message}). The EIP-712 hashing lives in `eip712.dart`.
class WalletConnectTypedDataRequest {
  const WalletConnectTypedDataRequest({
    required this.address,
    required this.typedData,
  });

  final String address;
  final Map<String, dynamic> typedData;
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
  static const String signTypedDataV4Method = 'eth_signTypedData_v4';
  static const String signTypedDataV3Method = 'eth_signTypedData_v3';

  /// Unversioned name many dApps (and WalletConnect's default namespaces)
  /// still request; it carries the same `[address, typedData]` as v4.
  static const String signTypedDataMethod = 'eth_signTypedData';
  static const String switchEthereumChainMethod = 'wallet_switchEthereumChain';
  static const String getCapabilitiesMethod = 'wallet_getCapabilities';

  static const Set<String> supportedMethods = <String>{
    signTransactionMethod,
    sendTransactionMethod,
    personalSignMethod,
    ethSignMethod,
    signTypedDataV4Method,
    signTypedDataV3Method,
    signTypedDataMethod,
    switchEthereumChainMethod,
    getCapabilitiesMethod,
  };

  /// Whether [method] is a transaction request this codec can decode.
  bool isTransactionMethod(String method) =>
      method == signTransactionMethod || method == sendTransactionMethod;

  /// Whether [method] is an EIP-191 message-signing request.
  bool isMessageSignMethod(String method) =>
      method == personalSignMethod || method == ethSignMethod;

  /// Whether [method] is an EIP-712 typed-data request (v3/v4 JSON shape).
  bool isTypedDataMethod(String method) =>
      method == signTypedDataV4Method ||
      method == signTypedDataV3Method ||
      method == signTypedDataMethod;

  /// Whether [method] changes dApp chain context without accessing a key.
  bool isChainSwitchMethod(String method) =>
      method == switchEthereumChainMethod;

  /// Whether [method] is the read-only EIP-5792 capability query.
  bool isCapabilitiesMethod(String method) => method == getCapabilitiesMethod;

  /// Decodes EIP-5792 `[address, [chainIds]?]`. Chain ids stay as canonical
  /// hex strings because that is also how the response object is keyed.
  ({String address, List<String>? chainIds}) decodeGetCapabilities(
    List<Object?> params,
  ) {
    if (params.isEmpty || params.first is! String) {
      throw const WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{
          'detail': 'wallet_getCapabilities needs the wallet address',
        },
      );
    }
    final address = params.first! as String;
    List<String>? chainIds;
    if (params.length > 1 && params[1] != null) {
      final rawChains = params[1];
      if (rawChains is! List || rawChains.any((value) => value is! String)) {
        throw const WalletConnectCodecException.coded(
          AppErrorCode.wcMalformedRequest,
          <String, Object>{
            'detail': 'wallet_getCapabilities needs an array of chain ids',
          },
        );
      }
      chainIds = rawChains.cast<String>();
    }
    return (address: address, chainIds: chainIds);
  }

  /// Decodes EIP-3326 / EIP-1193 `[{chainId: "0x..."}]` parameters.
  int decodeSwitchEthereumChainId(List<Object?> params) {
    if (params.isEmpty || params.first is! Map) {
      throw const WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{
          'detail': 'wallet_switchEthereumChain needs an object with chainId',
        },
      );
    }
    final raw = (params.first as Map)['chainId'];
    if (raw is! String || raw.isEmpty) {
      throw const WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{'detail': 'wallet_switchEthereumChain has no chainId'},
      );
    }
    final normalized = raw.toLowerCase().startsWith('0x')
        ? raw.substring(2)
        : raw;
    final chainId = int.tryParse(
      normalized,
      radix: raw.toLowerCase().startsWith('0x') ? 16 : 10,
    );
    if (chainId == null) {
      throw WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{
          'detail': 'invalid chainId in wallet_switchEthereumChain: $raw',
        },
      );
    }
    return chainId;
  }

  /// Decodes an `eth_signTypedData` / `_v3` / `_v4` request
  /// (`[address, typedData]`), where `typedData` is the EIP-712 object as a
  /// JSON string or a Map. Some dApps send the pair reversed; the address is
  /// recognised by its shape. The legacy v1 form (an array of typed fields)
  /// is not EIP-712 and is refused.
  WalletConnectTypedDataRequest decodeTypedDataRequest(List<Object?> params) {
    if (params.length < 2) {
      throw const WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{
          'detail': 'eth_signTypedData needs [address, typedData]',
        },
      );
    }
    if (params[0] is List || params[1] is List) {
      throw const WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{
          'detail':
              'legacy eth_signTypedData v1 (an array of fields) is not '
              'supported; use EIP-712 typed data',
        },
      );
    }
    final reversed =
        !_isEvmAddress(params[0]) &&
        _isEvmAddress(params[1]) &&
        _isTypedDataObject(params[0]);
    final address = reversed ? params[1] : params[0];
    if (address is! String || address.isEmpty) {
      throw const WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{'detail': 'typed data request has no address'},
      );
    }
    final raw = reversed ? params[0] : params[1];
    final Map<String, dynamic> typedData;
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const WalletConnectCodecException.coded(
          AppErrorCode.wcMalformedRequest,
          <String, Object>{'detail': 'typed data must be a JSON object'},
        );
      }
      typedData = decoded.cast<String, dynamic>();
    } else if (raw is Map) {
      typedData = raw.cast<String, dynamic>();
    } else {
      throw const WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{
          'detail': 'typed data must be a JSON object or string',
        },
      );
    }
    return WalletConnectTypedDataRequest(
      address: address,
      typedData: typedData,
    );
  }

  static final RegExp _evmAddressPattern = RegExp(r'^0x[0-9a-fA-F]{40}$');

  static bool _isEvmAddress(Object? value) =>
      value is String && _evmAddressPattern.hasMatch(value);

  static bool _isTypedDataObject(Object? value) =>
      value is Map || (value is String && value.trimLeft().startsWith('{'));

  /// Decodes a `personal_sign` (`[message, address]`) or `eth_sign`
  /// (`[address, message]`) request. The message param is hex (`0x…`) bytes or
  /// a plain UTF-8 string.
  WalletConnectMessageRequest decodeMessageRequest(
    String method,
    List<Object?> params,
  ) {
    if (params.length < 2) {
      throw const WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{
          'detail': 'message signing needs a message and an address',
        },
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
      throw const WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{'detail': 'signing request has no address'},
      );
    }
    if (messageParam is! String) {
      throw const WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{'detail': 'signing request has no message'},
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
      throw const WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{'detail': 'empty signature'},
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
      throw const WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{'detail': 'request has no transaction object'},
      );
    }
    final tx = (params.first as Map).cast<String, Object?>();
    final from = tx['from'] as String?;
    final to = tx['to'] as String?;
    if (from == null || from.isEmpty) {
      throw const WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{'detail': 'transaction has no from field'},
      );
    }
    if (to == null || to.isEmpty) {
      throw const WalletConnectCodecException.coded(
        AppErrorCode.wcMalformedRequest,
        <String, Object>{'detail': 'transaction has no to field'},
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
