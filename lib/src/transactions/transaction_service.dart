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

bool isRetryableNonceFailureMessage(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains('nonce too low') ||
      normalized.contains('nonce too high') ||
      normalized.contains('replacement transaction underpriced') ||
      normalized.contains('transaction underpriced');
}

bool isUnderpricedFailureMessage(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains('replacement transaction underpriced') ||
      normalized.contains('transaction underpriced');
}

bool isAlreadyKnownFailureMessage(String message) {
  return message.toLowerCase().contains('already known');
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
    double gasMultiplier = 1.0,
  });

  /// Builds a [PreparedTransfer] from a decoded inbound WalletConnect request's
  /// raw tx fields (no app snapshot/asset model). Sign it via the usual
  /// [signPreparedTransfer] / signer seam.
  PreparedTransfer prepareInboundTransaction({
    required EvmNetwork network,
    required String fromAddress,
    required String toAddress,
    required BigInt valueWei,
    required Uint8List data,
    required int gasLimit,
    required BigInt maxFeePerGasWei,
    required BigInt maxPriorityFeePerGasWei,
  });

  SignedTransfer signPreparedTransfer({
    required PreparedTransfer preparedTransfer,
    required WalletMaterial walletMaterial,
    required int nonce,
  });

  /// Signs an arbitrary message with the EIP-191 personal-sign scheme
  /// (`personal_sign` / `eth_sign`) — the wallet prepends
  /// `"\x19Ethereum Signed Message:\n<len>"` before hashing. Returns the
  /// 65-byte `r‖s‖v` signature as a `0x`-prefixed hex string.
  String signPersonalMessage({
    required WalletMaterial walletMaterial,
    required Uint8List message,
  });

  /// Assembles a [SignedTransfer] from raw signed-transaction bytes without
  /// re-running local signing — the seam the wallet-side WC v2 / AirGap flow
  /// uses to wrap an already-signed transaction. The transaction hash is
  /// derived from [rawSignedTransaction].
  SignedTransfer assembleSignedTransfer({
    required PreparedTransfer preparedTransfer,
    required Uint8List rawSignedTransaction,
    String? signingNote,
  });

  Future<SubmittedTransfer> submitSignedTransfer({
    required SignedTransfer signedTransfer,
    required TransactionBroadcaster broadcaster,
  });

  Future<TransactionReceipt> trackTransaction({
    required SubmittedTransfer submittedTransfer,
    required JsonRpcTransport rpcTransport,
  });
}

class LocalTransactionService implements TransactionService {
  const LocalTransactionService();

  static const double _fallbackBaseFeeGwei = 1.0;
  static const double _priorityFeeGwei = 1.5;
  // Headroom over the current base fee so the tx stays includable across a few
  // blocks of EIP-1559 base-fee growth (a rising base fee does not surface as
  // an "underpriced" RPC error, so the retry/replacement path would not catch
  // it). maxFeePerGas = baseFee * headroom + priorityFee.
  static const double _baseFeeHeadroomMultiplier = 2.0;
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
    double gasMultiplier = 1.0,
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
    final maxPriorityFeePerGasWei = BigInt.from(
      (_priorityFeeGwei * 1000000000 * gasMultiplier).round(),
    );
    final baseFeeGwei = snapshot.baseFeeGwei ?? _fallbackBaseFeeGwei;
    final maxFeePerGasGwei =
        (baseFeeGwei * _baseFeeHeadroomMultiplier + _priorityFeeGwei) *
        gasMultiplier;
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
          'Preview валиден. Дальше приложение подпишет, отправит транзакцию и отследит её lifecycle.',
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
  PreparedTransfer prepareInboundTransaction({
    required EvmNetwork network,
    required String fromAddress,
    required String toAddress,
    required BigInt valueWei,
    required Uint8List data,
    required int gasLimit,
    required BigInt maxFeePerGasWei,
    required BigInt maxPriorityFeePerGasWei,
  }) {
    final networkConfig = evmNetworkConfigs[network]!;
    final symbol = networkConfig.nativeSymbol;
    final feeWei = maxFeePerGasWei * BigInt.from(gasLimit);
    final preview = TransferPreview(
      network: network,
      fromAddress: fromAddress,
      toAddress: toAddress,
      asset: TransferAssetOption(
        kind: TransferAssetKind.native,
        symbol: symbol,
        name: symbol,
        balanceFormatted: '—',
        balanceRaw: BigInt.zero,
        decimals: 18,
      ),
      amountFormatted: '${_formatUnits(valueWei, 18)} $symbol',
      gasLimit: gasLimit,
      maxFeePerGasGwei: maxFeePerGasWei.toDouble() / 1000000000,
      estimatedNetworkFeeNativeFormatted: '${_formatUnits(feeWei, 18)} $symbol',
      totalDebitFormatted: '${_formatUnits(valueWei + feeWei, 18)} $symbol',
      previewNote: 'Входящий WalletConnect-запрос на подпись.',
    );
    return PreparedTransfer(
      preview: preview,
      networkConfig: networkConfig,
      amountUnits: valueWei,
      maxFeePerGasWei: maxFeePerGasWei,
      maxPriorityFeePerGasWei: maxPriorityFeePerGasWei,
      estimatedFeeWei: feeWei,
      transaction: Transaction(
        to: EthereumAddress.fromHex(toAddress),
        maxGas: gasLimit,
        value: EtherAmount.inWei(valueWei),
        data: data,
        maxFeePerGas: EtherAmount.inWei(maxFeePerGasWei),
        maxPriorityFeePerGas: EtherAmount.inWei(maxPriorityFeePerGasWei),
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
  String signPersonalMessage({
    required WalletMaterial walletMaterial,
    required Uint8List message,
  }) {
    final credentials = EthPrivateKey.fromHex(walletMaterial.privateKeyHex);
    final signature = credentials.signPersonalMessageToUint8List(message);
    return bytesToHex(signature, include0x: true);
  }

  @override
  SignedTransfer assembleSignedTransfer({
    required PreparedTransfer preparedTransfer,
    required Uint8List rawSignedTransaction,
    String? signingNote,
  }) {
    return SignedTransfer(
      preview: preparedTransfer.preview,
      networkConfig: preparedTransfer.networkConfig,
      rawTransactionBytes: rawSignedTransaction,
      rawTransactionHex: bytesToHex(rawSignedTransaction, include0x: true),
      transactionHashHex: bytesToHex(
        keccak256(rawSignedTransaction),
        include0x: true,
      ),
      signingNote: signingNote ?? 'Транзакция собрана из внешней подписи.',
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
          final message = error.toString();
          if (isAlreadyKnownFailureMessage(message)) {
            return SubmittedTransfer(
              signedTransfer: signedTransfer,
              providerLabel: uri.host,
              networkTransactionHash: signedTransfer.transactionHashHex,
              submittedAtUtc: DateTime.now().toUtc(),
            );
          }
          if (isRetryableNonceFailureMessage(message)) {
            throw TransactionFailure(
              'RPC ${uri.host} rejected signed transaction with a retryable nonce/pricing issue: $message',
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
}
