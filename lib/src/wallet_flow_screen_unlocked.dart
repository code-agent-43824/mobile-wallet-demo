part of 'wallet_flow_screen.dart';

/// Signature for the send-form authorize+sign+submit callback: the widget keeps
/// the read-only preview, this runs the private-key part (auth → unlock → sign →
/// submit) in the controller. Returns null if the user cancelled the auth
/// prompt; throws [TransactionFailure]/[VaultFailure] on a real failure.
typedef AuthorizeAndSubmitTransfer =
    Future<HardenedSubmitResult?> Function({
      required WalletChainSnapshot snapshot,
      required String fromAddress,
      required String toAddress,
      required String amountText,
      required TransferAssetOption asset,
      required TransactionTracker tracker,
      String? pin,
      bool useBiometrics,
    });

/// The transfer form. No key material is held while it is shown; submitting it
/// triggers a per-operation auth prompt and a freshly-unlocked sign via
/// [onAuthorizeAndSubmit].
class _TransferPreparationSection extends StatefulWidget {
  const _TransferPreparationSection({
    required this.snapshot,
    required this.fromAddress,
    required this.networkConfig,
    required this.transactionService,
    required this.trackingTransport,
    required this.canUnlockWithBiometrics,
    required this.onAuthorizeAndSubmit,
  });

  final WalletChainSnapshot snapshot;
  final String fromAddress;
  final EvmNetworkConfig networkConfig;
  final TransactionService transactionService;
  final JsonRpcTransport trackingTransport;
  final bool canUnlockWithBiometrics;
  final AuthorizeAndSubmitTransfer onAuthorizeAndSubmit;

  @override
  State<_TransferPreparationSection> createState() =>
      _TransferPreparationSectionState();
}

class _TransferPreparationSectionState
    extends State<_TransferPreparationSection> {
  late final TextEditingController _addressController;
  late final TextEditingController _amountController;

  TransferAssetOption? _selectedAsset;
  TransferPreview? _preview;
  LoadedNonce? _loadedNonce;
  SignedTransfer? _signedTransfer;
  SubmittedTransfer? _submittedTransfer;
  TransactionReceipt? _trackingReceipt;
  String? _error;
  bool _isSubmitting = false;
  int _submissionAttempts = 0;
  double _gasMultiplier = 1.0;
  bool _replacementTransfer = false;

  List<TransferAssetOption> get _assets =>
      widget.transactionService.availableAssets(
        snapshot: widget.snapshot,
        networkConfig: widget.networkConfig,
      );

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController();
    _amountController = TextEditingController();
    final assets = _assets;
    _selectedAsset = assets.isEmpty ? null : assets.first;
  }

  @override
  void didUpdateWidget(covariant _TransferPreparationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final assets = _assets;
    final selectedId = _selectedAsset?.id;
    final selectedIndex = assets.indexWhere((asset) => asset.id == selectedId);
    final nextSelectedAsset = selectedIndex < 0
        ? (assets.isEmpty ? null : assets.first)
        : assets[selectedIndex];
    final snapshotChanged =
        !identical(oldWidget.snapshot, widget.snapshot) ||
        oldWidget.networkConfig.network != widget.networkConfig.network ||
        oldWidget.fromAddress != widget.fromAddress;

    // TransferAssetOption carries balanceRaw. Rebind even when the asset id is
    // unchanged so validation uses the latest snapshot rather than the object
    // created before an incoming transfer or network refresh.
    _selectedAsset = nextSelectedAsset;
    if (snapshotChanged || selectedId != nextSelectedAsset?.id) {
      _preview = null;
      _loadedNonce = null;
      _signedTransfer = null;
      _submittedTransfer = null;
      _trackingReceipt = null;
      _submissionAttempts = 0;
      _gasMultiplier = 1.0;
      _replacementTransfer = false;
      _error = null;
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _buildPreview() {
    final asset = _selectedAsset;
    if (asset == null) {
      return;
    }

    try {
      final preview = widget.transactionService.preparePreview(
        snapshot: widget.snapshot,
        fromAddress: widget.fromAddress,
        toAddress: _addressController.text,
        amountText: _amountController.text,
        asset: asset,
      );
      setState(() {
        _preview = preview;
        _loadedNonce = null;
        _signedTransfer = null;
        _submittedTransfer = null;
        _trackingReceipt = null;
        _error = null;
      });
    } on TransactionFailure catch (error) {
      setState(() {
        _preview = null;
        _loadedNonce = null;
        _signedTransfer = null;
        _submittedTransfer = null;
        _trackingReceipt = null;
        _error = error.message;
      });
    }
  }

  Future<void> _signAndSubmit() async {
    final asset = _selectedAsset;
    if (asset == null) {
      setState(() {
        _error = 'Сначала выбери актив для отправки.';
      });
      return;
    }

    // Read-only validation stays in the widget; the private-key part runs in the
    // controller behind a per-op auth prompt.
    try {
      widget.transactionService.prepareTransfer(
        snapshot: widget.snapshot,
        fromAddress: widget.fromAddress,
        toAddress: _addressController.text,
        amountText: _amountController.text,
        asset: asset,
      );
    } on TransactionFailure catch (error) {
      setState(() {
        _error = error.message;
      });
      return;
    }

    final credential = await _promptForAuth(
      context,
      reason: 'Подпись и отправка перевода требует доступа к приватному ключу.',
      biometricsOffered: widget.canUnlockWithBiometrics,
    );
    if (credential == null || !mounted) {
      // User dismissed the auth sheet — abort silently, no error.
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
      _loadedNonce = null;
      _signedTransfer = null;
      _submittedTransfer = null;
      _trackingReceipt = null;
      _submissionAttempts = 0;
      _gasMultiplier = 1.0;
      _replacementTransfer = false;
    });

    try {
      final tracker = TransactionTracker(
        rpcTransport: widget.trackingTransport,
      );

      final result = await widget.onAuthorizeAndSubmit(
        snapshot: widget.snapshot,
        fromAddress: widget.fromAddress,
        toAddress: _addressController.text,
        amountText: _amountController.text,
        asset: asset,
        tracker: tracker,
        pin: credential.pin,
        useBiometrics: credential.useBiometrics,
      );

      if (!mounted) {
        return;
      }

      if (result == null) {
        // The controller surfaced the failure via its own errorMessage banner
        // (VaultFailure: wrong PIN/lockout/offline). Just clear the spinner.
        setState(() {
          _isSubmitting = false;
        });
        return;
      }

      setState(() {
        _preview = result.preparedTransfer.preview;
        _loadedNonce = result.loadedNonce;
        _signedTransfer = result.signedTransfer;
        _submittedTransfer = result.submittedTransfer;
        _submissionAttempts = result.attempts;
        _gasMultiplier = result.gasMultiplierUsed;
        _replacementTransfer = result.replacementUsed;
        _error = null;
        _isSubmitting = false;
      });

      unawaited(
        result.trackingFuture
            .then((trackingReceipt) {
              if (!mounted) {
                return;
              }
              setState(() {
                _trackingReceipt = trackingReceipt;
              });
            })
            .catchError((Object error) {
              if (!mounted) {
                return;
              }
              final message = error is TransactionFailure
                  ? error.message
                  : 'Tracking завершился с ошибкой: $error';
              setState(() {
                _trackingReceipt = TransactionReceipt(
                  status: TransactionStatus.failed,
                  errorMessage: message,
                );
              });
            }),
      );
    } on TransactionFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } finally {
      if (mounted && _isSubmitting) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final assets = _assets;
    final submittedTransfer = _submittedTransfer;
    final signedTransfer = _signedTransfer;
    final loadedNonce = _loadedNonce;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Подготовка и отправка перевода'),
        const SizedBox(height: 16),
        if (_replacementTransfer)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NocturneColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: NocturneColors.warning),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: NocturneColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Заменённая транзакция',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: NocturneColors.warning,
                              fontWeight: NocturneType.semibold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'RPC запросил replacement с более высоким gas price. Повторная отправка выполнена с multiplier ×${_gasMultiplier.toStringAsFixed(2)}.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _selectedAsset?.id,
          decoration: const InputDecoration(
            labelText: 'Актив',
            border: OutlineInputBorder(),
          ),
          items: assets
              .map(
                (asset) => DropdownMenuItem<String>(
                  value: asset.id,
                  child: Text('${asset.symbol} · ${asset.balanceFormatted}'),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            final nextAsset = assets.firstWhere((asset) => asset.id == value);
            setState(() {
              _selectedAsset = nextAsset;
              _preview = null;
              _loadedNonce = null;
              _signedTransfer = null;
              _submittedTransfer = null;
              _trackingReceipt = null;
              _submissionAttempts = 0;
              _error = null;
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _addressController,
          decoration: const InputDecoration(
            labelText: 'Адрес получателя',
            hintText: '0x…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Сумма',
            hintText: 'Например 0.1',
            helperText: _selectedAsset == null
                ? null
                : 'Доступно: ${_selectedAsset!.balanceFormatted} ${_selectedAsset!.symbol}',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _buildPreview,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Проверить перевод'),
              ),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _signAndSubmit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(
                  _isSubmitting ? 'Отправка…' : 'Подписать и отправить',
                ),
              ),
            ],
          ),
        ),
        if (_error case final String message) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: message),
        ],
        if (preview != null) ...[
          const SizedBox(height: 16),
          _SummaryTile(label: 'Получатель', value: preview.toAddress),
          const SizedBox(height: 10),
          _SummaryTile(label: 'Актив и сумма', value: preview.amountFormatted),
          const SizedBox(height: 10),
          _SummaryTile(
            label: 'Estimated gas',
            value:
                '${preview.gasLimit} gas\nmax fee ≈ ${preview.maxFeePerGasGwei.toStringAsFixed(3)} gwei',
          ),
          const SizedBox(height: 10),
          _SummaryTile(
            label: 'Estimated network fee',
            value: preview.estimatedNetworkFeeNativeFormatted,
          ),
          const SizedBox(height: 10),
          _SummaryTile(
            label: 'Итоговый debit',
            value: preview.totalDebitFormatted,
          ),
          const SizedBox(height: 10),
          _SummaryTile(label: 'Статус', value: preview.previewNote),
        ],
        if (_isSubmitting) ...[
          const SizedBox(height: 16),
          const _SummaryTile(
            label: 'Состояние отправки',
            value:
                'Идёт операция: готовим transfer, получаем nonce, подписываем локально и отправляем raw transaction в RPC.',
          ),
        ],
        if (loadedNonce != null) ...[
          const SizedBox(height: 16),
          _SummaryTile(
            label: 'Loaded nonce',
            value:
                '${loadedNonce.nonce}\nRPC: ${loadedNonce.providerLabel}\n${loadedNonce.loadedAtUtc.toIso8601String()}',
          ),
        ],
        if (signedTransfer != null) ...[
          const SizedBox(height: 10),
          _SummaryTile(
            label: 'Signed transaction',
            value:
                '${signedTransfer.transactionHashHex}\n${signedTransfer.signingNote}',
          ),
        ],
        if (submittedTransfer != null) ...[
          const SizedBox(height: 10),
          _SummaryTile(
            label: 'Успешная отправка',
            value:
                '${submittedTransfer.networkTransactionHash}\nRPC: ${submittedTransfer.providerLabel}\n${submittedTransfer.submittedAtUtc.toIso8601String()}',
          ),
          const SizedBox(height: 10),
          _SummaryTile(
            label: 'Tracking / lifecycle',
            value: _buildTrackingStatus(),
          ),
        ],
      ],
    );
  }

  String _buildTrackingStatus() {
    final receipt = _trackingReceipt;
    if (_submittedTransfer == null) {
      return 'Tracking ещё не запускался.';
    }
    if (receipt == null) {
      return _submissionAttempts > 1
          ? 'Транзакция отправлена после retry ($_submissionAttempts попытки). Идёт ожидание receipt…'
          : 'Транзакция отправлена. Идёт ожидание receipt…';
    }

    final statusLabel = switch (receipt.status) {
      TransactionStatus.confirmed => 'Confirmed',
      TransactionStatus.reverted => 'Reverted',
      TransactionStatus.pending => 'Pending / timeout',
      TransactionStatus.failed => 'Failed',
    };

    final details = <String>[
      'Статус: $statusLabel',
      if (receipt.blockNumber != null) 'Block: ${receipt.blockNumber}',
      if (receipt.gasUsed != null) 'Gas used: ${receipt.gasUsed}',
      if (_submissionAttempts > 1) 'Попыток отправки: $_submissionAttempts',
      if (receipt.errorMessage != null) receipt.errorMessage!,
    ];

    return details.join('\n');
  }
}
