import 'package:flutter/material.dart';

import 'blockchain/blockchain_provider.dart';
import 'blockchain/network_config.dart';
import 'key_storage/key_storage_backend.dart';
import 'key_storage/phone_secure_vault.dart';
import 'key_storage/secure_key_value_store.dart';
import 'transactions/transaction_service.dart';

enum WalletFlowStage {
  loading,
  welcome,
  createWallet,
  importWallet,
  showSeed,
  biometricPrompt,
  locked,
  unlocked,
}

class WalletFlowScreen extends StatefulWidget {
  const WalletFlowScreen({
    required this.store,
    required this.blockchainProvider,
    required this.transactionService,
    required this.transactionBroadcaster,
    required this.nonceProvider,
    super.key,
  });

  final SecureKeyValueStore store;
  final BlockchainProvider blockchainProvider;
  final TransactionService transactionService;
  final TransactionBroadcaster transactionBroadcaster;
  final NonceProvider nonceProvider;

  @override
  State<WalletFlowScreen> createState() => _WalletFlowScreenState();
}

class _WalletFlowScreenState extends State<WalletFlowScreen> {
  late final PhoneSecureVault _vault;

  WalletFlowStage _stage = WalletFlowStage.loading;
  StoredWalletSummary? _summary;
  WalletMaterial? _material;
  String? _seedPhraseToShow;
  String? _errorMessage;
  bool _biometricsEnabled = false;

  @override
  void initState() {
    super.initState();
    _vault = PhoneSecureVault(store: widget.store);
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    final summary = await _vault.getWalletSummary();
    if (!mounted) {
      return;
    }

    setState(() {
      _summary = summary;
      _stage = summary == null
          ? WalletFlowStage.welcome
          : WalletFlowStage.locked;
    });
  }

  Future<void> _createWallet({required String pin}) async {
    await _runGuarded(() async {
      final material = await _vault.createWallet(pin: pin);
      _summary = StoredWalletSummary(
        address: material.address,
        backendId: _vault.backendId,
        createdAtUtc: DateTime.now().toUtc(),
      );
      _material = material;
      _seedPhraseToShow = material.mnemonic;
      _stage = WalletFlowStage.showSeed;
    });
  }

  Future<void> _importWallet({
    required String mnemonic,
    required String pin,
  }) async {
    await _runGuarded(() async {
      final material = await _vault.importWallet(mnemonic: mnemonic, pin: pin);
      _summary = StoredWalletSummary(
        address: material.address,
        backendId: _vault.backendId,
        createdAtUtc: DateTime.now().toUtc(),
      );
      _material = material;
      _seedPhraseToShow = null;
      _stage = WalletFlowStage.biometricPrompt;
    });
  }

  Future<void> _unlockWallet(String pin) async {
    await _runGuarded(() async {
      _material = await _vault.unlock(pin: pin);
      _stage = WalletFlowStage.unlocked;
    });
  }

  Future<void> _runGuarded(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = null;
      });
    } on VaultFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    }
  }

  void _goToWelcome() {
    setState(() {
      _errorMessage = null;
      _stage = WalletFlowStage.welcome;
    });
  }

  void _finishSeedBackup() {
    setState(() {
      _stage = WalletFlowStage.biometricPrompt;
    });
  }

  void _completeBiometricChoice(bool enabled) {
    _vault.lock();
    setState(() {
      _biometricsEnabled = enabled;
      _material = null;
      _seedPhraseToShow = null;
      _stage = WalletFlowStage.locked;
    });
  }

  void _lockWallet() {
    _vault.lock();
    setState(() {
      _material = null;
      _stage = WalletFlowStage.locked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(stage: _stage),
                      if (_errorMessage case final String message) ...[
                        const SizedBox(height: 20),
                        _ErrorBanner(message: message),
                      ],
                      const SizedBox(height: 24),
                      _buildStageBody(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStageBody() {
    switch (_stage) {
      case WalletFlowStage.loading:
        return const Center(child: CircularProgressIndicator());
      case WalletFlowStage.welcome:
        return _WelcomeStage(
          onCreatePressed: () {
            setState(() {
              _errorMessage = null;
              _stage = WalletFlowStage.createWallet;
            });
          },
          onImportPressed: () {
            setState(() {
              _errorMessage = null;
              _stage = WalletFlowStage.importWallet;
            });
          },
        );
      case WalletFlowStage.createWallet:
        return _PinSetupStage(
          title: 'Создать новый кошелёк',
          description:
              'Сначала задаём обязательный PIN. После этого приложение создаст seed-фразу и покажет её один раз для резервного сохранения.',
          actionLabel: 'Создать кошелёк',
          onSubmit: _createWallet,
          onBack: _goToWelcome,
        );
      case WalletFlowStage.importWallet:
        return _ImportWalletStage(
          onSubmit: _importWallet,
          onBack: _goToWelcome,
        );
      case WalletFlowStage.showSeed:
        return _SeedPhraseStage(
          mnemonic: _seedPhraseToShow ?? '',
          onContinue: _finishSeedBackup,
        );
      case WalletFlowStage.biometricPrompt:
        return _BiometricPromptStage(
          onSkip: () => _completeBiometricChoice(false),
          onEnable: () => _completeBiometricChoice(true),
        );
      case WalletFlowStage.locked:
        return _LockedStage(
          summary: _summary,
          biometricsEnabled: _biometricsEnabled,
          onUnlock: _unlockWallet,
        );
      case WalletFlowStage.unlocked:
        return _UnlockedStage(
          blockchainProvider: widget.blockchainProvider,
          transactionService: widget.transactionService,
          transactionBroadcaster: widget.transactionBroadcaster,
          nonceProvider: widget.nonceProvider,
          material: _material,
          summary: _summary,
          biometricsEnabled: _biometricsEnabled,
          onLock: _lockWallet,
        );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.stage});

  final WalletFlowStage stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            Icons.account_balance_wallet_outlined,
            size: 32,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Mobile Wallet Demo',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _descriptionFor(stage),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  String _descriptionFor(WalletFlowStage stage) {
    switch (stage) {
      case WalletFlowStage.loading:
        return 'Проверяю текущее состояние кошелька и подготавливаю onboarding shell.';
      case WalletFlowStage.welcome:
        return 'Следующий шаг после foundation: пользовательский onboarding flow с выбором create/import, обязательным PIN и дальнейшим переходом в lock/unlock shell.';
      case WalletFlowStage.createWallet:
        return 'Новый кошелёк начнётся с обязательного PIN, а затем приложение создаст seed-фразу и покажет её один раз.';
      case WalletFlowStage.importWallet:
        return 'Импортируем существующую seed-фразу, задаём PIN и переводим приложение в тот же защищённый shell, что и для нового кошелька.';
      case WalletFlowStage.showSeed:
        return 'Это одноразовый экран резервного сохранения seed-фразы. После закрытия приложения seed больше не должен показываться в открытом виде.';
      case WalletFlowStage.biometricPrompt:
        return 'После PIN можно разрешить биометрию как удобный путь разблокировки. На этом этапе это пока продуктовый shell, без нативной платформенной интеграции.';
      case WalletFlowStage.locked:
        return 'Кошелёк инициализирован, но заблокирован. Дальше доступ в приложение идёт через PIN, а позже сюда же добавится реальная биометрия.';
      case WalletFlowStage.unlocked:
        return 'Onboarding/auth shell готов. Теперь поверх него строим первый действительно полезный read-only wallet слой: баланс, токены, история и локальный кэш.';
    }
  }
}

class _WelcomeStage extends StatelessWidget {
  const _WelcomeStage({
    required this.onCreatePressed,
    required this.onImportPressed,
  });

  final VoidCallback onCreatePressed;
  final VoidCallback onImportPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Выбери стартовый сценарий'),
        const SizedBox(height: 12),
        const Text(
          'Сейчас приложение уже умеет держать secure vault foundation. Теперь добавляем человеческий входной сценарий: создать новый кошелёк или импортировать существующий.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onCreatePressed,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Создать новый кошелёк'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onImportPressed,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Импортировать seed-фразу'),
        ),
      ],
    );
  }
}

class _PinSetupStage extends StatefulWidget {
  const _PinSetupStage({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onSubmit,
    required this.onBack,
  });

  final String title;
  final String description;
  final String actionLabel;
  final Future<void> Function({required String pin}) onSubmit;
  final VoidCallback onBack;

  @override
  State<_PinSetupStage> createState() => _PinSetupStageState();
}

class _PinSetupStageState extends State<_PinSetupStage> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (pin.length < 4) {
      setState(() {
        _localError = 'PIN должен быть не короче 4 символов.';
      });
      return;
    }

    if (pin != confirmPin) {
      setState(() {
        _localError = 'PIN и подтверждение не совпадают.';
      });
      return;
    }

    setState(() {
      _localError = null;
    });
    await widget.onSubmit(pin: pin);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(widget.title),
        const SizedBox(height: 12),
        Text(widget.description),
        const SizedBox(height: 20),
        TextField(
          controller: _pinController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'PIN',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPinController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Подтверждение PIN',
            border: OutlineInputBorder(),
          ),
        ),
        if (_localError case final String message) ...[
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: _handleSubmit,
              child: Text(widget.actionLabel),
            ),
            TextButton(onPressed: widget.onBack, child: const Text('Назад')),
          ],
        ),
      ],
    );
  }
}

class _ImportWalletStage extends StatefulWidget {
  const _ImportWalletStage({required this.onSubmit, required this.onBack});

  final Future<void> Function({required String mnemonic, required String pin})
  onSubmit;
  final VoidCallback onBack;

  @override
  State<_ImportWalletStage> createState() => _ImportWalletStageState();
}

class _ImportWalletStageState extends State<_ImportWalletStage> {
  final _mnemonicController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _mnemonicController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final mnemonic = _mnemonicController.text.trim();
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (mnemonic.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length <
        12) {
      setState(() {
        _localError =
            'Похоже, seed-фраза неполная. Ожидаю как минимум 12 слов.';
      });
      return;
    }

    if (pin.length < 4) {
      setState(() {
        _localError = 'PIN должен быть не короче 4 символов.';
      });
      return;
    }

    if (pin != confirmPin) {
      setState(() {
        _localError = 'PIN и подтверждение не совпадают.';
      });
      return;
    }

    setState(() {
      _localError = null;
    });
    await widget.onSubmit(mnemonic: mnemonic, pin: pin);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Импорт существующего кошелька'),
        const SizedBox(height: 12),
        const Text(
          'Вставь свою seed-фразу, затем задай локальный PIN для защиты secure vault на устройстве.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _mnemonicController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Seed-фраза',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pinController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'PIN',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPinController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Подтверждение PIN',
            border: OutlineInputBorder(),
          ),
        ),
        if (_localError case final String message) ...[
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: _handleSubmit,
              child: const Text('Импортировать кошелёк'),
            ),
            TextButton(onPressed: widget.onBack, child: const Text('Назад')),
          ],
        ),
      ],
    );
  }
}

class _SeedPhraseStage extends StatelessWidget {
  const _SeedPhraseStage({required this.mnemonic, required this.onContinue});

  final String mnemonic;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Сохраните seed-фразу'),
        const SizedBox(height: 12),
        const Text(
          'Это единственный момент, когда приложение показывает seed в открытом виде. Сохрани её офлайн и не отправляй в мессенджеры или облака.',
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            mnemonic,
            style: theme.textTheme.titleMedium?.copyWith(height: 1.5),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onContinue,
          child: const Text('Я сохранил seed-фразу'),
        ),
      ],
    );
  }
}

class _BiometricPromptStage extends StatelessWidget {
  const _BiometricPromptStage({required this.onSkip, required this.onEnable});

  final VoidCallback onSkip;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Биометрия после PIN'),
        const SizedBox(height: 12),
        const Text(
          'По продуктовой модели биометрия включается только после задания PIN и остаётся удобным способом разблокировки. Нативную платформенную интеграцию добавим позже, а сейчас фиксируем пользовательский выбор в shell flow.',
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onEnable,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Включить биометрию'),
            ),
            OutlinedButton(
              onPressed: onSkip,
              child: const Text('Пока без биометрии'),
            ),
          ],
        ),
      ],
    );
  }
}

class _LockedStage extends StatefulWidget {
  const _LockedStage({
    required this.summary,
    required this.biometricsEnabled,
    required this.onUnlock,
  });

  final StoredWalletSummary? summary;
  final bool biometricsEnabled;
  final Future<void> Function(String pin) onUnlock;

  @override
  State<_LockedStage> createState() => _LockedStageState();
}

class _LockedStageState extends State<_LockedStage> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Кошелёк заблокирован'),
        const SizedBox(height: 12),
        const Text(
          'Инициализация завершена. Дальше в кошелёк входим через PIN. Это и есть нужный locked-state shell для следующего продуктового слоя.',
        ),
        if (summary != null) ...[
          const SizedBox(height: 20),
          _SummaryTile(label: 'Адрес', value: summary.address),
          const SizedBox(height: 10),
          _SummaryTile(label: 'Backend', value: summary.backendId),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            const _StatusChip(label: 'Locked'),
            if (widget.biometricsEnabled)
              const _StatusChip(label: 'Biometrics enabled'),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _pinController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'PIN для разблокировки',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => widget.onUnlock(_pinController.text.trim()),
          child: const Text('Разблокировать'),
        ),
      ],
    );
  }
}

class _UnlockedStage extends StatefulWidget {
  const _UnlockedStage({
    required this.blockchainProvider,
    required this.transactionService,
    required this.transactionBroadcaster,
    required this.nonceProvider,
    required this.material,
    required this.summary,
    required this.biometricsEnabled,
    required this.onLock,
  });

  final BlockchainProvider blockchainProvider;
  final TransactionService transactionService;
  final TransactionBroadcaster transactionBroadcaster;
  final NonceProvider nonceProvider;
  final WalletMaterial? material;
  final StoredWalletSummary? summary;
  final bool biometricsEnabled;
  final VoidCallback onLock;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Read-only wallet foundation'),
        const SizedBox(height: 12),
        const Text(
          'Сейчас кошелёк уже умеет читать сеть и готовить перевод. Следующий шаг — нормальный signing/send flow с понятными состояниями отправки, а не немая магия в фоне.',
        ),
        const SizedBox(height: 20),
        _SummaryTile(label: 'Активный адрес', value: address),
        const SizedBox(height: 10),
        _SummaryTile(
          label: 'Биометрия',
          value: widget.biometricsEnabled
              ? 'Включена в shell-flow'
              : 'Пока выключена',
        ),
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
            walletMaterial: widget.material,
            transactionService: widget.transactionService,
            transactionBroadcaster: widget.transactionBroadcaster,
            nonceProvider: widget.nonceProvider,
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
    required this.walletMaterial,
    required this.transactionService,
    required this.transactionBroadcaster,
    required this.nonceProvider,
  });

  final WalletChainSnapshot snapshot;
  final String fromAddress;
  final EvmNetworkConfig networkConfig;
  final WalletMaterial? walletMaterial;
  final TransactionService transactionService;
  final TransactionBroadcaster transactionBroadcaster;
  final NonceProvider nonceProvider;

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
  String? _error;
  bool _isSubmitting = false;

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
        _error = null;
      });
    } on TransactionFailure catch (error) {
      setState(() {
        _preview = null;
        _loadedNonce = null;
        _signedTransfer = null;
        _submittedTransfer = null;
        _error = error.message;
      });
    }
  }

  Future<void> _signAndSubmit() async {
    final asset = _selectedAsset;
    final walletMaterial = widget.walletMaterial;
    if (asset == null || walletMaterial == null) {
      setState(() {
        _error = 'Кошелёк не разблокирован для подписания.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
      _loadedNonce = null;
      _signedTransfer = null;
      _submittedTransfer = null;
    });

    try {
      final preparedTransfer = widget.transactionService.prepareTransfer(
        snapshot: widget.snapshot,
        fromAddress: widget.fromAddress,
        toAddress: _addressController.text,
        amountText: _amountController.text,
        asset: asset,
      );
      final loadedNonce = await widget.nonceProvider.loadNextNonce(
        networkConfig: widget.networkConfig,
        address: widget.fromAddress,
      );
      final signedTransfer = widget.transactionService.signPreparedTransfer(
        preparedTransfer: preparedTransfer,
        walletMaterial: walletMaterial,
        nonce: loadedNonce.nonce,
      );
      final submittedTransfer = await widget.transactionService
          .submitSignedTransfer(
            signedTransfer: signedTransfer,
            broadcaster: widget.transactionBroadcaster,
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _preview = preparedTransfer.preview;
        _loadedNonce = loadedNonce;
        _signedTransfer = signedTransfer;
        _submittedTransfer = submittedTransfer;
        _error = null;
      });
    } on TransactionFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } finally {
      if (mounted) {
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
          'Это добор Phase 6: preview остаётся, но теперь поверх него есть реальная последовательность prepare → nonce → sign → submit с явным результатом на экране.',
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
                'Идёт операция: получаем nonce, подписываем локально и отправляем raw transaction в RPC.',
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
        ],
      ],
    );
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label), visualDensity: VisualDensity.compact);
  }
}
