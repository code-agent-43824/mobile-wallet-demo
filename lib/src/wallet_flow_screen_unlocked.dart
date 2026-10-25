part of 'wallet_flow_screen.dart';

/// Where the send sheet is in the confirmation pattern. One sheet walks every
/// step rather than stacking a PIN sheet and a busy overlay on top of it.
enum _SendStep { form, review, pin, working, result }

/// The transfer sheet: form → review → PIN → signing (or the card tap) →
/// result (pending → confirmed). No key material is held while it is shown;
/// the private-key part runs in [WalletFlowController.authorizeAndSubmitTransfer]
/// behind the PIN step, freshly unlocked for this send only.
class _TransferPreparationSection extends StatefulWidget {
  const _TransferPreparationSection({
    required this.controller,
    required this.snapshot,
    required this.fromAddress,
    required this.networkConfig,
    required this.transactionService,
    required this.trackingTransport,
    required this.canUnlockWithBiometrics,
  });

  final WalletFlowController controller;
  final WalletChainSnapshot snapshot;
  final String fromAddress;
  final EvmNetworkConfig networkConfig;
  final TransactionService transactionService;
  final JsonRpcTransport trackingTransport;
  final bool canUnlockWithBiometrics;

  @override
  State<_TransferPreparationSection> createState() =>
      _TransferPreparationSectionState();
}

class _TransferPreparationSectionState
    extends State<_TransferPreparationSection> {
  late final TextEditingController _addressController;
  late final TextEditingController _amountController;

  _SendStep _step = _SendStep.form;
  TransferAssetOption? _selectedAsset;
  TransferPreview? _preview;
  String? _error;
  HardenedSubmitResult? _result;
  String? _failure;
  TransactionReceipt? _trackingReceipt;

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
    // A changed snapshot invalidates a review that has not been signed yet;
    // once signing has started, the result belongs to the snapshot it used.
    if ((snapshotChanged || selectedId != nextSelectedAsset?.id) &&
        (_step == _SendStep.form || _step == _SendStep.review)) {
      _preview = null;
      _error = null;
      _step = _SendStep.form;
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _review() {
    final l10n = AppLocalizations.of(context);
    final asset = _selectedAsset;
    if (asset == null) {
      setState(() => _error = l10n.transferPickAssetFirst);
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
        _error = null;
        _step = _SendStep.review;
      });
    } on TransactionFailure catch (error) {
      setState(() {
        _preview = null;
        _error = describeError(l10n, error);
      });
    }
  }

  void _toPin() {
    final l10n = AppLocalizations.of(context);
    final asset = _selectedAsset;
    if (asset == null) return;
    // Read-only validation stays here; the private-key part runs in the
    // controller after the PIN step.
    try {
      widget.transactionService.prepareTransfer(
        snapshot: widget.snapshot,
        fromAddress: widget.fromAddress,
        toAddress: _addressController.text,
        amountText: _amountController.text,
        asset: asset,
      );
    } on TransactionFailure catch (error) {
      setState(() => _error = describeError(l10n, error));
      return;
    }
    setState(() {
      _error = null;
      _step = _SendStep.pin;
    });
  }

  Future<void> _submit(String? pin, bool useBiometrics) async {
    final l10n = AppLocalizations.of(context);
    final asset = _selectedAsset;
    if (asset == null) return;
    setState(() {
      _step = _SendStep.working;
      _result = null;
      _failure = null;
      _trackingReceipt = null;
    });

    HardenedSubmitResult? result;
    String? failure;
    try {
      result = await widget.controller.authorizeAndSubmitTransfer(
        snapshot: widget.snapshot,
        fromAddress: widget.fromAddress,
        toAddress: _addressController.text,
        amountText: _amountController.text,
        asset: asset,
        tracker: TransactionTracker(rpcTransport: widget.trackingTransport),
        pin: pin,
        useBiometrics: useBiometrics,
      );
    } on TransactionFailure catch (error) {
      failure = describeError(l10n, error);
    }
    if (!mounted) return;
    if (result == null) {
      // The controller reported the failure through its error state; show it
      // here and drop it there, so the page banner does not repeat it.
      failure ??= widget.controller.errorMessage ?? l10n.transferNotSent;
      widget.controller.clearError();
      setState(() {
        _failure = failure;
        _step = _SendStep.result;
      });
      return;
    }

    final submitted = result;
    setState(() {
      _result = submitted;
      _step = _SendStep.result;
    });
    unawaited(
      submitted.trackingFuture
          .then((receipt) {
            if (mounted) setState(() => _trackingReceipt = receipt);
          })
          .catchError((Object error) {
            if (!mounted) return;
            setState(() {
              _trackingReceipt = TransactionReceipt(
                status: TransactionStatus.failed,
                errorMessage: error is TransactionFailure
                    ? describeError(l10n, error)
                    : l10n.transferTrackingFailed('$error'),
              );
            });
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final step = _step;
    return PopScope(
      // Leaving mid-signature would orphan the operation's progress.
      canPop: step != _SendStep.working,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The sheet needs its own way out — the back gesture alone is not an
          // affordance — except while signing, when leaving is not offered.
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: step == _SendStep.working
                  ? null
                  : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              tooltip: l10n.actionClose,
            ),
          ),
          switch (step) {
            _SendStep.form => _buildForm(context),
            _SendStep.review => _buildReview(context),
            _SendStep.pin => _PinEntryPanel(
              reason: l10n.transferNeedsKey,
              biometricsOffered: widget.canUnlockWithBiometrics,
              onPin: (pin) => _submit(pin, false),
              onBiometrics: () => _submit(null, true),
              onCancel: () => setState(() => _step = _SendStep.review),
            ),
            _SendStep.working => _OperationProgress(
              controller: widget.controller,
            ),
            _SendStep.result => _buildResult(context),
          },
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final assets = _assets;
    final selected = _selectedAsset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(l10n.transferTitle),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: selected?.id,
          decoration: InputDecoration(
            labelText: l10n.transferAsset,
            border: const OutlineInputBorder(),
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
              _error = null;
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _addressController,
          decoration: InputDecoration(
            labelText: l10n.transferRecipientLabel,
            hintText: '0x…',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.transferAmount,
            hintText: l10n.transferAmountHint,
            helperText: selected == null
                ? null
                : l10n.transferAvailable(
                    selected.balanceFormatted,
                    selected.symbol,
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_error case final String message) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: message),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _review,
          icon: const Icon(Icons.visibility_outlined),
          label: Text(l10n.transferPreviewAction),
        ),
      ],
    );
  }

  Widget _buildReview(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preview = _preview;
    if (preview == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(l10n.transferReview),
        const SizedBox(height: 16),
        _SummaryTile(label: l10n.transferRecipient, value: preview.toAddress),
        const SizedBox(height: 10),
        _SummaryTile(
          label: l10n.transferAssetAndAmount,
          value: preview.amountFormatted,
        ),
        const SizedBox(height: 10),
        _SummaryTile(
          label: l10n.transferNetworkFee,
          value: preview.estimatedNetworkFeeNativeFormatted,
        ),
        const SizedBox(height: 10),
        _SummaryTile(
          label: l10n.transferTotalDebit,
          value: preview.totalDebitFormatted,
        ),
        if (_error case final String message) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: message),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _toPin,
          icon: const Icon(Icons.send_outlined),
          label: Text(l10n.transferSignAndSend),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            _error = null;
            _step = _SendStep.form;
          }),
          child: Text(l10n.transferEdit),
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final result = _result;
    if (result == null) {
      return _OperationResult(
        success: false,
        title: l10n.transferNotSent,
        body: _failure ?? '',
        primaryLabel: l10n.actionBack,
        onPrimary: () => setState(() => _step = _SendStep.review),
        secondaryLabel: l10n.actionClose,
        onSecondary: () => Navigator.of(context).pop(),
      );
    }
    final submitted = result.submittedTransfer;
    final receipt = _trackingReceipt;
    return _OperationResult(
      success:
          receipt?.status != TransactionStatus.reverted &&
          receipt?.status != TransactionStatus.failed,
      title: l10n.transferSuccess,
      body: _trackingSentence(l10n, result, receipt),
      primaryLabel: l10n.actionDone,
      onPrimary: () => Navigator.of(context).pop(),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (result.replacementUsed) ...[
            _ErrorBanner(
              message:
                  '${l10n.transferReplaced}. '
                  '${l10n.transferReplacedBody(result.gasMultiplierUsed.toStringAsFixed(2))}',
            ),
            const SizedBox(height: 10),
          ],
          _SummaryTile(
            label: l10n.transferHash,
            value: submitted.networkTransactionHash,
          ),
          // Nonce, endpoint, block and gas are developer detail; the design
          // keeps them behind «Подробности» rather than in the result itself.
          ExpansionTile(
            title: Text(l10n.settingsDetails),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                <String>[
                  'Nonce: ${result.loadedNonce.nonce}',
                  'RPC: ${submitted.providerLabel}',
                  if (receipt?.blockNumber case final Object block)
                    'Block: $block',
                  if (receipt?.gasUsed case final Object gas) 'Gas used: $gas',
                  if (result.attempts > 1)
                    l10n.transferAttempts(result.attempts),
                  submitted.submittedAtUtc.toIso8601String(),
                ].join('\n'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _trackingSentence(
    AppLocalizations l10n,
    HardenedSubmitResult result,
    TransactionReceipt? receipt,
  ) {
    if (receipt == null) {
      return result.attempts > 1
          ? l10n.transferBroadcastAfterRetry(result.attempts)
          : l10n.transferBroadcast;
    }
    return switch (receipt.status) {
      TransactionStatus.confirmed => l10n.transferConfirmed,
      TransactionStatus.reverted => l10n.transferReverted,
      TransactionStatus.pending => l10n.transferPendingTimeout,
      TransactionStatus.failed =>
        receipt.errorMessage ?? l10n.transferTrackingFailed(''),
    };
  }
}
