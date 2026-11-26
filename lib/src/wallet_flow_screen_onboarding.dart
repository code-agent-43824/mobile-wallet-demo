part of 'wallet_flow_screen.dart';

class _WelcomeStage extends StatelessWidget {
  const _WelcomeStage({
    required this.controller,
    required this.backendEntries,
    required this.isRutokenSelected,
    required this.onBackendSelected,
    required this.onCreatePressed,
    required this.onImportPressed,
    required this.onRutokenDiagnostic,
    required this.onRutokenCreate,
    required this.onRutokenImport,
    required this.onRutokenAdopt,
    required this.rutokenDiagnosticResult,
    required this.rutokenProvisioningResult,
  });

  /// Drives the card operations' confirmation sheet.
  final WalletFlowController controller;
  final List<WalletBackendCatalogEntry> backendEntries;
  final bool isRutokenSelected;
  final Future<void> Function(String backendId) onBackendSelected;
  final VoidCallback onCreatePressed;
  final VoidCallback onImportPressed;
  final Future<void> Function(String pin)? onRutokenDiagnostic;
  final VoidCallback? onRutokenCreate;
  final VoidCallback? onRutokenImport;
  final Future<void> Function({required String pin})? onRutokenAdopt;
  final String? rutokenDiagnosticResult;
  final String? rutokenProvisioningResult;

  /// The phone vault's id, from the catalogue rather than a literal.
  String get _phoneBackendId => backendEntries
      .firstWhere(
        (entry) => entry.descriptor.kind == WalletBackendKind.phoneSecureVault,
      )
      .descriptor
      .id;

  /// The card backend's id, or null when no hardware backend is available on
  /// this platform.
  String? get _cardBackendId {
    for (final entry in backendEntries) {
      if (entry.descriptor.kind == WalletBackendKind.externalDevice) {
        return entry.descriptor.id;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Onboarding variant B ("Кошелёк за минуту"), the owner's choice: make
        // a phone wallet immediately and offer the card as a later upgrade,
        // rather than opening with a storage-backend question most people
        // cannot answer yet. The backend is chosen by which button is pressed,
        // so there is no separate picker on this screen.
        _SectionTitle(l10n.welcomeTitle),
        const SizedBox(height: 12),
        Text(l10n.welcomeBody),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () async {
            await onBackendSelected(_phoneBackendId);
            onCreatePressed();
          },
          icon: const Icon(Icons.add_circle_outline),
          label: Text(l10n.welcomeCreate),
        ),
        const SizedBox(height: 12),
        if (_cardBackendId case final String cardBackendId)
          OutlinedButton.icon(
            onPressed: isRutokenSelected
                ? null
                : () => onBackendSelected(cardBackendId),
            icon: const Icon(Icons.nfc_outlined),
            label: Text(l10n.welcomeHaveCard),
          )
        else
          const _CardsUnsupportedNote(),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            await onBackendSelected(_phoneBackendId);
            onImportPressed();
          },
          icon: const Icon(Icons.download_outlined),
          label: Text(l10n.welcomeImportSeed),
        ),
        // Progressive disclosure: the card's own actions appear only after the
        // user says they have one. Variant B's first screen stays short.
        if (onRutokenDiagnostic != null && isRutokenSelected) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          _SectionTitle(l10n.cardSectionTitle),
          const SizedBox(height: 8),
          Text(l10n.cardSectionBody),
          const SizedBox(height: 12),
          _CardActions(
            controller: controller,
            onCreate: onRutokenCreate,
            onImport: onRutokenImport,
            onAdopt: onRutokenAdopt,
            onDiagnostic: onRutokenDiagnostic,
            diagnosticResult: rutokenDiagnosticResult,
            provisioningResult: rutokenProvisioningResult,
          ),
        ],
      ],
    );
  }
}

/// The card's own actions: write a new key, import a seed, connect a card that
/// already holds one, or check that a card answers. Shared by onboarding and
/// the add-card screen, so both offer the same three ways in.
class _CardActions extends StatelessWidget {
  const _CardActions({
    required this.controller,
    required this.onCreate,
    required this.onImport,
    required this.onAdopt,
    required this.onDiagnostic,
    required this.diagnosticResult,
    required this.provisioningResult,
  });

  final WalletFlowController controller;
  final VoidCallback? onCreate;
  final VoidCallback? onImport;
  final Future<void> Function({required String pin})? onAdopt;
  final Future<void> Function(String pin)? onDiagnostic;
  final String? diagnosticResult;
  final String? provisioningResult;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final adopt = onAdopt;
    final diagnostic = onDiagnostic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_card),
              label: Text(l10n.cardCreate),
            ),
            OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.download),
              label: Text(l10n.cardImport),
            ),
            OutlinedButton.icon(
              onPressed: adopt == null
                  ? null
                  : () => _confirmOperation(
                      context,
                      controller: controller,
                      reason: l10n.cardAdoptPinReason,
                      biometricsOffered: false,
                      run: (pin, _) => adopt(pin: pin ?? ''),
                      successBody: () =>
                          controller.rutokenProvisioningResult ??
                          l10n.cardConnectSuccess,
                    ),
              icon: const Icon(Icons.credit_card),
              label: Text(l10n.cardAdopt),
            ),
          ],
        ),
        if (diagnostic != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _confirmOperation(
              context,
              controller: controller,
              reason: l10n.cardCheckPinReason,
              biometricsOffered: false,
              run: (pin, _) => diagnostic(pin ?? ''),
              successBody: () => controller.rutokenDiagnosticResult ?? '',
            ),
            icon: const Icon(Icons.nfc),
            label: Text(l10n.cardCheck),
          ),
        ],
        if (diagnosticResult case final result?) ...[
          const SizedBox(height: 12),
          Text(result),
        ],
        if (provisioningResult case final result?) ...[
          const SizedBox(height: 12),
          Text(result),
        ],
      ],
    );
  }
}

/// «Новая карта»: adds a card to a phone that already holds a wallet.
///
/// Offers only the card's three ways in — never phone-vault creation, which
/// the welcome screen would have put one tap away from a wallet in use. The
/// active wallet stays as it is until a card is actually connected.
class _AddCardStage extends StatelessWidget {
  const _AddCardStage({required this.controller});

  final WalletFlowController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.addCardTitle),
        const SizedBox(height: 12),
        Text(l10n.addCardBody),
        const SizedBox(height: 20),
        _CardActions(
          controller: controller,
          onCreate: controller.goToRutokenCreate,
          onImport: controller.goToRutokenImport,
          onAdopt: controller.adoptExistingRutoken,
          onDiagnostic: controller.runRutokenTransportDiagnostic,
          diagnosticResult: controller.rutokenDiagnosticResult,
          provisioningResult: controller.rutokenProvisioningResult,
        ),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: controller.closeAddCard,
          icon: const Icon(Icons.arrow_back),
          label: Text(l10n.actionBack),
        ),
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
      final message = AppLocalizations.of(context).passphraseMismatch;
      setState(() {
        _localError = message;
      });
      return;
    }
    widget.onGenerate(passphrase: _passphraseController.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.cardCreateTitle),
        const SizedBox(height: 12),
        Text(l10n.cardCreateBody),
        const SizedBox(height: 20),
        TextField(
          controller: _passphraseController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.passphraseOptional,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.passphraseConfirm,
            border: const OutlineInputBorder(),
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
              child: Text(l10n.cardCreateAction),
            ),
            TextButton(onPressed: widget.onBack, child: Text(l10n.actionBack)),
          ],
        ),
      ],
    );
  }
}

class _RutokenImportStage extends StatefulWidget {
  const _RutokenImportStage({
    required this.controller,
    required this.onSubmit,
    required this.onBack,
  });

  final WalletFlowController controller;

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
    final l10n = AppLocalizations.of(context);
    final words = _mnemonicController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .length;
    if (!const <int>{12, 15, 18, 21, 24}.contains(words)) {
      setState(() {
        _localError = l10n.seedWordCountError;
      });
      return;
    }
    if (_passphraseController.text != _confirmController.text) {
      setState(() {
        _localError = l10n.passphraseMismatch;
      });
      return;
    }
    setState(() {
      _localError = null;
    });
    await _confirmOperation(
      context,
      controller: widget.controller,
      reason: l10n.cardWritePinReason,
      biometricsOffered: false,
      run: (pin, _) => widget.onSubmit(
        mnemonic: _mnemonicController.text,
        passphrase: _passphraseController.text,
        pin: pin ?? '',
      ),
      successBody: () =>
          widget.controller.rutokenProvisioningResult ??
          l10n.cardConnectSuccess,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.cardImportTitle),
        const SizedBox(height: 12),
        Text(l10n.cardImportBody),
        const SizedBox(height: 20),
        TextField(
          controller: _mnemonicController,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: l10n.seedPhraseLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passphraseController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.passphraseOptional,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.passphraseConfirm,
            border: const OutlineInputBorder(),
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
              child: Text(l10n.cardImport),
            ),
            TextButton(onPressed: widget.onBack, child: Text(l10n.actionBack)),
          ],
        ),
      ],
    );
  }
}

class _RutokenBackupStage extends StatefulWidget {
  const _RutokenBackupStage({
    required this.controller,
    required this.backup,
    required this.onProvision,
    required this.onBack,
  });

  final WalletFlowController controller;
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
    final l10n = AppLocalizations.of(context);
    await _confirmOperation(
      context,
      controller: widget.controller,
      reason: l10n.cardWritePinReason,
      biometricsOffered: false,
      run: (pin, _) => widget.onProvision(pin: pin ?? ''),
      successBody: () =>
          widget.controller.rutokenProvisioningResult ??
          l10n.cardConnectSuccess,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasPassphrase = widget.backup.passphrase.isNotEmpty;
    final canContinue = _mnemonicSaved && (!hasPassphrase || _passphraseSaved);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.cardBackupTitle),
        const SizedBox(height: 12),
        Text(l10n.cardBackupBody),
        const SizedBox(height: 20),
        SelectableText(widget.backup.mnemonic),
        if (hasPassphrase) ...[
          const SizedBox(height: 16),
          Text(l10n.cardBackupPassphraseLabel),
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
          title: Text(l10n.cardBackupSavedWords),
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
            title: Text(l10n.cardBackupSavedPassphrase),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: canContinue ? _handleProvision : null,
              child: Text(l10n.cardBackupWrite),
            ),
            TextButton(
              onPressed: widget.onBack,
              child: Text(l10n.actionCancel),
            ),
          ],
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
    final l10n = AppLocalizations.of(context);
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (pin.length < 4) {
      setState(() {
        _localError = l10n.pinTooShort;
      });
      return;
    }

    if (pin != confirmPin) {
      setState(() {
        _localError = l10n.pinMismatch;
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
    final l10n = AppLocalizations.of(context);
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
          decoration: InputDecoration(
            labelText: l10n.pinLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPinController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.pinConfirmLabel,
            border: const OutlineInputBorder(),
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
            TextButton(onPressed: widget.onBack, child: Text(l10n.actionBack)),
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
    final l10n = AppLocalizations.of(context);
    final mnemonic = _mnemonicController.text.trim();
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (mnemonic.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length <
        12) {
      setState(() {
        _localError = l10n.seedTooShortError;
      });
      return;
    }

    if (pin.length < 4) {
      setState(() {
        _localError = l10n.pinTooShort;
      });
      return;
    }

    if (pin != confirmPin) {
      setState(() {
        _localError = l10n.pinMismatch;
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.importWalletTitle),
        const SizedBox(height: 12),
        Text(l10n.importWalletBody),
        const SizedBox(height: 20),
        TextField(
          controller: _mnemonicController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: l10n.seedPhraseLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pinController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.pinLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPinController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.pinConfirmLabel,
            border: const OutlineInputBorder(),
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
              child: Text(l10n.importWalletAction),
            ),
            TextButton(onPressed: widget.onBack, child: Text(l10n.actionBack)),
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
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.seedStageTitle),
        const SizedBox(height: 12),
        Text(l10n.seedStageBody),
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
        FilledButton(onPressed: onContinue, child: Text(l10n.seedStageAction)),
      ],
    );
  }
}

class _BiometricPromptStage extends StatelessWidget {
  const _BiometricPromptStage({
    required this.isAvailable,
    required this.isSimulated,
    required this.onSkip,
    required this.onEnable,
  });

  final bool isAvailable;
  final bool isSimulated;
  final VoidCallback onSkip;
  final VoidCallback? onEnable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final description = isSimulated
        ? l10n.biometricsBodySimulated
        : isAvailable
        ? l10n.biometricsBodyAvailable
        : l10n.biometricsBodyUnavailable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.biometricsTitle),
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
                isSimulated
                    ? l10n.biometricsEnableSimulated
                    : l10n.biometricsEnable,
              ),
            ),
            OutlinedButton(onPressed: onSkip, child: Text(l10n.biometricsSkip)),
          ],
        ),
      ],
    );
  }
}

/// The lock screen: the wallet it opens, and the PIN keypad, on a screen of
/// its own rather than in the onboarding card. Everything fits the window at
/// the default text size — beside each other when the window is wide and low,
/// one above the other otherwise — and scrolls only when larger text needs it.
class _LockedStage extends StatelessWidget {
  const _LockedStage({
    required this.summary,
    required this.backendLabel,
    required this.isExternalBackend,
    required this.biometricsEnabled,
    required this.errorMessage,
    required this.onUnlock,
    required this.onUnlockWithBiometrics,
  });

  final StoredWalletSummary? summary;
  final String backendLabel;
  final bool isExternalBackend;
  final bool biometricsEnabled;
  final String? errorMessage;
  final Future<void> Function(String pin) onUnlock;
  final Future<void> Function()? onUnlockWithBiometrics;

  /// Lower than this, the prompt and the keypad no longer fit one above the
  /// other, so a window with the width for it puts them side by side.
  static const double _stackedMinHeight = 640;

  /// Of the content, inside the margins: a closed iPhone Duo on its side
  /// leaves 554 pt, which holds both halves.
  static const double _sideBySideMinWidth = 480;

  /// Lower than this, a column of full-height keys would push the button out
  /// of the window.
  static const double _fullKeysMinHeight = 680;
  static const double _compactKeyHeight = 48;

  /// The unlock button under the keypad, for the fit check.
  static const double _buttonHeight = 48;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final summary = this.summary;
    final biometrics = onUnlockWithBiometrics;
    final errorMessage = this.errorMessage;

    final identity = Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            isExternalBackend
                ? Icons.credit_card_outlined
                : Icons.account_balance_wallet_outlined,
            size: 24,
            color: theme.colorScheme.primary,
          ),
        ),
        if (summary != null) ...[
          const SizedBox(height: NocturneSpacing.x3),
          Text(
            '$backendLabel · ${_shortLockAddress(summary.address)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.nocturne.textMuted,
            ),
          ),
        ],
      ],
    );

    // The window's middle is measured on the whole screen area, whose place
    // does not depend on the content laid out in it.
    return _WindowMiddle(
      builder: (context, middle) => LayoutBuilder(
        builder: (context, constraints) {
          const padding = NocturneSpacing.gutter;
          final width = constraints.maxWidth - 2 * padding;
          final height = constraints.maxHeight - 2 * padding;
          final sideBySide =
              width >= _sideBySideMinWidth && height < _stackedMinHeight;
          final keyHeight = !sideBySide && height < _fullKeysMinHeight
              ? _compactKeyHeight
              : _PinKeypad.defaultKeyHeight;
          // In a tall window the keypad goes below the window's middle — the
          // fold of an open iPhone Duo held upright — when it still fits there;
          // the content then starts at the top, so the middle stays put.
          const gap = _PinEntryPanel.middleGap;
          final keypadBlock =
              4 * (keyHeight + NocturneSpacing.x3) +
              NocturneSpacing.x6 +
              _buttonHeight;
          final middleY = middle == null ? null : middle.dy - padding;
          final splitAtY =
              !sideBySide &&
                  middleY != null &&
                  middleY - gap / 2 >= 0 &&
                  middleY + gap / 2 + keypadBlock <= height
              ? middleY
              : null;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(padding),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height < 0 ? 0 : height),
              child: Align(
                alignment: splitAtY == null
                    ? Alignment.center
                    : Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (errorMessage != null) ...[
                        _ErrorBanner(message: errorMessage),
                        const SizedBox(height: NocturneSpacing.x6),
                      ],
                      // The same keypad as every signature: the PIN never reaches
                      // the system keyboard. For a card the PIN is the card's,
                      // and the tap follows.
                      _PinEntryPanel(
                        leading: identity,
                        sideBySide: sideBySide,
                        keyHeight: keyHeight,
                        splitAtY: splitAtY,
                        title: isExternalBackend
                            ? l10n.lockedTitleCard
                            : l10n.lockedTitlePhone,
                        reason: isExternalBackend
                            ? l10n.lockedBodyCard
                            : l10n.lockedBodyPhone,
                        confirmLabel: isExternalBackend
                            ? l10n.lockedUnlockCard
                            : l10n.lockedUnlockPhone,
                        biometricsOffered: biometrics != null,
                        onPin: onUnlock,
                        onBiometrics: () => biometrics?.call(),
                        onCancel: null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// `0x928c54…6cab1`: enough of the address to recognise the wallet.
String _shortLockAddress(String address) {
  if (address.length <= 14) {
    return address;
  }
  return '${address.substring(0, 8)}…${address.substring(address.length - 6)}';
}
