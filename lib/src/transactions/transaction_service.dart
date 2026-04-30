import 'dart:typed_data';

import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' hide TransactionReceipt;

import '../blockchain/blockchain_provider.dart';
import '../blockchain/network_config.dart';
import '../key_storage/key_storage_backend.dart';
import 'transaction_tracker.dart';

class TransactionFailure implements Exception {
  const TransactionFailure(this.message);

  final String message;

  @override
  String toString() => 'TransactionFailure: $message';
}

enum TransferAssetKind { native, erc20 }

class TransferAssetOption {
  const TransferAssetOption({
    required this.kind,
    required this.symbol,
    required this.name,
    required this.balanceFormatted,
    required this.balanceRaw,
    required this.decimals,
    this.contractAddress,
  });

  final TransferAssetKind kind;
  final String symbol;
  final String name;
  final String balanceFormatted;
  final BigInt balanceRaw;
  final int decimals;
  final String? contractAddress;

  String get id => contractAddress ?? 'native:$symbol';
}

class TransferPreview {
  const TransferPreview({
    required this.network,
    required this.fromAddress,
    required this.toAddress,
    required this.asset,
    required this.amountFormatted,
    required this.gasLimit,
    required this.maxFeePerGasGwei,
    required this.estimatedNetworkFeeNativeFormatted,
    required this.totalDebitFormatted,
    required this.previewNote,
  });

  final EvmNetwork network;
  final String fromAddress;
  final String toAddress;
  final TransferAssetOption asset;
  final String amountFormatted;
  final int gasLimit;
  final double maxFeePerGasGwei;
  final String estimatedNetworkFeeNativeFormatted;
  final String totalDebitFormatted;
  final String previewNote;
}

class PreparedTransfer {
  const PreparedTransfer({
    required this.preview,
    required this.networkConfig,
    required this.amountUnits,
    required this.maxFeePerGasWei,
    required this.maxPriorityFeePerGasWei,
    required this.estimatedFeeWei,
    required this.transaction,
  });

  final TransferPreview preview;
  final EvmNetworkConfig networkConfig;
  final BigInt amountUnits;
  final BigInt maxFeePerGasWei;
  final BigInt maxPriorityFeePerGasWei;
  final BigInt estimatedFeeWei;
  final Transaction transaction;
}

class SignedTransfer {
  const SignedTransfer({
    required this.preview,
    required this.networkConfig,
    required this.rawTransactionBytes,
    required this.rawTransactionHex,
    required this.transactionHashHex,
    required this.signingNote,
  });

  final TransferPreview preview;
  final EvmNetworkConfig networkConfig;
  final Uint8List rawTransactionBytes;
  final String rawTransactionHex;
  final String transactionHashHex;
  final String signingNote;
}

class SubmittedTransfer {
  const SubmittedTransfer({
    required this.signedTransfer,
    required this.providerLabel,
    required this.networkTransactionHash,
    required this.submittedAtUtc,
  });

  final SignedTransfer signedTransfer;
  final String providerLabel;
  final String networkTransactionHash;
  final DateTime submittedAtUtc;
}

class LoadedNonce {
  const LoadedNonce({
    required this.network,
    required this.address,
    required this.nonce,
    required this.providerLabel,
    required this.loadedAtUtc,
  });

  final EvmNetwork network;
  final String address;
  final int nonce;
  final String providerLabel;
  final DateTime loadedAtUtc;
}

abstract interface class NonceProvider {
  Future<LoadedNonce> loadNextNonce({
    required EvmNetworkConfig networkConfig,
    required String address,
  });
}

abstract interface class TransactionBroadcaster {
  Future<SubmittedTransfer> submit({required SignedTransfer signedTransfer});
}

abstract interface class TransactionService {
  List<TransferAssetOption> availableAssets({
    required WalletChainSnapshot snapshot,
    required EvmNetworkConfig networkConfig,
  });

  TransferPreview preparePreview({
    required WalletChainSnapshot snapshot,
    required String fromAddress,
    required String toAddress,
    required String amountText,
    required TransferAssetOption asset,
  });

  PreparedTransfer prepareTransfer({
    required WalletChainSnapshot snapshot,
    required String fromAddress,
    required String toAddress,
    required String amountText,
    required TransferAssetOption asset,
  });

  SignedTransfer signPreparedTransfer({
    required PreparedTransfer preparedTransfer,
    required WalletMaterial walletMaterial,
    required int nonce,
  });

  Future<SubmittedTransfer> submitSignedTransfer({
    required SignedTransfer signedTransfer,
    required TransactionBroadcaster broadcaster,
  }) {
    throw UnimplementedError('ReadOnlyTransactionService does not support submission');
  }

  Future<TransactionReceipt> trackTransaction({
    required SubmittedTransfer submittedTransfer,
    required JsonRpcTransport rpcTransport,
  }) {
    throw UnimplementedError('ReadOnlyTransactionService does not support tracking');
  }
}

class ReadOnlyTransactionService implements TransactionService {
  const ReadOnlyTransactionService();

  static const double _fallbackBaseFeeGwei = 1.0;
  static const double _priorityFeeGwei = 1.5;
  static const int _nativeTransferGasLimit = 21000;
  static const int _erc20TransferGasLimit = 65000;

  @override
  List<TransferAssetOption> availableAssets({
    required WalletChainSnapshot snapshot,
    required EvmNetworkConfig networkConfig,
  }) {
    return <TransferAssetOption>[
      TransferAssetOption(
        kind: TransferAssetKind.native,
        symbol: networkConfig.nativeSymbol,
        name: networkConfig.name,
        balanceFormatted: snapshot.nativeBalanceFormatted,
        balanceRaw: snapshot.nativeBalanceWei,
        decimals: 18,
      ),
      ...snapshot.tokenBalances.map(
        (token) => TransferAssetOption(
          kind: TransferAssetKind.erc20,
          symbol: token.symbol,
          name: token.name,
          balanceFormatted: token.balanceFormatted,
          balanceRaw: token.rawBalance,
          decimals: token.decimals,
          contractAddress: token.contractAddress,
        ),
      ),
    ];
  }

  @override
  TransferPreview preparePreview({
    required WalletChainSnapshot snapshot,
    required String fromAddress,
    required String toAddress,
    required String amountText,
    required TransferAssetOption asset,
  }) {
    return prepareTransfer(
      snapshot: snapshot,
      fromAddress: fromAddress,
      toAddress: toAddress,
      amountText: amountText,
      asset: asset,
    ).preview;
  }

  @override
  PreparedTransfer prepareTransfer({
    required WalletChainSnapshot snapshot,
    required String fromAddress,
    required String toAddress,
    required String amountText,
    required TransferAssetOption asset,
  }) {
    final normalizedTarget = toAddress.trim();
    if (!_isValidEvmAddress(normalizedTarget)) {
      throw const TransactionFailure(
        'Введите корректный EVM-адрес получателя.',
      );
    }

    final amountUnits = _parseDecimalToUnits(
      text: amountText,
      decimals: asset.decimals,
    );
    if (amountUnits <= BigInt.zero) {
      throw const TransactionFailure('Сумма должна быть больше нуля.');
    }
    if (amountUnits > asset.balanceRaw) {
      throw TransactionFailure('Недостаточно ${asset.symbol} для такой суммы.');
    }

    final gasLimit = asset.kind == TransferAssetKind.native
        ? _nativeTransferGasLimit
        : _erc20TransferGasLimit;
    final maxPriorityFeePerGasWei = BigInt.from(1500000000);
    final maxFeePerGasGwei =
        (snapshot.baseFeeGwei ?? _fallbackBaseFeeGwei) + _priorityFeeGwei;
    final maxFeePerGasWei = BigInt.from(
      (maxFeePerGasGwei * 1000000000).round(),
    );
    final feeWei = maxFeePerGasWei * BigInt.from(gasLimit);

    if (asset.kind == TransferAssetKind.native &&
        amountUnits + feeWei > snapshot.nativeBalanceWei) {
      throw const TransactionFailure(
        'Недостаточно нативного баланса для суммы и estimated network fee.',
      );
    }

    if (asset.kind == TransferAssetKind.erc20 &&
        feeWei > snapshot.nativeBalanceWei) {
      throw const TransactionFailure(
        'Недостаточно нативного баланса для оплаты network fee.',
      );
    }

    final amountFormatted = _formatUnits(amountUnits, asset.decimals);
    final estimatedFeeFormatted = _formatUnits(feeWei, 18);
    final networkConfig = evmNetworkConfigs[snapshot.network]!;
    final totalDebitFormatted = asset.kind == TransferAssetKind.native
        ? '${_formatUnits(amountUnits + feeWei, 18)} ${asset.symbol}'
        : '$amountFormatted ${asset.symbol} + $estimatedFeeFormatted ${networkConfig.nativeSymbol} fee';

    final preview = TransferPreview(
      network: snapshot.network,
      fromAddress: fromAddress,
      toAddress: normalizedTarget,
      asset: asset,
      amountFormatted: '$amountFormatted ${asset.symbol}',
      gasLimit: gasLimit,
      maxFeePerGasGwei: maxFeePerGasGwei,
      estimatedNetworkFeeNativeFormatted:
          '$estimatedFeeFormatted ${networkConfig.nativeSymbol}',
      totalDebitFormatted: totalDebitFormatted,
      previewNote:
          'Это только preparation/preview. Подпись и отправка ещё не включены.',
    );

    return PreparedTransfer(
      preview: preview,
      networkConfig: networkConfig,
      amountUnits: amountUnits,
      maxFeePerGasWei: maxFeePerGasWei,
      maxPriorityFeePerGasWei: maxPriorityFeePerGasWei,
      estimatedFeeWei: feeWei,
      transaction: _buildTransaction(
        preview: preview,
        amountUnits: amountUnits,
        maxFeePerGasWei: maxFeePerGasWei,
        maxPriorityFeePerGasWei: maxPriorityFeePerGasWei,
      ),
    );
  }

  @override
  SignedTransfer signPreparedTransfer({
    required PreparedTransfer preparedTransfer,
    required WalletMaterial walletMaterial,
    required int nonce,
  }) {
    if (nonce < 0) {
      throw const TransactionFailure('Nonce должен быть неотрицательным.');
    }

    if (walletMaterial.address.toLowerCase() !=
        preparedTransfer.preview.fromAddress.toLowerCase()) {
      throw const TransactionFailure(
        'Материал кошелька не соответствует адресу отправителя.',
      );
    }

    final credentials = EthPrivateKey.fromHex(walletMaterial.privateKeyHex);
    final unsigned = preparedTransfer.transaction.copyWith(
      from: EthereumAddress.fromHex(preparedTransfer.preview.fromAddress),
      nonce: nonce,
    );

    var signedBytes = signTransactionRaw(
      unsigned,
      credentials,
      chainId: preparedTransfer.networkConfig.chainId,
    );
    if (unsigned.isEIP1559) {
      signedBytes = prependTransactionType(0x02, signedBytes);
    }

    final rawTransactionHex = bytesToHex(signedBytes, include0x: true);
    final transactionHashHex = bytesToHex(
      keccak256(signedBytes),
      include0x: true,
    );

    return SignedTransfer(
      preview: preparedTransfer.preview,
      networkConfig: preparedTransfer.networkConfig,
      rawTransactionBytes: signedBytes,
      rawTransactionHex: rawTransactionHex,
      transactionHashHex: transactionHashHex,
      signingNote:
          'Транзакция локально подписана. Для этой операции PIN нужен только один раз на весь high-level signing flow.',
    );
  }

  @override
  Future<SubmittedTransfer> submitSignedTransfer({
    required SignedTransfer signedTransfer,
    required TransactionBroadcaster broadcaster,
  }) {
    return broadcaster.submit(signedTransfer: signedTransfer);
  }

  @override
  Future<TransactionReceipt> trackTransaction({
    required SubmittedTransfer submittedTransfer,
    required JsonRpcTransport rpcTransport,
  }) {
    final tracker = TransactionTracker(rpcTransport: rpcTransport);
    return tracker.waitForReceipt(
      networkConfig: submittedTransfer.signedTransfer.networkConfig,
      transactionHash: submittedTransfer.networkTransactionHash,
    );
  }

  Transaction _buildTransaction({
    required TransferPreview preview,
    required BigInt amountUnits,
    required BigInt maxFeePerGasWei,
    required BigInt maxPriorityFeePerGasWei,
  }) {
    final to = EthereumAddress.fromHex(preview.toAddress);
    final isNative = preview.asset.kind == TransferAssetKind.native;

    return Transaction(
      to: isNative
          ? to
          : EthereumAddress.fromHex(preview.asset.contractAddress!),
      maxGas: preview.gasLimit,
      value: isNative ? EtherAmount.inWei(amountUnits) : EtherAmount.zero(),
      data: isNative
          ? Uint8List(0)
          : _buildErc20TransferData(recipient: to, amountUnits: amountUnits),
      maxFeePerGas: EtherAmount.inWei(maxFeePerGasWei),
      maxPriorityFeePerGas: EtherAmount.inWei(maxPriorityFeePerGasWei),
    );
  }

  Uint8List _buildErc20TransferData({
    required EthereumAddress recipient,
    required BigInt amountUnits,
  }) {
    final selector = hexToBytes('a9059cbb');
    final paddedAddress = Uint8List(32)
      ..setRange(12, 32, recipient.addressBytes);
    final paddedAmount = _bigIntToFixedBytes(amountUnits, 32);

    return Uint8List.fromList(<int>[
      ...selector,
      ...paddedAddress,
      ...paddedAmount,
    ]);
  }

  Uint8List _bigIntToFixedBytes(BigInt value, int byteLength) {
    final hexValue = value.toRadixString(16).padLeft(byteLength * 2, '0');
    return Uint8List.fromList(hexToBytes(hexValue));
  }

  bool _isValidEvmAddress(String value) {
    return RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(value);
  }

  BigInt _parseDecimalToUnits({required String text, required int decimals}) {
    final normalized = text.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      throw const TransactionFailure('Введите сумму перевода.');
    }

    final parts = normalized.split('.');
    if (parts.length > 2) {
      throw const TransactionFailure('Сумма указана в неверном формате.');
    }

    final wholePart = parts.first.isEmpty ? '0' : parts.first;
    final fractionalPart = parts.length == 2 ? parts[1] : '';
    if (!RegExp(r'^\d+$').hasMatch(wholePart) ||
        (fractionalPart.isNotEmpty &&
            !RegExp(r'^\d+$').hasMatch(fractionalPart))) {
      throw const TransactionFailure('Сумма должна содержать только цифры.');
    }
    if (fractionalPart.length > decimals) {
      throw TransactionFailure(
        'Слишком много знаков после запятой для ${decimals.toString()} decimals.',
      );
    }

    final whole = BigInt.parse(wholePart);
    final scale = BigInt.from(10).pow(decimals);
    final paddedFraction = fractionalPart.padRight(decimals, '0');
    final fraction = paddedFraction.isEmpty
        ? BigInt.zero
        : BigInt.parse(paddedFraction);
    return whole * scale + fraction;
  }

  String _formatUnits(BigInt units, int decimals) {
    final divisor = BigInt.from(10).pow(decimals);
    final whole = units ~/ divisor;
    final remainder = units.remainder(divisor);
    if (remainder == BigInt.zero) {
      return whole.toString();
    }

    final fractional = remainder
        .toString()
        .padLeft(decimals, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    final compact = fractional.length > 6
        ? fractional.substring(0, 6)
        : fractional;
    return '$whole.$compact';
  }
}

class PublicRpcTransactionBroadcaster implements TransactionBroadcaster {
  PublicRpcTransactionBroadcaster({JsonRpcTransport? rpcTransport})
    : _rpcTransport = rpcTransport ?? HttpJsonRpcTransport();

  final JsonRpcTransport _rpcTransport;

  @override
  Future<SubmittedTransfer> submit({
    required SignedTransfer signedTransfer,
  }) async {
    TransactionFailure? lastFailure;

    for (final rpcUrl in signedTransfer.networkConfig.rpcUrls) {
      final uri = Uri.parse(rpcUrl);

      try {
        final response = await _rpcTransport.post(
          uri: uri,
          payload: <String, dynamic>{
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'eth_sendRawTransaction',
            'params': <dynamic>[signedTransfer.rawTransactionHex],
          },
        );

        final error = response['error'];
        if (error != null) {
          // Handle 'nonce too low' with retry logic
          if (error.toString().contains('nonce too low')) {
            throw TransactionFailure(
              'RPC ${uri.host} rejected due to nonce too low. Will retry with updated nonce.',
            );
          }
          throw TransactionFailure(
            'RPC ${uri.host} rejected signed transaction: $error',
          );
        }

        final result = response['result'] as String?;
        if (result == null || result.isEmpty) {
          throw TransactionFailure(
            'RPC ${uri.host} returned an empty transaction hash.',
          );
        }

        return SubmittedTransfer(
          signedTransfer: signedTransfer,
          providerLabel: uri.host,
          networkTransactionHash: result,
          submittedAtUtc: DateTime.now().toUtc(),
        );
      } on TransactionFailure catch (error) {
        lastFailure = error;
      } on BlockchainFailure catch (error) {
        lastFailure = TransactionFailure(error.message);
      } catch (error) {
        lastFailure = TransactionFailure(
          'RPC ${uri.host} failed during raw submission: $error',
        );
      }
    }

    throw lastFailure ??
        const TransactionFailure(
          'No RPC endpoints are configured for submission.',
        );
  }
}

class PublicRpcNonceProvider implements NonceProvider {
  PublicRpcNonceProvider({JsonRpcTransport? rpcTransport})
    : _rpcTransport = rpcTransport ?? HttpJsonRpcTransport();

  final JsonRpcTransport _rpcTransport;

  @override
  Future<LoadedNonce> loadNextNonce({
    required EvmNetworkConfig networkConfig,
    required String address,
  }) async {
    TransactionFailure? lastFailure;

    for (final rpcUrl in networkConfig.rpcUrls) {
      final uri = Uri.parse(rpcUrl);

      try {
        final response = await _rpcTransport.post(
          uri: uri,
          payload: <String, dynamic>{
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'eth_getTransactionCount',
            'params': <dynamic>[address, 'pending'],
          },
        );

        final error = response['error'];
        if (error != null) {
          throw TransactionFailure(
            'RPC ${uri.host} rejected nonce lookup: $error',
          );
        }

        final result = response['result'] as String?;
        if (result == null || result.isEmpty) {
          throw TransactionFailure('RPC ${uri.host} returned empty nonce.');
        }

        final nonce = int.tryParse(result.replaceFirst('0x', ''), radix: 16);
        if (nonce == null) {
          throw TransactionFailure(
            'RPC ${uri.host} returned invalid nonce value: $result',
          );
        }

        return LoadedNonce(
          network: networkConfig.network,
          address: address,
          nonce: nonce,
          providerLabel: uri.host,
          loadedAtUtc: DateTime.now().toUtc(),
        );
      } on TransactionFailure catch (error) {
        lastFailure = error;
      } on BlockchainFailure catch (error) {
        lastFailure = TransactionFailure(error.message);
      } catch (error) {
        lastFailure = TransactionFailure(
          'RPC ${uri.host} failed during nonce lookup: $error',
        );
      }
    }

    throw lastFailure ??
        const TransactionFailure(
          'No RPC endpoints are configured for nonce lookup.',
        );
  }

  /// Enhanced nonce hardening with retry logic for 'nonce too low' errors.
  Future<LoadedNonce> loadNextNonceWithRetry({
    required EvmNetworkConfig networkConfig,
    required String address,
    int maxRetries = 3,
  }) async {
    int retryCount = 0;
    while (retryCount < maxRetries) {
      try {
        return await loadNextNonce(
          networkConfig: networkConfig,
          address: address,
        );
      } on TransactionFailure catch (error) {
        if (error.message.contains('nonce too low') && retryCount < maxRetries - 1) {
          retryCount++;
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        rethrow;
      }
    }
    throw const TransactionFailure('Max retries reached for nonce loading.');
  }
}
