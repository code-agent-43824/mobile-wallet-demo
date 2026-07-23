part of 'wallet_flow_screen.dart';

class _WelcomeStage extends StatelessWidget {
  const _WelcomeStage({
    required this.backendEntries,
    required this.selectedBackendId,
    required this.isExternalBackendSelected,
    required this.isRutokenSelected,
    required this.onBackendSelected,
    required this.onCreatePressed,
    required this.onImportPressed,
    required this.onRutokenDiagnostic,
    required this.onRutokenCreate,
    required this.onRutokenImport,
    required this.rutokenDiagnosticResult,
    required this.rutokenProvisioningResult,
  });

  final List<WalletBackendCatalogEntry> backendEntries;
  final String selectedBackendId;
  final bool isExternalBackendSelected;
  final bool isRutokenSelected;
  final Future<void> Function(String backendId) onBackendSelected;
  final VoidCallback onCreatePressed;
  final VoidCallback onImportPressed;
  final Future<void> Function(String pin)? onRutokenDiagnostic;
  final VoidCallback? onRutokenCreate;
  final VoidCallback? onRutokenImport;
  final String? rutokenDiagnosticResult;
  final String? rutokenProvisioningResult;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Выбери стартовый сценарий'),
        const SizedBox(height: 12),
        const Text(
          'Выбери локальный phone vault, учебный demo backend или настоящий '
          'Rutoken NFC. Активный backend определяет, где хранится ключ и как '
          'подтверждается каждая подпись.',
        ),
        const SizedBox(height: 20),
        _BackendSelectionCard(
          entries: backendEntries,
          selectedBackendId: selectedBackendId,
          onSelected: onBackendSelected,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onCreatePressed,
          icon: Icon(
            isExternalBackendSelected
                ? Icons.nfc_outlined
                : Icons.add_circle_outline,
          ),
          label: Text(
            isRutokenSelected
                ? 'Создать кошелёк на Рутокене'
                : isExternalBackendSelected
                ? 'Подключить demo NFC-устройство'
                : 'Создать новый кошелёк',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onImportPressed,
          icon: Icon(
            isExternalBackendSelected
                ? Icons.memory_outlined
                : Icons.download_outlined,
          ),
          label: Text(
            isRutokenSelected
                ? 'Импортировать seed в Рутокен'
                : isExternalBackendSelected
                ? 'Импортировать seed в demo device'
                : 'Импортировать seed-фразу',
          ),
        ),
        if (onRutokenDiagnostic != null) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          const _SectionTitle('Физический Рутокен'),
          const SizedBox(height: 8),
          const Text(
            'Android-контур NFC/PIN/публичного адреса/сырой подписи проверен '
            'на физическом устройстве. Для нового кошелька сначала сохрани '
            '24 слова и опциональную passphrase; импорт принимает существующий '
            'BIP-39 backup. Запись разрешена только на пустой Рутокен.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: onRutokenCreate,
                icon: const Icon(Icons.add_card),
                label: const Text('Создать на Рутокене'),
              ),
              OutlinedButton.icon(
                onPressed: onRutokenImport,
                icon: const Icon(Icons.download),
                label: const Text('Импортировать в Рутокен'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final auth = await _promptForAuth(
                context,
                reason:
                    'Введите PIN Рутокена и удерживайте устройство у NFC до завершения проверки.',
                biometricsOffered: false,
              );
              final pin = auth?.pin;
              if (pin != null) await onRutokenDiagnostic!(pin);
            },
            icon: const Icon(Icons.nfc),
            label: const Text('Проверить настоящий Рутокен'),
          ),
          if (rutokenDiagnosticResult case final result?) ...[
            const SizedBox(height: 12),
            Text(result),
          ],
          if (rutokenProvisioningResult case final result?) ...[
            const SizedBox(height: 12),
            Text(result),
          ],
        ],
      ],
    );
  }
}

class _RutokenCreateStage extends StatefulWidget {
  const _RutokenCreateStage({required this.onGenerate, required this.onBack});

  final void Function({required String passphrase}) onGenerate;
  final VoidCallback onBack;

  @override
  State<_RutokenCreateStage> createState() => _RutokenCreateStageState();
}

class _RutokenCreateStageState extends State<_RutokenCreateStage> {
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _handleGenerate() {
    if (_passphraseController.text != _confirmController.text) {
      setState(() {
        _localError = 'Passphrase и подтверждение не совпадают.';
      });
      return;
    }
    widget.onGenerate(passphrase: _passphraseController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Новый кошелёк на Рутокене'),
        const SizedBox(height: 12),
        const Text(
          'Приложение создаст 24 слова в памяти телефона. Passphrase '
          'необязательна, но если задать её, она становится обязательной '
          'частью backup: без неё те же 24 слова восстановят другой адрес.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _passphraseController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'BIP-39 passphrase (необязательно)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Подтверждение passphrase',
            border: OutlineInputBorder(),
          ),
        ),
        if (_localError case final message?) ...[
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
              onPressed: _handleGenerate,
              child: const Text('Создать резервную фразу'),
            ),
            TextButton(onPressed: widget.onBack, child: const Text('Назад')),
          ],
        ),
      ],
    );
  }
}

class _RutokenImportStage extends StatefulWidget {
  const _RutokenImportStage({required this.onSubmit, required this.onBack});

  final Future<void> Function({
    required String mnemonic,
    required String passphrase,
    required String pin,
  })
  onSubmit;
  final VoidCallback onBack;

  @override
  State<_RutokenImportStage> createState() => _RutokenImportStageState();
}

class _RutokenImportStageState extends State<_RutokenImportStage> {
  final _mnemonicController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _mnemonicController.dispose();
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final words = _mnemonicController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .length;
    if (!const <int>{12, 15, 18, 21, 24}.contains(words)) {
      setState(() {
        _localError =
            'BIP-39 seed-фраза должна содержать 12/15/18/21/24 слова.';
      });
      return;
    }
    if (_passphraseController.text != _confirmController.text) {
      setState(() {
        _localError = 'Passphrase и подтверждение не совпадают.';
      });
      return;
    }
    setState(() {
      _localError = null;
    });
    final auth = await _promptForAuth(
      context,
      reason:
          'Введите текущий PIN Рутокена и удерживайте пустую карту у NFC до завершения записи.',
      biometricsOffered: false,
    );
    final pin = auth?.pin;
    if (pin == null) return;
    await widget.onSubmit(
      mnemonic: _mnemonicController.text,
      passphrase: _passphraseController.text,
      pin: pin,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Импорт BIP-39 backup в Рутокен'),
        const SizedBox(height: 12),
        const Text(
          'Master key и chain code вычисляются программно и передаются '
          'Рутокену только во время этой операции. Passphrase нигде не '
          'сохраняется. Рутокен с существующим BIP-32 ключом будет отклонён.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _mnemonicController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Seed-фраза',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passphraseController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'BIP-39 passphrase (необязательно)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Подтверждение passphrase',
            border: OutlineInputBorder(),
          ),
        ),
        if (_localError case final message?) ...[
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
              child: const Text('Импортировать в Рутокен'),
            ),
            TextButton(onPressed: widget.onBack, child: const Text('Назад')),
          ],
        ),
      ],
    );
  }
}

class _RutokenBackupStage extends StatefulWidget {
  const _RutokenBackupStage({
    required this.backup,
    required this.onProvision,
    required this.onBack,
  });

  final RutokenGeneratedBackup backup;
  final Future<void> Function({required String pin}) onProvision;
  final VoidCallback onBack;

  @override
  State<_RutokenBackupStage> createState() => _RutokenBackupStageState();
}

class _RutokenBackupStageState extends State<_RutokenBackupStage> {
  bool _mnemonicSaved = false;
  bool _passphraseSaved = false;

  Future<void> _handleProvision() async {
    final auth = await _promptForAuth(
      context,
      reason:
          'Введите текущий PIN Рутокена и удерживайте пустую карту у NFC до завершения записи.',
      biometricsOffered: false,
    );
    final pin = auth?.pin;
    if (pin != null) await widget.onProvision(pin: pin);
  }

  @override
  Widget build(BuildContext context) {
    final hasPassphrase = widget.backup.passphrase.isNotEmpty;
    final canContinue = _mnemonicSaved && (!hasPassphrase || _passphraseSaved);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Сохрани backup до записи на Рутокен'),
        const SizedBox(height: 12),
        const Text(
          'Эти данные больше не будут показаны приложением. Сохрани их '
          'офлайн; потеря Рутокена без полного backup означает потерю средств.',
        ),
        const SizedBox(height: 20),
        SelectableText(widget.backup.mnemonic),
        if (hasPassphrase) ...[
          const SizedBox(height: 16),
          const Text('BIP-39 passphrase:'),
          SelectableText(widget.backup.passphrase),
        ],
        const SizedBox(height: 16),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _mnemonicSaved,
          onChanged: (value) {
            setState(() {
              _mnemonicSaved = value ?? false;
            });
          },
          title: const Text('Я сохранил все 24 слова офлайн'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (hasPassphrase)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _passphraseSaved,
            onChanged: (value) {
              setState(() {
                _passphraseSaved = value ?? false;
              });
            },
            title: const Text('Я отдельно сохранил passphrase'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: canContinue ? _handleProvision : null,
              child: const Text('Записать ключ на Рутокен'),
            ),
            TextButton(onPressed: widget.onBack, child: const Text('Отмена')),
          ],
        ),
      ],
    );
  }
}

class _BackendSelectionCard extends StatelessWidget {
  const _BackendSelectionCard({
    required this.entries,
    required this.selectedBackendId,
    required this.onSelected,
  });

  final List<WalletBackendCatalogEntry> entries;
  final String selectedBackendId;
  final Future<void> Function(String backendId) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Активное хранилище ключей'),
        const SizedBox(height: 12),
        for (final entry in entries) ...[
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: entry.descriptor.id == selectedBackendId
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.descriptor.label,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (entry.descriptor.isAvailable)
                        ChoiceChip(
                          selected: entry.descriptor.id == selectedBackendId,
                          label: Text(
                            entry.descriptor.id == selectedBackendId
                                ? 'Выбрано'
                                : 'Выбрать',
                          ),
                          onSelected: (_) => onSelected(entry.descriptor.id),
                        )
                      else
                        const Chip(label: Text('Скоро')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(entry.descriptor.description),
                  if (entry.descriptor.availabilityNote
                      case final String note) ...[
                    const SizedBox(height: 8),
                    Text(
                      note,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
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
  const _ImportWalletStage({
    required this.isExternalBackendSelected,
    required this.onSubmit,
    required this.onBack,
  });

  final bool isExternalBackendSelected;
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
        _SectionTitle(
          widget.isExternalBackendSelected
              ? 'Импорт seed в demo NFC-устройство'
              : 'Импорт существующего кошелька',
        ),
        const SizedBox(height: 12),
        Text(
          widget.isExternalBackendSelected
              ? 'Отдельная UX-ветка для внешнего backend: seed уходит в demo device runtime, а дальше операции идут как у внешнего подписанта.'
              : 'Вставь свою seed-фразу, затем задай локальный PIN для защиты secure vault на устройстве.',
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
              child: Text(
                widget.isExternalBackendSelected
                    ? 'Импортировать в устройство'
                    : 'Импортировать кошелёк',
              ),
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
  const _BiometricPromptStage({
    required this.isAvailable,
    required this.isWindowsSimulation,
    required this.onSkip,
    required this.onEnable,
  });

  final bool isAvailable;
  final bool isWindowsSimulation;
  final VoidCallback onSkip;
  final VoidCallback? onEnable;

  @override
  Widget build(BuildContext context) {
    final description = isWindowsSimulation
        ? 'На Windows здесь используется аккуратная имитация biometric unlock для demo-сценария. На мобильных платформах будет использоваться реальная системная биометрия.'
        : isAvailable
        ? 'По продуктовой модели биометрия включается только после задания PIN и остаётся удобным способом разблокировки. Здесь уже используется реальная системная биометрия, если устройство её поддерживает.'
        : 'На этом устройстве биометрия недоступна, поэтому продолжаем без неё. PIN остаётся обязательным способом разблокировки.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Биометрия после PIN'),
        const SizedBox(height: 12),
        Text(description),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onEnable,
              icon: const Icon(Icons.fingerprint),
              label: Text(
                isWindowsSimulation
                    ? 'Включить биометрию (имитация)'
                    : 'Включить биометрию',
              ),
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
    required this.backendLabel,
    required this.isExternalBackend,
    required this.externalRuntimeState,
    required this.biometricsEnabled,
    required this.onUnlock,
    required this.onUnlockWithBiometrics,
    required this.onReconnectExternalDevice,
    required this.onSimulateExternalOffline,
  });

  final StoredWalletSummary? summary;
  final String backendLabel;
  final bool isExternalBackend;
  final ExternalDeviceDemoRuntimeState? externalRuntimeState;
  final bool biometricsEnabled;
  final Future<void> Function(String pin) onUnlock;
  final Future<void> Function()? onUnlockWithBiometrics;
  final Future<void> Function()? onReconnectExternalDevice;
  final Future<void> Function()? onSimulateExternalOffline;

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
    final externalRuntimeState = widget.externalRuntimeState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          widget.isExternalBackend
              ? 'Внешнее устройство заблокировано'
              : 'Кошелёк заблокирован',
        ),
        const SizedBox(height: 12),
        Text(
          widget.isExternalBackend
              ? 'Demo device уже привязан. Дальше операции идут через PIN устройства и отдельный external-signer runtime path.'
              : 'Инициализация завершена. Дальше в кошелёк входим через PIN. Это и есть нужный locked-state shell для следующего продуктового слоя.',
        ),
        if (summary != null) ...[
          const SizedBox(height: 20),
          _SummaryTile(label: 'Адрес', value: summary.address),
          const SizedBox(height: 10),
          _SummaryTile(label: 'Backend', value: widget.backendLabel),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            const _StatusChip(label: 'Locked'),
            if (widget.biometricsEnabled)
              const _StatusChip(label: 'Biometrics enabled'),
            if (widget.isExternalBackend && externalRuntimeState != null)
              _StatusChip(
                label: externalRuntimeState.isAvailable
                    ? 'Device online'
                    : 'Device offline',
              ),
            if (widget.isExternalBackend &&
                externalRuntimeState?.lastError != null)
              const _StatusChip(label: 'Last error recorded'),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _pinController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: widget.isExternalBackend
                ? 'PIN устройства'
                : 'PIN для разблокировки',
            border: const OutlineInputBorder(),
          ),
        ),
        if (widget.isExternalBackend && externalRuntimeState != null) ...[
          const SizedBox(height: 16),
          _SummaryTile(
            label: 'Состояние demo device',
            value: externalRuntimeState.isAvailable ? 'Доступно' : 'Недоступно',
          ),
          if (externalRuntimeState.connectedAtUtc
              case final DateTime connectedAt) ...[
            const SizedBox(height: 10),
            _SummaryTile(
              label: 'Последняя device session',
              value: connectedAt.toIso8601String(),
            ),
          ],
          if (externalRuntimeState.lastError case final String error) ...[
            const SizedBox(height: 10),
            _ErrorBanner(message: error),
          ],
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: () => widget.onUnlock(_pinController.text.trim()),
              child: Text(
                widget.isExternalBackend
                    ? 'Подключить устройство'
                    : 'Разблокировать',
              ),
            ),
            if (widget.onUnlockWithBiometrics != null)
              OutlinedButton.icon(
                onPressed: widget.onUnlockWithBiometrics,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Разблокировать биометрией'),
              ),
            if (widget.onReconnectExternalDevice != null)
              OutlinedButton.icon(
                onPressed: widget.onReconnectExternalDevice,
                icon: const Icon(Icons.usb),
                label: const Text('Переподключить demo device'),
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

/// Per-operation auth prompt. Every private-key operation (send, approve a
/// WalletConnect request, sign an AirGap payload) collects a credential through
/// this modal — no session reuse. It pops itself (returning the credential)
/// BEFORE the caller runs the backend op, so a `pumpAndSettle` after invoking
/// the controller doesn't spin on an open sheet over the busy overlay.
Future<({String? pin, bool useBiometrics})?> _promptForAuth(
  BuildContext context, {
  required String reason,
  required bool biometricsOffered,
}) {
  return showModalBottomSheet<({String? pin, bool useBiometrics})>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _OperationAuthSheet(
      reason: reason,
      biometricsOffered: biometricsOffered,
    ),
  );
}

class _OperationAuthSheet extends StatefulWidget {
  const _OperationAuthSheet({
    required this.reason,
    required this.biometricsOffered,
  });

  final String reason;
  final bool biometricsOffered;

  @override
  State<_OperationAuthSheet> createState() => _OperationAuthSheetState();
}

class _OperationAuthSheetState extends State<_OperationAuthSheet> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _confirmPin() {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      return;
    }
    // Pop with the credential BEFORE the caller runs the backend op.
    Navigator.of(context).pop((pin: pin, useBiometrics: false));
  }

  void _confirmBiometrics() {
    Navigator.of(context).pop((pin: null, useBiometrics: true));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Подтвердите операцию'),
          const SizedBox(height: 12),
          Text(
            widget.reason,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _pinController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'PIN',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _confirmPin(),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _confirmPin,
                icon: const Icon(Icons.lock_open),
                label: const Text('Подтвердить'),
              ),
              if (widget.biometricsOffered)
                OutlinedButton.icon(
                  onPressed: _confirmBiometrics,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Разблокировать биометрией'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
