part of 'wallet_flow_screen.dart';

/// The Connections screen (Phase 9 chunk 9.4b): WalletConnect status, a
/// "new connection" `wc:` URI field, the incoming session-proposal approval
/// card, and the active-session list with disconnect. Driven by the
/// [WalletFlowController] WC seam (9.4a); works on the fake service until the
/// real `reown_walletkit` impl (9.2) lands.
class _ConnectionsStage extends StatefulWidget {
  const _ConnectionsStage({
    required this.isAvailable,
    required this.sessions,
    required this.pendingProposal,
    required this.pendingRequest,
    required this.pendingRequestPreview,
    required this.pendingRequestPreviewError,
    required this.isPendingRequestPreviewLoading,
    required this.airGapAccountExportPayload,
    required this.airGapRequest,
    required this.airGapRequestPreview,
    required this.airGapResponsePayload,
    required this.walletAddress,
    required this.isQrCameraAvailable,
    required this.isQrFileLoadAvailable,
    required this.canUnlockWithBiometrics,
    required this.onScanQrCamera,
    required this.onLoadQrFromFile,
    required this.onPair,
    required this.onApprove,
    required this.onReject,
    required this.onApproveRequest,
    required this.onRejectRequest,
    required this.onPrepareAirGapAccountExport,
    required this.onScanAirGapRequest,
    required this.onLoadAirGapRequest,
    required this.onSignAirGapRequest,
    required this.onClearAirGapRequest,
    required this.onDisconnect,
    required this.onBack,
  });

  final bool isAvailable;
  final List<WalletConnectSession> sessions;
  final WalletConnectSessionProposal? pendingProposal;
  final WalletConnectRequest? pendingRequest;
  final WalletConnectTransactionPreview? pendingRequestPreview;
  final String? pendingRequestPreviewError;
  final bool isPendingRequestPreviewLoading;
  final String? airGapAccountExportPayload;
  final EthSignRequest? airGapRequest;
  final Eip4527TransactionPreview? airGapRequestPreview;
  final String? airGapResponsePayload;
  final String? walletAddress;
  final bool isQrCameraAvailable;
  final bool isQrFileLoadAvailable;
  final bool canUnlockWithBiometrics;
  final Future<String?> Function({String title}) onScanQrCamera;
  final Future<String?> Function() onLoadQrFromFile;
  final Future<void> Function({required String uri}) onPair;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  // Private-key operations: the credential is collected per-op in this widget
  // and threaded to the controller. Reject/clear stay auth-free.
  final Future<void> Function({String? pin, bool useBiometrics})
  onApproveRequest;
  final Future<void> Function() onRejectRequest;
  final Future<void> Function({String? pin, bool useBiometrics})
  onPrepareAirGapAccountExport;
  final Future<void> Function() onScanAirGapRequest;
  final Future<void> Function() onLoadAirGapRequest;
  final Future<void> Function({String? pin, bool useBiometrics})
  onSignAirGapRequest;
  final VoidCallback onClearAirGapRequest;
  final Future<void> Function(String topic) onDisconnect;
  final VoidCallback onBack;

  @override
  State<_ConnectionsStage> createState() => _ConnectionsStageState();
}

class _ConnectionsStageState extends State<_ConnectionsStage> {
  final TextEditingController _uriController = TextEditingController();

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final uri = _uriController.text.trim();
    if (uri.isEmpty) {
      return;
    }
    await widget.onPair(uri: uri);
  }

  bool get _biometricsOffered => widget.canUnlockWithBiometrics;

  Future<void> _approveRequest() async {
    final l10n = AppLocalizations.of(context);
    const codec = WalletConnectV2RequestCodec();
    final request = widget.pendingRequest;
    if (request != null && codec.isChainSwitchMethod(request.method)) {
      // Chain switching changes the dApp context only; it must not unlock the
      // vault or ask for a PIN.
      await widget.onApproveRequest();
      return;
    }
    final credential = await _promptForAuth(
      context,
      reason: l10n.wcApproveNeedsKey,
      biometricsOffered: _biometricsOffered,
    );
    if (credential == null) {
      // User dismissed the auth sheet — abort silently, keep the request shown.
      return;
    }
    await widget.onApproveRequest(
      pin: credential.pin,
      useBiometrics: credential.useBiometrics,
    );
  }

  /// Which AirGap step the user is on, derived from state that already exists:
  /// a returned signature means step 3, a scanned request means step 2, and
  /// otherwise the pairing QR is still the task.
  int _airGapStep() {
    if (widget.airGapResponsePayload != null) {
      return 3;
    }
    if (widget.airGapRequest != null) {
      return 2;
    }
    return 1;
  }

  Future<void> _prepareAirGapAccountExport() async {
    final credential = await _promptForAuth(
      context,
      reason: AppLocalizations.of(context).wcExportPinReason,
      biometricsOffered: _biometricsOffered,
    );
    if (credential == null) {
      return;
    }
    await widget.onPrepareAirGapAccountExport(
      pin: credential.pin,
      useBiometrics: credential.useBiometrics,
    );
  }

  Future<void> _signAirGap() async {
    final credential = await _promptForAuth(
      context,
      reason: AppLocalizations.of(context).wcSignPinReason,
      biometricsOffered: _biometricsOffered,
    );
    if (credential == null) {
      return;
    }
    await widget.onSignAirGapRequest(
      pin: credential.pin,
      useBiometrics: credential.useBiometrics,
    );
  }

  Future<void> _fillFrom(
    TextEditingController controller,
    Future<String?> Function() source,
  ) async {
    final value = await source();
    if (value != null && mounted) {
      setState(() => controller.text = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final proposal = widget.pendingProposal;
    final request = widget.pendingRequest;
    final accountExport = widget.airGapAccountExportPayload;
    final airGapRequest = widget.airGapRequest;
    final airGapPreview = widget.airGapRequestPreview;
    final airGapResponse = widget.airGapResponsePayload;
    final sessions = widget.sessions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.wcSectionTitle),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusChip(
              label: widget.isAvailable
                  ? l10n.wcAvailable
                  : l10n.wcNotConfigured,
            ),
            _StatusChip(label: l10n.wcActiveSessionsCount(sessions.length)),
          ],
        ),
        const SizedBox(height: 24),
        _SectionTitle(l10n.wcNewConnection),
        const SizedBox(height: 8),
        Text(l10n.wcPasteUri),
        const SizedBox(height: 12),
        TextField(
          controller: _uriController,
          decoration: const InputDecoration(
            labelText: 'wc: URI',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: widget.isAvailable ? _pair : null,
              icon: const Icon(Icons.link),
              label: Text(l10n.wcPair),
            ),
            if (widget.isQrFileLoadAvailable)
              OutlinedButton.icon(
                onPressed: () =>
                    _fillFrom(_uriController, widget.onLoadQrFromFile),
                icon: const Icon(Icons.image_outlined),
                label: Text(l10n.wcLoadFromFile),
              ),
            if (widget.isQrCameraAvailable)
              OutlinedButton.icon(
                onPressed: () => _fillFrom(
                  _uriController,
                  () => widget.onScanQrCamera(title: 'wc: URI'),
                ),
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(l10n.wcScanCamera),
              ),
          ],
        ),
        if (proposal != null) ...[
          const SizedBox(height: 24),
          _ProposalCard(
            proposal: proposal,
            onApprove: widget.walletAddress == null ? null : widget.onApprove,
            onReject: widget.onReject,
          ),
        ],
        if (request != null) ...[
          const SizedBox(height: 24),
          _RequestCard(
            request: request,
            preview: widget.pendingRequestPreview,
            previewError: widget.pendingRequestPreviewError,
            isPreviewLoading: widget.isPendingRequestPreviewLoading,
            onApprove: _approveRequest,
            onReject: widget.onRejectRequest,
          ),
        ],
        const SizedBox(height: 24),
        _SectionTitle(l10n.wcActiveSessions),
        const SizedBox(height: 12),
        if (sessions.isEmpty)
          Text(
            l10n.wcNoSessions,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...sessions.map(
            (session) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SessionCard(
                session: session,
                onDisconnect: () => widget.onDisconnect(session.topic),
              ),
            ),
          ),
        const SizedBox(height: 24),
        _SectionTitle(l10n.airgapTitle),
        const SizedBox(height: 8),
        Text(l10n.airgapIntro),
        const SizedBox(height: 12),
        _AirGapProgress(currentStep: _airGapStep()),
        const SizedBox(height: 12),
        _AirGapStepCard(
          title: l10n.airgapStep1Title,
          stepNumber: 1,
          description: l10n.airgapStep1Body,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton.icon(
                onPressed: _prepareAirGapAccountExport,
                icon: const Icon(Icons.qr_code_2),
                label: Text(
                  accountExport == null
                      ? l10n.airgapShowAccountQr
                      : l10n.airgapRefreshAccountQr,
                ),
              ),
              if (accountExport != null) ...[
                const SizedBox(height: 12),
                _UrQrDisplay(
                  payload: accountExport,
                  semanticsLabel: l10n.airgapAccountQr,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _AirGapStepCard(
          title: l10n.airgapStep2Title,
          stepNumber: 2,
          description: l10n.airgapStep2Body,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (widget.isQrCameraAvailable)
                    FilledButton.icon(
                      onPressed: widget.onScanAirGapRequest,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(l10n.airgapScanRequest),
                    ),
                  if (widget.isQrFileLoadAvailable)
                    OutlinedButton.icon(
                      onPressed: widget.onLoadAirGapRequest,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(l10n.airgapLoadQrFile),
                    ),
                ],
              ),
              if (airGapRequest != null && airGapPreview != null) ...[
                const SizedBox(height: 16),
                _AirGapTransactionPreviewCard(
                  request: airGapRequest,
                  preview: airGapPreview,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _signAirGap,
                  icon: const Icon(Icons.draw),
                  label: Text(l10n.airgapSignTransaction),
                ),
              ],
            ],
          ),
        ),
        if (airGapResponse != null) ...[
          const SizedBox(height: 12),
          _AirGapStepCard(
            title: l10n.airgapStep3Title,
            stepNumber: 3,
            description: l10n.airgapStep3Body,
            child: _UrQrDisplay(
              payload: airGapResponse,
              semanticsLabel: l10n.airgapSignatureQr,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.onClearAirGapRequest,
            icon: const Icon(Icons.clear),
            label: Text(l10n.airgapNewTransaction),
          ),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back),
          label: Text(l10n.wcBackToWallet),
        ),
      ],
    );
  }
}

class _AirGapStepCard extends StatelessWidget {
  const _AirGapStepCard({
    required this.title,
    required this.stepNumber,
    required this.description,
    required this.child,
  });

  final String title;
  final int stepNumber;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: NocturneColors.accent800,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$stepNumber',
                  style: const TextStyle(
                    fontFamily: NocturneType.family,
                    fontSize: 12,
                    fontWeight: NocturneType.semibold,
                    color: NocturneColors.accent100,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(description),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _AirGapTransactionPreviewCard extends StatelessWidget {
  const _AirGapTransactionPreviewCard({
    required this.request,
    required this.preview,
  });

  final EthSignRequest request;
  final Eip4527TransactionPreview preview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.previewTitle),
        const SizedBox(height: 8),
        _SummaryTile(label: l10n.detailsNetwork, value: preview.networkLabel),
        _SummaryTile(
          label: l10n.previewType,
          value: preview.transactionTypeLabel,
        ),
        _SummaryTile(
          label: l10n.previewFrom,
          value: request.addressHex ?? request.derivationPath.toPathString(),
        ),
        _SummaryTile(
          label: l10n.previewTo,
          value: preview.toAddress ?? l10n.previewContractCreation,
        ),
        _SummaryTile(
          label: l10n.previewAmount,
          value: '${preview.valueEth} ETH',
        ),
        _SummaryTile(label: l10n.previewNonce, value: preview.nonce.toString()),
        _SummaryTile(
          label: l10n.previewGasLimit,
          value: preview.gasLimit.toString(),
        ),
        _SummaryTile(
          label: l10n.wcMaxFee,
          value: '${preview.maximumFeeEth} ETH',
        ),
        _SummaryTile(
          label: l10n.wcContractData,
          value: preview.dataLength == 0
              ? l10n.previewNone
              : l10n.previewContractDataValue(
                  preview.dataLength,
                  preview.selector ?? l10n.previewNone,
                ),
        ),
        if (request.origin != null)
          _SummaryTile(label: l10n.previewSource, value: request.origin!),
      ],
    );
  }
}

/// Static QR for small URs and a looping animated fountain sequence for larger
/// ones. QR contents are uppercased to use compact alphanumeric mode; BC-UR is
/// case-insensitive and camera intake normalizes it back to lowercase.
class _UrQrDisplay extends StatefulWidget {
  const _UrQrDisplay({required this.payload, required this.semanticsLabel});

  final String payload;
  final String semanticsLabel;

  @override
  State<_UrQrDisplay> createState() => _UrQrDisplayState();
}

class _UrQrDisplayState extends State<_UrQrDisplay> {
  Timer? _timer;
  late List<String> _frames;
  var _index = 0;

  @override
  void initState() {
    super.initState();
    _configure();
  }

  @override
  void didUpdateWidget(covariant _UrQrDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload != widget.payload) {
      _configure();
    }
  }

  void _configure() {
    _timer?.cancel();
    _frames = const UrQrEncoder().encode(widget.payload);
    _index = 0;
    if (_frames.length > 1) {
      _timer = Timer.periodic(const Duration(milliseconds: 350), (_) {
        if (mounted) {
          setState(() => _index = (_index + 1) % _frames.length);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: widget.semanticsLabel,
      image: true,
      child: Column(
        children: [
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 280,
                child: CustomPaint(
                  painter: _QrPainter(_qrModules(_frames[_index])),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _frames.length == 1
                ? l10n.qrSingleFrame
                : l10n.qrFrameProgress(_index + 1, _frames.length),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<List<bool>> _qrModules(String frame) {
    final qr = Encoder.encode(frame.toUpperCase(), ErrorCorrectionLevel.m);
    final matrix = qr.matrix!;
    return List<List<bool>>.generate(
      matrix.height,
      (y) => List<bool>.generate(matrix.width, (x) => matrix.get(x, y) == 1),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.modules);

  final List<List<bool>> modules;

  @override
  void paint(Canvas canvas, Size size) {
    final dimension = modules.length;
    const quietZone = 4;
    final moduleSize = size.shortestSide / (dimension + quietZone * 2);
    final paint = Paint()..color = Colors.black;
    for (var y = 0; y < dimension; y++) {
      for (var x = 0; x < dimension; x++) {
        if (modules[y][x]) {
          canvas.drawRect(
            Rect.fromLTWH(
              (x + quietZone) * moduleSize,
              (y + quietZone) * moduleSize,
              moduleSize + 0.05,
              moduleSize + 0.05,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) =>
      oldDelegate.modules != modules;
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.onApprove,
    required this.onReject,
  });

  final WalletConnectSessionProposal proposal;
  final Future<void> Function()? onApprove;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.wcConnectionRequest,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(proposal.peer.name, style: theme.textTheme.bodyLarge),
          if (proposal.peer.url.isNotEmpty)
            Text(
              proposal.peer.url,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          Text(l10n.wcChains(proposal.requiredChains.join(', '))),
          Text(l10n.wcMethods(proposal.requiredMethods.join(', '))),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: onApprove, child: Text(l10n.wcApprove)),
              OutlinedButton(onPressed: onReject, child: Text(l10n.wcReject)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.preview,
    required this.previewError,
    required this.isPreviewLoading,
    required this.onApprove,
    required this.onReject,
  });

  final WalletConnectRequest request;
  final WalletConnectTransactionPreview? preview;
  final String? previewError;
  final bool isPreviewLoading;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  /// Best-effort decoded text for `personal_sign` / `eth_sign`; null otherwise.
  String? _messageText() {
    const codec = WalletConnectV2RequestCodec();
    if (!codec.isMessageSignMethod(request.method)) {
      return null;
    }
    try {
      return codec
          .decodeMessageRequest(request.method, request.params)
          .displayText;
    } catch (_) {
      return null;
    }
  }

  /// Best-effort `primaryType @ domain` summary for EIP-712; null otherwise.
  String? _typedDataSummary() {
    const codec = WalletConnectV2RequestCodec();
    if (!codec.isTypedDataMethod(request.method)) {
      return null;
    }
    try {
      final typed = codec.decodeTypedDataRequest(request.params).typedData;
      final primaryType = typed['primaryType'] ?? 'typed data';
      final domain = typed['domain'];
      final domainName = domain is Map ? (domain['name'] ?? '') : '';
      return domainName == '' ? '$primaryType' : '$primaryType @ $domainName';
    } catch (_) {
      return null;
    }
  }

  String? _chainSwitchTarget(AppLocalizations l10n) {
    const codec = WalletConnectV2RequestCodec();
    if (!codec.isChainSwitchMethod(request.method)) {
      return null;
    }
    try {
      final chainId = codec.decodeSwitchEthereumChainId(request.params);
      return chainId == 11155111
          ? 'Sepolia (eip155:11155111)'
          : chainId == 1
          ? 'Ethereum Mainnet (eip155:1)'
          : 'eip155:$chainId';
    } catch (_) {
      return l10n.wcInvalidChain;
    }
  }

  /// Human name of the chain the request targets; falls back to the numeric id
  /// for a chain the wallet does not carry a config for.
  /// Chain ids arrive CAIP-2 style ("eip155:11155111") or bare ("11155111").
  int? _numericChainId(String chainId) {
    final tail = chainId.contains(':') ? chainId.split(':').last : chainId;
    return int.tryParse(tail.trim());
  }

  EvmNetworkConfig? _configForChain(String chainId) {
    final numeric = _numericChainId(chainId);
    if (numeric == null) {
      return null;
    }
    for (final config in evmNetworkConfigs.values) {
      if (config.chainId == numeric) {
        return config;
      }
    }
    return null;
  }

  String _networkName(String chainId) =>
      _configForChain(chainId)?.name ?? chainId;

  String _nativeSymbol(String chainId) =>
      _configForChain(chainId)?.nativeSymbol ?? '';

  /// Wei arrives as a hex or decimal string depending on the dApp.
  BigInt _parseWei(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
      return BigInt.tryParse(trimmed.substring(2), radix: 16) ?? BigInt.zero;
    }
    return BigInt.tryParse(trimmed) ?? BigInt.zero;
  }

  String _shortAddress(String address) {
    if (address.length <= 14) {
      return address;
    }
    return '${address.substring(0, 8)}…${address.substring(address.length - 6)}';
  }

  /// One line saying what the dApp is asking for, in the user's terms.
  String _requestSummary(AppLocalizations l10n) {
    const codec = WalletConnectV2RequestCodec();
    if (codec.isTransactionMethod(request.method)) {
      return l10n.wcAskSignTransfer;
    }
    if (codec.isMessageSignMethod(request.method)) {
      return l10n.wcAskSignMessage;
    }
    if (codec.isTypedDataMethod(request.method)) {
      return l10n.wcAskSignTypedData;
    }
    return l10n.wcAskConfirm;
  }

  String _formatUnits(BigInt value, int decimals) {
    final negative = value.isNegative;
    final digits = value.abs().toString().padLeft(decimals + 1, '0');
    final whole = digits.substring(0, digits.length - decimals);
    final fraction = digits
        .substring(digits.length - decimals)
        .replaceFirst(RegExp(r'0+$'), '');
    final rendered = fraction.isEmpty ? whole : '$whole.$fraction';
    return negative ? '-$rendered' : rendered;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tx = request.params.isNotEmpty && request.params.first is Map
        ? (request.params.first! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final to = tx['to']?.toString();
    final value = tx['value']?.toString();
    final message = _messageText();
    final typedData = _typedDataSummary();
    final chainSwitchTarget = _chainSwitchTarget(l10n);
    const codec = WalletConnectV2RequestCodec();
    final isTransaction = codec.isTransactionMethod(request.method);
    final canApproveTransaction =
        !isTransaction ||
        (!isPreviewLoading && previewError == null && preview != null);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chainSwitchTarget == null
                ? l10n.wcSignRequest
                : l10n.wcChainSwitchRequest,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          // Plain language: what is being asked, in units a person reads. The
          // raw method name, the numeric chain id and the wei value are
          // developer detail and stay out of the request card.
          Text(_requestSummary(l10n), style: theme.textTheme.bodyMedium),
          Text(
            l10n.wcNetworkLine(_networkName(request.chainId)),
            style: theme.textTheme.bodySmall,
          ),
          if (chainSwitchTarget != null)
            Text(l10n.wcSwitchTo(_networkName(chainSwitchTarget))),
          if (to != null) ...[
            const SizedBox(height: 4),
            Text('${l10n.wcRecipient}: ${_shortAddress(to)}'),
          ],
          if (value != null && isTransaction) ...[
            const SizedBox(height: 4),
            Text(
              l10n.wcAmountLine(
                _formatUnits(_parseWei(value), 18),
                _nativeSymbol(request.chainId),
              ),
              style: theme.textTheme.titleMedium,
            ),
          ],
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(l10n.wcMessageLine(message)),
          ],
          if (typedData != null) Text('EIP-712: $typedData'),
          if (isPreviewLoading) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.wcSimulating)),
              ],
            ),
          ],
          if (previewError != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.wcSigningBlocked(previewError!),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          if (preview case final WalletConnectTransactionPreview safe) ...[
            // The request's network, not the dashboard selector, defines the
            // native unit for this WalletConnect operation.
            const SizedBox(height: 8),
            Text(
              safe.isContractCall
                  ? l10n.wcTypeContractCall
                  : l10n.wcTypePlainTransfer,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(l10n.wcDestination(safe.toAddress)),
            Text(
              l10n.wcAmountLine(
                _formatUnits(safe.valueWei, 18),
                evmNetworkConfigs[safe.network]!.nativeSymbol,
              ),
            ),
            if (safe.isContractCall)
              Text(
                l10n.wcCalldataLine(
                  safe.data.length,
                  safe.calldataSelector ?? l10n.wcSelectorNone,
                ),
              ),
            Text(
              safe.gasWasEstimated
                  ? l10n.wcGasLimitEstimated('${safe.gasLimit}')
                  : l10n.wcGasLimitFromDapp('${safe.gasLimit}'),
            ),
            Text(
              l10n.wcGasPriceLine(
                _formatUnits(safe.maxFeePerGasWei, 9),
                _formatUnits(safe.maxPriorityFeePerGasWei, 9),
              ),
            ),
            Text(
              l10n.wcMaxFeeLine(
                _formatUnits(safe.maximumNetworkFeeWei, 18),
                evmNetworkConfigs[safe.network]!.nativeSymbol,
              ),
            ),
            Text(
              safe.wasSimulated
                  ? l10n.wcPreflightOk(safe.providerLabel)
                  : l10n.wcPreflightOffline,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: canApproveTransaction ? onApprove : null,
                child: Text(
                  const WalletConnectV2RequestCodec().isChainSwitchMethod(
                        request.method,
                      )
                      ? l10n.wcSwitchNetwork
                      : l10n.wcApproveAndSign,
                ),
              ),
              OutlinedButton(
                onPressed: onReject,
                child: Text(l10n.wcRejectRequest),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onDisconnect});

  final WalletConnectSession session;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            session.peer.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (session.peer.url.isNotEmpty)
            Text(
              session.peer.url,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 6),
          Text(l10n.wcChains(session.chains.join(', '))),
          Text(l10n.wcAccounts(session.accounts.join(', '))),
          const SizedBox(height: 4),
          Text(
            l10n.wcConnectedAt(session.connectedAtUtc.toIso8601String()),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onDisconnect,
            icon: const Icon(Icons.link_off),
            label: Text(l10n.wcDisconnect),
          ),
        ],
      ),
    );
  }
}

/// Three-segment progress for the AirGap flow, so the user can see where they
/// are in a process that spans two devices.
class _AirGapProgress extends StatelessWidget {
  const _AirGapProgress({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var step = 1; step <= 3; step++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: step <= currentStep
                      ? NocturneColors.accent
                      : NocturneColors.neutral800,
                  borderRadius: NocturneRadius.smAll,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
