part of 'wallet_flow_screen.dart';

class _TonWalletPage extends StatefulWidget {
  const _TonWalletPage({
    required this.store,
    required this.biometricAuth,
    required this.adapter,
    required this.client,
  });

  final SecureKeyValueStore store;
  final BiometricAuthGateway biometricAuth;
  final RutokenNativeAdapter? adapter;
  final TonCenterClient? client;

  @override
  State<_TonWalletPage> createState() => _TonWalletPageState();
}

class _TonWalletPageState extends State<_TonWalletPage> {
  late final TonCenterClient _client;
  late final TonWalletController _wallet;
  late final Timer _poll;

  @override
  void initState() {
    super.initState();
    final adapter = widget.adapter;
    _client = widget.client ?? TonCenterClient();
    _wallet = TonWalletController(
      phone: PhoneTonVault(
        store: widget.store,
        biometricAuth: widget.biometricAuth,
        biometricPromptText: (prompt) =>
            biometricPromptText(AppLocalizations.of(context), prompt),
      ),
      card: adapter is RutokenTonAdapter
          ? RutokenTonVault(adapter: adapter, store: widget.store)
          : null,
      transfers: TonTransferService(client: _client, store: widget.store),
    );
    unawaited(_wallet.load());
    _poll = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!_wallet.refreshing && _wallet.awaitingTransfer) {
        unawaited(_wallet.refresh());
      }
    });
  }

  @override
  void dispose() {
    _poll.cancel();
    _wallet.dispose();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tonNetwork),
        actions: [
          ListenableBuilder(
            listenable: _wallet,
            builder: (context, _) => IconButton(
              onPressed: _wallet.selection == null || _wallet.refreshing
                  ? null
                  : _wallet.refresh,
              icon: const Icon(Icons.refresh),
              tooltip: l10n.actionRetry,
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _wallet,
        builder: (context, _) {
          if (_wallet.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final selected = _wallet.selection;
          final snapshot = _wallet.snapshot;
          return SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.all(NocturneSpacing.gutter),
                  children: [
                    if (_wallet.error case final Object failure)
                      _ErrorBanner(message: _tonError(l10n, failure)),
                    if (selected != null) ...[
                      DropdownButtonFormField<TonWalletSelection>(
                        key: ObjectKey(selected),
                        initialValue: selected,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.settingsKeyStorage,
                        ),
                        items: [
                          if (_wallet.phone case final TonWalletSelection phone)
                            DropdownMenuItem(
                              value: phone,
                              child: Text(l10n.tonPhone),
                            ),
                          for (final card in _wallet.cards)
                            DropdownMenuItem(
                              value: card,
                              child: Text(
                                '${l10n.tonCard} · ${card.account.address.substring(0, 12)}…',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) _wallet.select(value);
                        },
                      ),
                      const SizedBox(height: 20),
                      if (_wallet.refreshing) const LinearProgressIndicator(),
                      if (snapshot != null)
                        _BalanceHero(
                          amount: formatGram(snapshot.balance),
                          symbol: 'GRAM',
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _receive(selected),
                              child: Text(l10n.actionReceive),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed:
                                  snapshot == null || _wallet.awaitingTransfer
                                  ? null
                                  : () => _send(selected),
                              child: Text(l10n.actionSend),
                            ),
                          ),
                        ],
                      ),
                      if (snapshot?.lastSubmission
                          case final TonTransferStatus status)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(_tonStatus(l10n, status)),
                        ),
                      if (selected.card == null && _wallet.biometricsAvailable)
                        SwitchListTile(
                          title: Text(l10n.settingsBiometrics),
                          value: _wallet.biometricsEnabled,
                          onChanged: _biometrics,
                        ),
                      if (selected.card?.key.generatedOnCard == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(l10n.tonCardOnlyBackup),
                        ),
                      const SizedBox(height: 16),
                    ],
                    _setupActions(l10n),
                    if (snapshot != null) ...[
                      const SizedBox(height: 24),
                      _SectionTitle(l10n.tabActivity),
                      if (snapshot.activity.isEmpty) Text(l10n.activityEmpty),
                      for (final entry in snapshot.activity)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            entry.incoming
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                          ),
                          title: Text(
                            '${entry.incoming ? '+' : '−'}${formatGram(entry.amount)} GRAM',
                          ),
                          subtitle: Text(
                            entry.counterparty,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            MaterialLocalizations.of(
                              context,
                            ).formatShortDate(entry.time.toLocal()),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _setupActions(AppLocalizations l10n) => Wrap(
    spacing: 12,
    runSpacing: 8,
    children: [
      if (_wallet.phone == null) ...[
        OutlinedButton(
          onPressed: () => _setup(TonSetupMethod.phoneCreate),
          child: Text(l10n.tonCreatePhone),
        ),
        OutlinedButton(
          onPressed: () => _setup(TonSetupMethod.phoneImport),
          child: Text(l10n.tonImportPhone),
        ),
      ],
      if (_wallet.cardAvailable)
        PopupMenuButton<TonSetupMethod>(
          onSelected: _setup,
          itemBuilder: (_) => [
            for (final method in TonSetupMethod.values.where(
              (method) => method.usesCard,
            ))
              PopupMenuItem(
                value: method,
                child: Text(_tonSetupLabel(l10n, method)),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Text(l10n.tonCard),
          ),
        ),
    ],
  );

  void _setup(TonSetupMethod method) =>
      _tonShowSheet(context, _TonSetupSheet(wallet: _wallet, method: method));

  void _send(TonWalletSelection selected) => _tonShowSheet(
    context,
    _TonSendSheet(wallet: _wallet, selection: selected),
  );

  void _biometrics(bool enabled) => _tonShowSheet(
    context,
    _TonBiometricSheet(wallet: _wallet, enabled: enabled),
  );

  void _receive(TonWalletSelection selected) {
    final l10n = AppLocalizations.of(context);
    final address = selected.account.address;
    // TON's address is case-sensitive. The UR encoder uppercases its payloads.
    final matrix = Encoder.encode(address, ErrorCorrectionLevel.m).matrix!;
    _tonShowSheet(
      context,
      _TonSheet(
        title: l10n.receiveTitle,
        children: [
          Text(l10n.tonNetwork),
          SelectableText(address),
          Center(
            child: Semantics(
              image: true,
              label: l10n.receiveTitle,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: SizedBox.square(
                  dimension: 180,
                  child: CustomPaint(
                    painter: _QrPainter([
                      for (var y = 0; y < matrix.height; y++)
                        [
                          for (var x = 0; x < matrix.width; x++)
                            matrix.get(x, y) == 1,
                        ],
                    ]),
                  ),
                ),
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: address));
              if (!mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l10n.addressCopied)));
            },
            child: Text(l10n.actionCopyAddress),
          ),
        ],
      ),
    );
  }
}

void _tonShowSheet(BuildContext context, Widget content) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    isDismissible: false,
    backgroundColor: context.nocturne.surface,
    builder: (_) => content,
  );
}

class _TonSheet extends StatelessWidget {
  const _TonSheet({
    required this.title,
    required this.children,
    this.busy = false,
  });

  final String title;
  final List<Widget> children;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: !busy,
      child: _SheetSafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionTitle(title),
                  for (final child in children) ...[
                    const SizedBox(height: 12),
                    child,
                  ],
                  if (!busy)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.actionClose),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TonSetupSheet extends StatefulWidget {
  const _TonSetupSheet({required this.wallet, required this.method});

  final TonWalletController wallet;
  final TonSetupMethod method;

  @override
  State<_TonSetupSheet> createState() => _TonSetupSheetState();
}

class _TonSetupSheetState extends State<_TonSetupSheet> {
  final _phraseInput = TextEditingController();
  final _expectedAddress = TextEditingController();
  final _cardPin = TextEditingController();
  String? _phrase;
  bool _acknowledged = false;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.method.createsPhrase) unawaited(_generate());
  }

  Future<void> _generate() async {
    try {
      final phrase = await TonMnemonic.generate();
      if (mounted) setState(() => _phrase = phrase);
    } catch (failure) {
      if (mounted) setState(() => _error = failure);
    }
  }

  @override
  void dispose() {
    _phrase = null;
    _phraseInput.dispose();
    _expectedAddress.dispose();
    _cardPin.dispose();
    super.dispose();
  }

  Future<void> _submit({required String pin}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.wallet.setup(
        method: widget.method,
        phrase: _phrase ?? _phraseInput.text,
        pin: pin,
        expectedAddress: _expectedAddress.text,
      );
      if (!mounted) return;
      _phrase = null;
      _phraseInput.clear();
      _cardPin.clear();
      Navigator.of(context).pop();
    } catch (failure) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final method = widget.method;
    final phrase = _phrase;
    final generated = method.createsPhrase;
    final cardOnly = method == TonSetupMethod.cardGenerate;
    final canContinue = generated
        ? phrase != null && _acknowledged
        : !cardOnly || _acknowledged;
    return _TonSheet(
      title: _tonSetupLabel(l10n, method),
      busy: _busy,
      children: [
        Text(l10n.tonNetwork),
        if (generated && phrase == null && _error == null)
          const LinearProgressIndicator(),
        if (generated && phrase != null) ...[
          Text(l10n.tonSavePhrase),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              for (final (index, word) in phrase.split(' ').indexed)
                Text('${index + 1}. $word'),
            ],
          ),
          CheckboxListTile(
            title: Text(l10n.cardBackupSavedWords),
            value: _acknowledged,
            onChanged: _busy
                ? null
                : (value) => setState(() => _acknowledged = value!),
          ),
        ],
        if (method.usesPhrase && !generated) ...[
          Text(l10n.tonRestoreContract),
          TextField(
            controller: _phraseInput,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            maxLines: 4,
            decoration: InputDecoration(labelText: l10n.tonPhrase),
          ),
          TextField(
            controller: _expectedAddress,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: l10n.tonExpectedAddress),
          ),
        ],
        if (cardOnly) ...[
          Text(l10n.tonCardOnlyBackup),
          CheckboxListTile(
            title: Text(l10n.tonCardOnlyConfirm),
            value: _acknowledged,
            onChanged: _busy
                ? null
                : (value) => setState(() => _acknowledged = value!),
          ),
        ],
        if (_error case final Object failure)
          _ErrorBanner(message: _tonError(l10n, failure)),
        if (_busy) ...[
          const LinearProgressIndicator(),
          if (method.usesCard) ...[
            Text(l10n.tonTapCard),
            TextButton(
              onPressed: widget.wallet.cancelCardOperation,
              child: Text(l10n.busyCancelNfc),
            ),
          ],
        ] else if (canContinue)
          if (method.usesCard) ...[
            _tonPinField(_cardPin, l10n.errorEnterCardPin),
            FilledButton(
              onPressed: () => _submit(pin: _cardPin.text),
              child: Text(l10n.authConfirmAction),
            ),
          ] else
            _PinSetupStage(
              title: l10n.pinLabel,
              description: l10n.tonPhonePin,
              actionLabel: l10n.authConfirmAction,
              onSubmit: _submit,
              onBack: () => Navigator.of(context).pop(),
            ),
      ],
    );
  }
}

class _TonSendSheet extends StatefulWidget {
  const _TonSendSheet({required this.wallet, required this.selection});

  final TonWalletController wallet;
  final TonWalletSelection selection;

  @override
  State<_TonSendSheet> createState() => _TonSendSheetState();
}

class _TonSendSheetState extends State<_TonSendSheet> {
  final _recipient = TextEditingController();
  final _amount = TextEditingController();
  final _pin = TextEditingController();
  TonTransferQuote? _quote;
  bool _busy = false;
  bool _waitingCard = false;
  bool? _accepted;
  Object? _error;

  @override
  void dispose() {
    _recipient.dispose();
    _amount.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _prepare() => _run(() async {
    final quote = await widget.wallet.prepare(
      widget.selection,
      _recipient.text,
      _amount.text,
    );
    if (mounted) setState(() => _quote = quote);
  });

  Future<void> _submit(String? pin) => _run(() async {
    final accepted = await widget.wallet.submit(
      widget.selection,
      _quote!,
      pin: pin,
      onCardPrompt: (waiting) {
        if (mounted) setState(() => _waitingCard = waiting);
      },
    );
    if (mounted) {
      _pin.clear();
      setState(() => _accepted = accepted);
    }
  });

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
    } catch (failure) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) {
        _pin.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quote = _quote;
    final accepted = _accepted;
    return _TonSheet(
      title: quote == null ? l10n.transferTitle : l10n.transferReview,
      busy: _busy,
      children: [
        Text(l10n.tonNetwork),
        if (_error case final Object failure)
          _ErrorBanner(message: _tonError(l10n, failure)),
        if (accepted != null)
          Text(accepted ? l10n.tonSubmitted : l10n.tonSubmissionUncertain)
        else if (quote == null) ...[
          TextField(
            controller: _recipient,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: l10n.transferRecipientLabel),
          ),
          TextField(
            controller: _amount,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.transferAmount,
              suffixText: 'GRAM',
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _prepare,
            child: Text(l10n.transferPreviewAction),
          ),
        ] else ...[
          Text(l10n.transferRecipient),
          SelectableText(quote.destination),
          Text(l10n.wcAmountLine(formatGram(quote.amount), 'GRAM')),
          Text('${l10n.transferNetworkFee} · ${formatGram(quote.fee)} GRAM'),
          if (!_busy) ...[
            _tonPinField(
              _pin,
              widget.selection.card == null
                  ? l10n.pinLabel
                  : l10n.errorEnterCardPin,
            ),
            FilledButton(
              onPressed: () => _submit(_pin.text),
              child: Text(l10n.transferSignAndSend),
            ),
            if (widget.selection.card == null &&
                widget.wallet.biometricsEnabled)
              OutlinedButton(
                onPressed: () => _submit(null),
                child: Text(l10n.unlockWithBiometrics),
              ),
            TextButton(
              onPressed: () => setState(() {
                _quote = null;
                _error = null;
              }),
              child: Text(l10n.transferEdit),
            ),
          ],
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_waitingCard) ...[
          Text(l10n.tonTapCard),
          TextButton(
            onPressed: widget.wallet.cancelCardOperation,
            child: Text(l10n.busyCancelNfc),
          ),
        ],
      ],
    );
  }
}

class _TonBiometricSheet extends StatefulWidget {
  const _TonBiometricSheet({required this.wallet, required this.enabled});
  final TonWalletController wallet;
  final bool enabled;

  @override
  State<_TonBiometricSheet> createState() => _TonBiometricSheetState();
}

class _TonBiometricSheetState extends State<_TonBiometricSheet> {
  bool _busy = false;
  Object? _error;
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.wallet.setBiometrics(
        enabled: widget.enabled,
        pin: _pin.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (failure) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _TonSheet(
      title: l10n.settingsBiometrics,
      busy: _busy,
      children: [
        Text(l10n.tonNetwork),
        if (_error case final Object failure)
          _ErrorBanner(message: _tonError(l10n, failure)),
        if (_busy)
          const LinearProgressIndicator()
        else ...[
          if (widget.enabled) _tonPinField(_pin, l10n.pinLabel),
          FilledButton(onPressed: _apply, child: Text(l10n.authConfirmAction)),
        ],
      ],
    );
  }
}

Widget _tonPinField(TextEditingController controller, String label) =>
    TextField(
      controller: controller,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(labelText: label),
    );

String _tonError(AppLocalizations l10n, Object failure) =>
    failure is CodedError && failure.errorCode != null
    ? describeError(l10n, failure)
    : l10n.errTonApiUnavailable;

String _tonSetupLabel(AppLocalizations l10n, TonSetupMethod method) =>
    switch (method) {
      TonSetupMethod.phoneCreate => l10n.tonCreatePhone,
      TonSetupMethod.phoneImport => l10n.tonImportPhone,
      TonSetupMethod.cardCreate => l10n.tonCreateCard,
      TonSetupMethod.cardImport => l10n.tonImportCard,
      TonSetupMethod.cardGenerate => l10n.tonGenerateOnCard,
      TonSetupMethod.cardAdopt => l10n.tonAdoptCard,
    };

String _tonStatus(AppLocalizations l10n, TonTransferStatus status) =>
    switch (status) {
      TonTransferStatus.pending => l10n.errTonTransferPending,
      TonTransferStatus.confirmed => l10n.transferConfirmed,
      TonTransferStatus.failed => l10n.transferReverted,
      TonTransferStatus.unknown => l10n.transferPendingTimeout,
    };
