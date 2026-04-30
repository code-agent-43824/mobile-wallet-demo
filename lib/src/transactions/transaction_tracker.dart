import 'dart:async';

import '../blockchain/blockchain_provider.dart';
import '../blockchain/network_config.dart';

enum TransactionStatus { pending, confirmed, reverted, failed }

class TransactionReceipt {
  const TransactionReceipt({
    required this.status,
    this.blockNumber,
    this.gasUsed,
    this.errorMessage,
  });

  final TransactionStatus status;
  final int? blockNumber;
  final BigInt? gasUsed;
  final String? errorMessage;
}

class TransactionTracker {
  TransactionTracker({
    required this.rpcTransport,
    this.pollInterval = const Duration(seconds: 5),
    this.maxAttempts = 60, // ~5 minutes default
  });

  final JsonRpcTransport rpcTransport;
  final Duration pollInterval;
  final int maxAttempts;

  Future<TransactionReceipt> waitForReceipt({
    required EvmNetworkConfig networkConfig,
    required String transactionHash,
  }) async {
    int attempts = 0;

    while (attempts < maxAttempts) {
      for (final rpcUrl in networkConfig.rpcUrls) {
        final uri = Uri.parse(rpcUrl);
        try {
          final response = await rpcTransport.post(
            uri: uri,
            payload: <String, dynamic>{
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'eth_getTransactionReceipt',
              'params': <dynamic>[transactionHash],
            },
          );

          final error = response['error'];
          if (error != null) {
            continue; // Try next RPC
          }

          final result = response['result'] as Map<String, dynamic>?;
          if (result == null) {
            continue; // Not found yet, continue polling
          }

          final statusHex = result['status'] as String?;
          final status = (statusHex == '0x1')
              ? TransactionStatus.confirmed
              : TransactionStatus.reverted;

          return TransactionReceipt(
            status: status,
            blockNumber: _parseHexInt(result['blockNumber'] as String?),
            gasUsed: _parseHexBigInt(result['gasUsed'] as String?),
          );
        } catch (_) {
          continue; // RPC error, try next
        }
      }

      attempts++;
      await Future<void>.delayed(pollInterval);
    }

    return const TransactionReceipt(
      status: TransactionStatus.pending,
      errorMessage: 'Tracking timeout: transaction still pending or not found.',
    );
  }

  int? _parseHexInt(String? hex) {
    if (hex == null) return null;
    return int.tryParse(hex.replaceFirst('0x', ''), radix: 16);
  }

  BigInt? _parseHexBigInt(String? hex) {
    if (hex == null) return null;
    return BigInt.tryParse(hex.replaceFirst('0x', ''), radix: 16);
  }
}
