import '../blockchain/blockchain_provider.dart';
import '../blockchain/network_config.dart';

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
    final maxFeePerGasGwei =
        (snapshot.baseFeeGwei ?? _fallbackBaseFeeGwei) + _priorityFeeGwei;
    final feeWei =
        BigInt.from((maxFeePerGasGwei * 1000000000).round()) *
        BigInt.from(gasLimit);

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
    final totalDebitFormatted = asset.kind == TransferAssetKind.native
        ? '${_formatUnits(amountUnits + feeWei, 18)} ${asset.symbol}'
        : '$amountFormatted ${asset.symbol} + $estimatedFeeFormatted ${evmNetworkConfigs[snapshot.network]!.nativeSymbol} fee';

    return TransferPreview(
      network: snapshot.network,
      fromAddress: fromAddress,
      toAddress: normalizedTarget,
      asset: asset,
      amountFormatted: '$amountFormatted ${asset.symbol}',
      gasLimit: gasLimit,
      maxFeePerGasGwei: maxFeePerGasGwei,
      estimatedNetworkFeeNativeFormatted:
          '$estimatedFeeFormatted ${evmNetworkConfigs[snapshot.network]!.nativeSymbol}',
      totalDebitFormatted: totalDebitFormatted,
      previewNote:
          'Это только preparation/preview. Подпись и отправка ещё не включены.',
    );
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
