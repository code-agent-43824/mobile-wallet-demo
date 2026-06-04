part of 'wallet_flow_screen.dart';

class _UnlockedStage extends StatefulWidget {
  const _UnlockedStage({
    required this.blockchainProvider,
    required this.transactionService,
    required this.transactionBroadcaster,
    required this.nonceProvider,
    required this.trackingTransport,
    required this.walletOperationAuthorizer,
    required this.activeBackend,
    required this.authMethod,
    required this.material,
    required this.summary,
    required this.backendLabel,
    required this.externalRuntimeState,
    required this.biometricsEnabled,
    required this.onLock,
    required this.onReconnectExternalDevice,
    required this.onDisconnectExternalSession,
    required this.onSimulateExternalOffline,
    required this.onPingExternalDevice,
    required this.onReadExternalAddress,
    required this.onRefreshExternalRuntimeState,
  });

  final BlockchainProvider blockchainProvider;
  final TransactionService transactionService;
  final TransactionBroadcaster transactionBroadcaster;
  final NonceProvider nonceProvider;
  final JsonRpcTransport trackingTransport;
  final WalletOperationAuthorizer walletOperationAuthorizer;
  final KeyStorageBackend activeBackend;
  final WalletAuthMethod authMethod;
  final WalletMaterial? material;
  final StoredWalletSummary? summary;
  final String backendLabel;
  final ExternalDeviceDemoRuntimeState? externalRuntimeState;
  final bool biometricsEnabled;
  final VoidCallback onLock;
  final Future<void> Function()? onReconnectExternalDevice;
  final Future<void> Function()? onDisconnectExternalSession;
  final Future<void> Function()? onSimulateExternalOffline;
  final Future<void> Function()? onPingExternalDevice;
  final Future<void> Function()? onReadExternalAddress;
  final Future<void> Function()? onRefreshExternalRuntimeState;

  @override
  State<_UnlockedStage> createState() => _UnlockedStageState();
}

class _UnlockedStageState extends State<_UnlockedStage> {
  EvmNetwork _selectedNetwork = EvmNetwork.ethereumMainnet;
  WalletChainSnapshot? _snapshot;
  String? _error;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final address = widget.material?.address ?? widget.summary?.address;
    if (address == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final snapshot = await widget.blockchainProvider.loadSnapshot(
        network: _selectedNetwork,
        address: address,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
      });
    } on BlockchainFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final address = widget.material?.address ?? widget.summary?.address ?? '—';
    final config = evmNetworkConfigs[_selectedNetwork]!;
    final snapshot = _snapshot;
    final externalRuntimeState = widget.externalRuntimeState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Wallet runtime + Phase 7 foundation'),
        const SizedBox(height: 12),
        const Text(
          'Phase 6 уже закрыт. Теперь строим основу для нескольких storage backends: текущее выполнение идёт через выбранный backend и совместимый signing/auth контракт.',
        ),
        const SizedBox(height: 20),
        _SummaryTile(label: 'Активный адрес', value: address),
        const SizedBox(height: 10),
        _SummaryTile(label: 'Backend', value: widget.backendLabel),
        const SizedBox(height: 10),
        _SummaryTile(
          label: 'Последний auth-метод',
          value: switch (widget.authMethod) {
            WalletAuthMethod.pin => 'PIN',
            WalletAuthMethod.biometric => 'Biometric unlock',
            WalletAuthMethod.externalDevice => 'External device',
          },
        ),
        const SizedBox(height: 10),
        _SummaryTile(
          label: 'Биометрия',
          value: widget.biometricsEnabled
              ? 'Включена в shell-flow'
              : 'Пока выключена',
        ),
        if (widget.activeBackend is ExternalDeviceKeyStorageBackend &&
            externalRuntimeState != null) ...[
          const SizedBox(height: 10),
          _SummaryTile(
            label: 'Demo device availability',
            value: externalRuntimeState.isAvailable ? 'Online' : 'Offline',
          ),
          const SizedBox(height: 10),
          _SummaryTile(
            label: 'Device session',
            value: externalRuntimeState.hasActiveSession
                ? 'Active'
                : 'Needs reconnect/auth',
          ),
          if (externalRuntimeState.connectedAtUtc
              case final DateTime connectedAt) ...[
            const SizedBox(height: 10),
            _SummaryTile(
              label: 'Session connected at',
              value: connectedAt.toIso8601String(),
            ),
          ],
          if (externalRuntimeState.lastError case final String error) ...[
            const SizedBox(height: 10),
            _ErrorBanner(message: error),
          ],
          if (externalRuntimeState.session
              case final ExternalDevicePkcs11SessionSnapshot session) ...[
            const SizedBox(height: 10),
            _SummaryTile(label: 'PKCS#11 session id', value: session.sessionId),
            const SizedBox(height: 10),
            _SummaryTile(
              label: 'PKCS#11 operations',
              value: session.operationCount.toString(),
            ),
            if (session.lastOperationKind != null) ...[
              const SizedBox(height: 10),
              _SummaryTile(
                label: 'Last PKCS#11 operation',
                value: session.lastOperationKind!.name,
              ),
            ],
            if (session.lastMessage case final String message) ...[
              const SizedBox(height: 10),
              _SummaryTile(label: 'Last PKCS#11 result', value: message),
            ],
          ],
        ],
        const SizedBox(height: 20),
        DropdownButtonFormField<EvmNetwork>(
          initialValue: _selectedNetwork,
          decoration: const InputDecoration(
            labelText: 'Сеть',
            border: OutlineInputBorder(),
          ),
          items: EvmNetwork.values
              .map(
                (network) => DropdownMenuItem<EvmNetwork>(
                  value: network,
                  child: Text(evmNetworkConfigs[network]!.name),
                ),
              )
              .toList(),
          onChanged: (network) {
            if (network == null) {
              return;
            }

            setState(() {
              _selectedNetwork = network;
            });
            _refresh();
          },
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          const LinearProgressIndicator()
        else if (_error != null)
          _ErrorBanner(message: _error!)
        else if (snapshot != null)
          Column(
            children: [
              _SummaryTile(
                label: 'Нативный баланс',
                value:
                    '${snapshot.nativeBalanceFormatted} ${config.nativeSymbol}',
              ),
              const SizedBox(height: 10),
              _SummaryTile(
                label: 'Base fee',
                value: snapshot.baseFeeGwei == null
                    ? 'Недоступно'
                    : '${snapshot.baseFeeGwei!.toStringAsFixed(3)} gwei',
              ),
              const SizedBox(height: 10),
              _SummaryTile(
                label: 'RPC endpoint',
                value: snapshot.providerLabel,
              ),
              const SizedBox(height: 10),
              _SummaryTile(
                label: 'Обновлено',
                value: snapshot.fetchedAtUtc.toIso8601String(),
              ),
              const SizedBox(height: 10),
              _SummaryTile(
                label: 'Источник данных',
                value: snapshot.loadedFromCache
                    ? 'Локальный кэш'
                    : 'Живой запрос к сети',
              ),
            ],
          ),
        if (snapshot != null) ...[
          const SizedBox(height: 20),
          _TokenBalancesSection(snapshot: snapshot),
          const SizedBox(height: 20),
          _RecentTransactionsSection(snapshot: snapshot),
          const SizedBox(height: 20),
          _TransferPreparationSection(
            snapshot: snapshot,
            fromAddress: address,
            networkConfig: config,
            activeBackend: widget.activeBackend,
            walletMaterial: widget.material,
            authMethod: widget.authMethod,
            walletOperationAuthorizer: widget.walletOperationAuthorizer,
            transactionService: widget.transactionService,
            transactionBroadcaster: widget.transactionBroadcaster,
            nonceProvider: widget.nonceProvider,
            trackingTransport: widget.trackingTransport,
            onExternalPkcs11OperationRecorded:
                widget.onRefreshExternalRuntimeState,
          ),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            const _StatusChip(label: 'Unlocked'),
            const _StatusChip(label: 'Read-only RPC'),
            const _StatusChip(label: 'Signing + send flow'),
            _StatusChip(label: 'Chain ${config.chainId}'),
            if (widget.activeBackend is ExternalDeviceKeyStorageBackend)
              _StatusChip(
                label: externalRuntimeState?.isAvailable ?? false
                    ? 'Device online'
                    : 'Device offline',
              ),
            if (snapshot?.loadedFromCache ?? false)
              const _StatusChip(label: 'Cached fallback'),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Обновить с блокчейна'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onLock,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Заблокировать снова'),
            ),
            if (widget.onDisconnectExternalSession != null)
              OutlinedButton.icon(
                onPressed: widget.onDisconnectExternalSession,
                icon: const Icon(Icons.link_off),
                label: const Text('Разорвать device session'),
              ),
            if (widget.onReconnectExternalDevice != null)
              OutlinedButton.icon(
                onPressed: widget.onReconnectExternalDevice,
                icon: const Icon(Icons.usb),
                label: const Text('Переподключить demo device'),
              ),
            if (widget.onPingExternalDevice != null)
              OutlinedButton.icon(
                onPressed: widget.onPingExternalDevice,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Проверить PKCS#11 session'),
              ),
            if (widget.onReadExternalAddress != null)
              OutlinedButton.icon(
                onPressed: widget.onReadExternalAddress,
                icon: const Icon(Icons.badge_outlined),
                label: const Text('Прочитать адрес через PKCS#11'),
              ),
            if (widget.onSimulateExternalOffline != null)
              TextButton(
                onPressed: widget.onSimulateExternalOffline,
                child: const Text('Симулировать offline'),
              ),
          ],
        ),
      ],
    );
  }
}

class _TransferPreparationSection extends StatefulWidget {
  const _TransferPreparationSection({
    required this.snapshot,
    required this.fromAddress,
    required this.networkConfig,
    required this.activeBackend,
    required this.walletMaterial,
    required this.authMethod,
    required this.walletOperationAuthorizer,
    required this.transactionService,
    required this.transactionBroadcaster,
    required this.nonceProvider,
    required this.trackingTransport,
    required this.onExternalPkcs11OperationRecorded,
  });

  final WalletChainSnapshot snapshot;
  final String fromAddress;
  final EvmNetworkConfig networkConfig;
  final KeyStorageBackend activeBackend;
  final WalletMaterial? walletMaterial;
  final WalletAuthMethod authMethod;
  final WalletOperationAuthorizer walletOperationAuthorizer;
  final TransactionService transactionService;
  final TransactionBroadcaster transactionBroadcaster;
  final NonceProvider nonceProvider;
  final JsonRpcTransport trackingTransport;
  final Future<void> Function()? onExternalPkcs11OperationRecorded;

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
    final stillExists = assets.any((asset) => asset.id == selectedId);
    if (!stillExists) {
      _selectedAsset = assets.isEmpty ? null : assets.first;
      _preview = null;
      _loadedNonce = null;
      _signedTransfer = null;
      _submittedTransfer = null;
      _trackingReceipt = null;
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

    AuthorizedWalletOperation authorizedOperation;
    try {
      widget.transactionService.prepareTransfer(
        snapshot: widget.snapshot,
        fromAddress: widget.fromAddress,
        toAddress: _addressController.text,
        amountText: _amountController.text,
        asset: asset,
      );

      if (widget.activeBackend is ExternalDeviceKeyStorageBackend) {
        if (widget.activeBackend is ExternalDeviceDemoBackend) {
          await (widget.activeBackend as ExternalDeviceDemoBackend)
              .performPkcs11Operation(
                ExternalDevicePkcs11Operation(
                  kind:
                      ExternalDevicePkcs11OperationKind.signTransactionPreview,
                  payload:
                      '${_amountController.text} ${asset.symbol} -> ${_addressController.text}',
                ),
              );
          await widget.onExternalPkcs11OperationRecorded?.call();
        }
        authorizedOperation = widget.walletOperationAuthorizer
            .authorizeUnlockedExternalDeviceSigning(
              backend: widget.activeBackend as ExternalDeviceKeyStorageBackend,
              walletMaterial: widget.walletMaterial,
            );
      } else {
        authorizedOperation = widget.walletOperationAuthorizer
            .authorizeUnlockedLocalSigning(
              backend: widget.activeBackend,
              walletMaterial: widget.walletMaterial,
              authMethod: widget.authMethod,
            );
      }
    } on VaultFailure catch (error) {
      setState(() {
        _error = error.message;
      });
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
      final hardenedService = widget.transactionService;
      if (hardenedService is! HardenedTransactionService) {
        throw const TransactionFailure(
          'Текущий transaction service не поддерживает Phase 6 hardened flow.',
        );
      }

      final result = await hardenedService.submitAuthorizedTransferFlow(
        snapshot: widget.snapshot,
        fromAddress: widget.fromAddress,
        toAddress: _addressController.text,
        amountText: _amountController.text,
        asset: asset,
        signer: authorizedOperation.signer,
        broadcaster: widget.transactionBroadcaster,
        nonceProvider: widget.nonceProvider,
        tracker: tracker,
      );

      if (!mounted) {
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
        const SizedBox(height: 12),
        const Text(
          'Phase 6: Поддержка retries, замены транзакций, gas price increase, tracking.',
        ),
        const SizedBox(height: 16),
        if (_replacementTransfer)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Заменённая транзакция',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
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
                label: const Text('Оценить и показать preview'),
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

class _TokenBalancesSection extends StatelessWidget {
  const _TokenBalancesSection({required this.snapshot});

  final WalletChainSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Токены'),
        const SizedBox(height: 12),
        if (snapshot.tokenBalances.isEmpty)
          const _SummaryTile(
            label: 'Token balances',
            value:
                'Пока пусто или публичный индексер не вернул ненулевые токены.',
          )
        else
          Column(
            children: snapshot.tokenBalances
                .map(
                  (token) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SummaryTile(
                      label: '${token.symbol} · ${token.name}',
                      value:
                          '${token.balanceFormatted}\n${token.contractAddress}',
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _RecentTransactionsSection extends StatelessWidget {
  const _RecentTransactionsSection({required this.snapshot});

  final WalletChainSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Последние транзакции'),
        const SizedBox(height: 12),
        if (snapshot.recentTransactions.isEmpty)
          const _SummaryTile(
            label: 'История',
            value: 'Пока пусто или индексер не вернул недавние операции.',
          )
        else
          Column(
            children: snapshot.recentTransactions
                .map(
                  (tx) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SummaryTile(
                      label: '${tx.directionLabel} · ${tx.statusLabel}',
                      value:
                          '${tx.valueFormatted}\n${tx.counterparty}\n${tx.hash}\n${tx.timestampUtc?.toIso8601String() ?? 'Время неизвестно'}',
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}
