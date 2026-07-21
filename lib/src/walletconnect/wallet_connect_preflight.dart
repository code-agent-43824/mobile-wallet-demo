import 'dart:typed_data';

import '../blockchain/blockchain_provider.dart';
import '../blockchain/network_config.dart';
import 'wallet_connect_service.dart';
import 'wallet_connect_v2.dart';

class WalletConnectPreflightFailure implements Exception {
  const WalletConnectPreflightFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Immutable, request-bound data shown before vault authentication and reused
/// for signing. It prevents the confirmation UI and signer from interpreting
/// different gas/fee values for the same WalletConnect request.
class WalletConnectTransactionPreview {
  const WalletConnectTransactionPreview({
    required this.requestId,
    required this.topic,
    required this.chainId,
    required this.network,
    required this.fromAddress,
    required this.toAddress,
    required this.valueWei,
    required this.data,
    required this.gasLimit,
    required this.maxFeePerGasWei,
    required this.maxPriorityFeePerGasWei,
    required this.providerLabel,
    required this.wasSimulated,
    required this.gasWasEstimated,
    required this.feesWereEstimated,
  });

  final int requestId;
  final String topic;
  final String chainId;
  final EvmNetwork network;
  final String fromAddress;
  final String toAddress;
  final BigInt valueWei;
  final Uint8List data;
  final int gasLimit;
  final BigInt maxFeePerGasWei;
  final BigInt maxPriorityFeePerGasWei;
  final String providerLabel;
  final bool wasSimulated;
  final bool gasWasEstimated;
  final bool feesWereEstimated;

  bool get isContractCall => data.isNotEmpty;
  BigInt get maximumNetworkFeeWei => BigInt.from(gasLimit) * maxFeePerGasWei;

  String? get calldataSelector {
    if (data.length < 4) {
      return null;
    }
    final buffer = StringBuffer('0x');
    for (final byte in data.take(4)) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  bool matches(WalletConnectRequest request) =>
      request.id == requestId &&
      request.topic == topic &&
      request.chainId == chainId;
}

abstract interface class WalletConnectTransactionPreflight {
  Future<WalletConnectTransactionPreview> inspect({
    required WalletConnectRequest request,
    required String walletAddress,
  });
}

/// Deterministic fallback for pure coordinator/controller tests. Production
/// injects [PublicRpcWalletConnectTransactionPreflight]. It deliberately
/// refuses missing fields instead of recreating the removed fixed constants.
class RequestFieldsWalletConnectTransactionPreflight
    implements WalletConnectTransactionPreflight {
  const RequestFieldsWalletConnectTransactionPreflight({
    WalletConnectV2RequestCodec codec = const WalletConnectV2RequestCodec(),
  }) : _codec = codec;

  final WalletConnectV2RequestCodec _codec;

  @override
  Future<WalletConnectTransactionPreview> inspect({
    required WalletConnectRequest request,
    required String walletAddress,
  }) async {
    final decoded = _codec.decodeTransactionRequest(request.params);
    _validateAccount(decoded.fromAddress, walletAddress);
    final network = _networkForChainId(request.chainId);
    final gasLimit = decoded.gasLimit;
    final maxFee = decoded.maxFeePerGasWei;
    final priorityFee = decoded.maxPriorityFeePerGasWei;
    if (gasLimit == null || maxFee == null || priorityFee == null) {
      throw const WalletConnectPreflightFailure(
        'dApp не передал gas/fee, а live RPC preflight не подключён.',
      );
    }
    _validateFeeFields(
      gasLimit: gasLimit,
      maxFee: maxFee,
      priorityFee: priorityFee,
    );
    return WalletConnectTransactionPreview(
      requestId: request.id,
      topic: request.topic,
      chainId: request.chainId,
      network: network,
      fromAddress: decoded.fromAddress,
      toAddress: decoded.toAddress,
      valueWei: decoded.valueWei,
      data: decoded.data,
      gasLimit: gasLimit,
      maxFeePerGasWei: maxFee,
      maxPriorityFeePerGasWei: priorityFee,
      providerLabel: 'параметры dApp',
      wasSimulated: false,
      gasWasEstimated: false,
      feesWereEstimated: false,
    );
  }
}

class PublicRpcWalletConnectTransactionPreflight
    implements WalletConnectTransactionPreflight {
  PublicRpcWalletConnectTransactionPreflight({
    JsonRpcTransport? rpcTransport,
    WalletConnectV2RequestCodec codec = const WalletConnectV2RequestCodec(),
  }) : _rpcTransport = rpcTransport ?? HttpJsonRpcTransport(),
       _codec = codec;

  final JsonRpcTransport _rpcTransport;
  final WalletConnectV2RequestCodec _codec;

  @override
  Future<WalletConnectTransactionPreview> inspect({
    required WalletConnectRequest request,
    required String walletAddress,
  }) async {
    final decoded = _codec.decodeTransactionRequest(request.params);
    _validateAccount(decoded.fromAddress, walletAddress);
    final network = _networkForChainId(request.chainId);
    final config = evmNetworkConfigs[network]!;
    final failures = <String>[];

    for (final rpcUrl in config.rpcUrls) {
      final uri = Uri.parse(rpcUrl);
      try {
        final call = <String, Object?>{
          'from': decoded.fromAddress,
          'to': decoded.toAddress,
          'value': _toHex(decoded.valueWei),
          'data': _bytesToHex(decoded.data),
          if (decoded.gasLimit case final int gas)
            'gas': _toHex(BigInt.from(gas)),
        };

        // eth_call executes the exact calldata against latest state without
        // broadcasting. A revert blocks approval before any key unlock.
        await _rpcResult(
          uri: uri,
          method: 'eth_call',
          params: <Object?>[call, 'latest'],
        );

        final int gasLimit;
        final bool gasWasEstimated;
        if (decoded.gasLimit case final int suppliedGas) {
          gasLimit = suppliedGas;
          gasWasEstimated = false;
        } else {
          final rawEstimate = await _rpcResult(
            uri: uri,
            method: 'eth_estimateGas',
            params: <Object?>[call],
          );
          final estimate = _parseHexBigInt(rawEstimate, 'eth_estimateGas');
          // A small safety margin protects against state movement between the
          // simulation and inclusion while remaining visible in the preview.
          gasLimit = ((estimate * BigInt.from(120)) ~/ BigInt.from(100))
              .toInt();
          gasWasEstimated = true;
        }

        var priorityFee = decoded.maxPriorityFeePerGasWei;
        if (priorityFee == null) {
          final rawPriority = await _rpcResult(
            uri: uri,
            method: 'eth_maxPriorityFeePerGas',
            params: const <Object?>[],
          );
          priorityFee = _parseHexBigInt(
            rawPriority,
            'eth_maxPriorityFeePerGas',
          );
        }

        var maxFee = decoded.maxFeePerGasWei;
        if (maxFee == null) {
          final rawBlock = await _rpcResult(
            uri: uri,
            method: 'eth_getBlockByNumber',
            params: const <Object?>['latest', false],
          );
          if (rawBlock is! Map || rawBlock['baseFeePerGas'] is! String) {
            throw const WalletConnectPreflightFailure(
              'RPC не вернул baseFeePerGas последнего блока.',
            );
          }
          final baseFee = _parseHexBigInt(
            rawBlock['baseFeePerGas'],
            'baseFeePerGas',
          );
          maxFee = baseFee * BigInt.from(2) + priorityFee;
        }
        if (priorityFee > maxFee) {
          priorityFee = maxFee;
        }
        _validateFeeFields(
          gasLimit: gasLimit,
          maxFee: maxFee,
          priorityFee: priorityFee,
        );

        return WalletConnectTransactionPreview(
          requestId: request.id,
          topic: request.topic,
          chainId: request.chainId,
          network: network,
          fromAddress: decoded.fromAddress,
          toAddress: decoded.toAddress,
          valueWei: decoded.valueWei,
          data: decoded.data,
          gasLimit: gasLimit,
          maxFeePerGasWei: maxFee,
          maxPriorityFeePerGasWei: priorityFee,
          providerLabel: uri.host,
          wasSimulated: true,
          gasWasEstimated: gasWasEstimated,
          feesWereEstimated:
              decoded.maxFeePerGasWei == null ||
              decoded.maxPriorityFeePerGasWei == null,
        );
      } on WalletConnectPreflightFailure catch (error) {
        failures.add('${uri.host}: ${error.message}');
      } catch (error) {
        failures.add('${uri.host}: $error');
      }
    }

    throw WalletConnectPreflightFailure(
      'Не удалось безопасно проверить транзакцию через RPC: '
      '${failures.join(' | ')}',
    );
  }

  Future<Object?> _rpcResult({
    required Uri uri,
    required String method,
    required List<Object?> params,
  }) async {
    final response = await _rpcTransport.post(
      uri: uri,
      payload: <String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        'params': params,
      },
    );
    final error = response['error'];
    if (error != null) {
      final message = error is Map ? error['message'] : error;
      throw WalletConnectPreflightFailure(
        '$method отклонён: ${message ?? 'неизвестная RPC-ошибка'}',
      );
    }
    if (!response.containsKey('result')) {
      throw WalletConnectPreflightFailure('$method вернул ответ без result.');
    }
    return response['result'];
  }
}

EvmNetwork _networkForChainId(String chainId) {
  final parts = chainId.split(':');
  final raw = parts.length == 2 ? parts.last : chainId;
  final id = int.tryParse(raw);
  if (id != null) {
    for (final entry in evmNetworkConfigs.entries) {
      if (entry.value.chainId == id) {
        return entry.key;
      }
    }
  }
  throw WalletConnectPreflightFailure('Сеть $chainId не поддерживается.');
}

void _validateAccount(String requested, String active) {
  if (requested.toLowerCase() != active.toLowerCase()) {
    throw WalletConnectPreflightFailure(
      'Запрос адресован другому аккаунту ($requested).',
    );
  }
}

void _validateFeeFields({
  required int gasLimit,
  required BigInt maxFee,
  required BigInt priorityFee,
}) {
  if (gasLimit <= 0) {
    throw const WalletConnectPreflightFailure(
      'Gas limit должен быть больше 0.',
    );
  }
  if (maxFee < BigInt.zero || priorityFee < BigInt.zero) {
    throw const WalletConnectPreflightFailure(
      'Gas fee не может быть отрицательной.',
    );
  }
  if (priorityFee > maxFee) {
    throw const WalletConnectPreflightFailure(
      'maxPriorityFeePerGas превышает maxFeePerGas.',
    );
  }
}

BigInt _parseHexBigInt(Object? value, String field) {
  if (value is! String || !value.startsWith('0x')) {
    throw WalletConnectPreflightFailure(
      '$field вернул некорректное hex-значение.',
    );
  }
  final parsed = BigInt.tryParse(value.substring(2), radix: 16);
  if (parsed == null) {
    throw WalletConnectPreflightFailure(
      '$field вернул некорректное hex-значение.',
    );
  }
  return parsed;
}

String _toHex(BigInt value) => '0x${value.toRadixString(16)}';

String _bytesToHex(Uint8List value) {
  final buffer = StringBuffer('0x');
  for (final byte in value) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
