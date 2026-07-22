part of 'wallet_flow_screen.dart';

/// Owns the wallet onboarding/unlock state machine and every domain action,
/// independent of any widget. [WalletFlowScreen] is now a thin listener that
/// renders [stage] and forwards user intents to the methods here, so this logic
/// is unit-testable without pumping a widget.
///
/// Behavior is preserved 1:1 from the former `State`: each action mutates plain
/// fields and then calls [_notify] (the old single `setState`), and
/// `if (_disposed)` guards replace the old `if (!mounted)` guards so a late
/// async completion after [dispose] is a harmless no-op.
class WalletFlowController extends ChangeNotifier {
  WalletFlowController({
    required SecureKeyValueStore store,
    required BiometricAuthGateway biometricAuthGateway,
    WalletConnectService walletConnectService =
        const UnavailableWalletConnectService(),
    WalletConnectTransactionPreflight walletConnectPreflight =
        const RequestFieldsWalletConnectTransactionPreflight(),
    TransactionService? transactionService,
    TransactionBroadcaster? transactionBroadcaster,
    NonceProvider? nonceProvider,
    QrScanner qrScanner = const UnavailableQrScanner(),
  }) : _walletConnectService = walletConnectService,
       _walletConnectPreflight = walletConnectPreflight,
       _qrScanner = qrScanner,
       _transactionService =
           transactionService ??
           const HardenedTransactionServiceImplementation(),
       _transactionBroadcaster =
           transactionBroadcaster ?? PublicRpcTransactionBroadcaster(),
       _nonceProvider = nonceProvider ?? PublicRpcNonceProvider() {
    _vault = PhoneSecureVault(
      store: store,
      biometricAuth: biometricAuthGateway,
    );
    _externalDeviceBackend = ExternalDeviceDemoBackend(store: store);
    _backendRegistry = WalletBackendRegistry(
      store: store,
      entries: <WalletBackendCatalogEntry>[
        WalletBackendCatalogEntry(
          descriptor: const WalletBackendDescriptor(
            id: 'phone_secure_vault',
            kind: WalletBackendKind.phoneSecureVault,
            label: 'Phone Secure Vault',
            description:
                'Seed хранится локально в защищённом phone vault под PIN и опциональной биометрией.',
          ),
          backend: _vault,
        ),
        WalletBackendCatalogEntry(
          descriptor: const WalletBackendDescriptor(
            id: 'external_nfc_demo_device',
            kind: WalletBackendKind.externalDevice,
            label: 'External NFC demo device',
            description:
                'Симулированный внешний NFC-подписант для Phase 7: отдельная UX-ветка и отдельный signing/auth runtime без реального SDK.',
            availabilityNote:
                'Demo-only путь: настоящий NFC SDK пока не подключён.',
          ),
          backend: _externalDeviceBackend,
        ),
      ],
    );

    _walletConnectSessions = _walletConnectService.activeSessions;
    _walletConnectProposalSub = _walletConnectService.sessionProposals.listen((
      proposal,
    ) {
      _pendingProposal = proposal;
      _notify();
    });
    _walletConnectSessionsSub = _walletConnectService.sessionsChanges.listen((
      sessions,
    ) {
      _walletConnectSessions = sessions;
      _notify();
    });
    _walletConnectRequestSub = _walletConnectService.requests.listen((request) {
      const codec = WalletConnectV2RequestCodec();
      if (codec.isCapabilitiesMethod(request.method)) {
        unawaited(_autoRespondCapabilities(request));
        return;
      }
      final alreadyQueued = _pendingRequests.any(
        (queued) => queued.id == request.id && queued.topic == request.topic,
      );
      if (!alreadyQueued) {
        final wasEmpty = _pendingRequests.isEmpty;
        _pendingRequests.addLast(request);
        if (wasEmpty) {
          unawaited(_preparePendingRequestPreview());
        }
      }
      _notify();
    });
    unawaited(_walletConnectService.init());
  }

  late final PhoneSecureVault _vault;
  late final ExternalDeviceDemoBackend _externalDeviceBackend;
  late final WalletBackendRegistry _backendRegistry;
  final WalletConnectService _walletConnectService;
  final WalletConnectTransactionPreflight _walletConnectPreflight;
  final QrScanner _qrScanner;
  final TransactionService _transactionService;
  final TransactionBroadcaster _transactionBroadcaster;
  final NonceProvider _nonceProvider;
  late final StreamSubscription<WalletConnectSessionProposal>
  _walletConnectProposalSub;
  late final StreamSubscription<List<WalletConnectSession>>
  _walletConnectSessionsSub;
  late final StreamSubscription<WalletConnectRequest> _walletConnectRequestSub;

  /// Stateless signing authorizer used by the unlocked send flow.
  final WalletOperationAuthorizer walletOperationAuthorizer =
      const WalletOperationAuthorizer();

  WalletFlowStage _stage = WalletFlowStage.loading;
  StoredWalletSummary? _summary;
  WalletMaterial? _material;
  String? _seedPhraseToShow;
  String? _errorMessage;
  String? _busyMessage;
  String? _pendingBiometricPin;
  String? _selectedBackendId;
  WalletConnectSessionProposal? _pendingProposal;
  final ListQueue<WalletConnectRequest> _pendingRequests =
      ListQueue<WalletConnectRequest>();
  bool _isHandlingWalletConnectRequest = false;
  WalletConnectTransactionPreview? _pendingRequestPreview;
  String? _pendingRequestPreviewError;
  bool _isPendingRequestPreviewLoading = false;
  String? _airGapAccountExportPayload;
  String? _airGapRequestPayload;
  EthSignRequest? _airGapRequest;
  Eip4527TransactionPreview? _airGapRequestPreview;
  String? _airGapResponsePayload;
  List<WalletConnectSession> _walletConnectSessions =
      const <WalletConnectSession>[];
  ExternalDeviceDemoRuntimeState? _externalRuntimeState;
  WalletAuthMethod _lastUnlockAuthMethod = WalletAuthMethod.pin;
  bool _biometricsEnabled = false;
  bool _biometricsAvailable = false;
  bool _disposed = false;

  // Read-only surface consumed by the widget layer.
  WalletFlowStage get stage => _stage;
  StoredWalletSummary? get summary => _summary;
  WalletMaterial? get material => _material;
  String? get seedPhraseToShow => _seedPhraseToShow;
  String? get errorMessage => _errorMessage;

  /// Non-null while a long operation (create/import/unlock) runs; the UI shows a
  /// progress overlay with this message so key derivation isn't a frozen screen.
  String? get busyMessage => _busyMessage;
  String? get selectedBackendId => _selectedBackendId;
  ExternalDeviceDemoRuntimeState? get externalRuntimeState =>
      _externalRuntimeState;
  WalletAuthMethod get lastUnlockAuthMethod => _lastUnlockAuthMethod;
  bool get biometricsEnabled => _biometricsEnabled;
  bool get biometricsAvailable => _biometricsAvailable;
  List<WalletBackendCatalogEntry> get backendEntries =>
      _backendRegistry.entries;
  String get defaultBackendId => _backendRegistry.defaultBackendId;

  /// The backend id to preselect in the welcome stage.
  String get effectiveBackendId => _selectedBackendId ?? defaultBackendId;

  /// Whether the biometric-unlock affordance should be offered.
  bool get canUnlockWithBiometrics =>
      _biometricsEnabled && _biometricsAvailable;

  /// Whether a relay-backed WalletConnect client is configured and usable.
  bool get isWalletConnectAvailable => _walletConnectService.isAvailable;

  /// Whether live camera QR scanning is wired (the camera affordance is shown).
  bool get isQrCameraAvailable => _qrScanner.isCameraScanAvailable;

  /// Whether loading a QR from an image file is available (all platforms).
  bool get isQrFileLoadAvailable => _qrScanner.isFileLoadAvailable;

  /// Active WalletConnect sessions (wallet-side view).
  List<WalletConnectSession> get walletConnectSessions =>
      _walletConnectSessions;

  /// The incoming session proposal awaiting approve/reject, if any.
  WalletConnectSessionProposal? get pendingProposal => _pendingProposal;

  /// The incoming signing request awaiting approve/reject, if any.
  WalletConnectRequest? get pendingRequest =>
      _pendingRequests.isEmpty ? null : _pendingRequests.first;

  int get pendingRequestCount => _pendingRequests.length;

  WalletConnectTransactionPreview? get pendingRequestPreview =>
      _pendingRequestPreview;

  String? get pendingRequestPreviewError => _pendingRequestPreviewError;

  bool get isPendingRequestPreviewLoading => _isPendingRequestPreviewLoading;

  /// MetaMask-compatible account export and transaction signing state.
  String? get airGapAccountExportPayload => _airGapAccountExportPayload;
  EthSignRequest? get airGapRequest => _airGapRequest;
  Eip4527TransactionPreview? get airGapRequestPreview => _airGapRequestPreview;

  /// The most recent EIP-4527 `eth-signature` response, if any.
  String? get airGapResponsePayload => _airGapResponsePayload;

  KeyStorageBackend get activeBackend {
    // Once a wallet exists, its persisted summary is authoritative. The
    // mutable onboarding selection must never redirect a private-key operation
    // to another (uninitialized) vault.
    final backendId = _summary?.backendId ?? _selectedBackendId;
    if (backendId != null) {
      final backend = _backendRegistry.backendById(backendId);
      if (backend != null) {
        return backend;
      }
    }
    return _vault;
  }

  bool get isExternalBackendSelected =>
      activeBackend is ExternalDeviceKeyStorageBackend;

  /// Display label for the active/selected backend (locked & unlocked stages).
  String get backendLabel {
    final id = _summary?.backendId ?? _selectedBackendId ?? '';
    return _backendRegistry.descriptorById(id)?.label ?? 'Unknown backend';
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_walletConnectProposalSub.cancel());
    unawaited(_walletConnectSessionsSub.cancel());
    unawaited(_walletConnectRequestSub.cancel());
    super.dispose();
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  Future<void> loadInitialState() async {
    try {
      var selectedBackendId = await _backendRegistry.loadSelectedBackendId();
      var backend = _backendRegistry.backendById(selectedBackendId) ?? _vault;
      var summary = await backend.getWalletSummary();

      // A backend-selection write and a wallet-payload write are separate
      // durable records. If Android killed the process between them (or an old
      // build left a stale selection), recover the existing wallet by scanning
      // the small backend catalog instead of incorrectly returning to welcome.
      if (summary == null) {
        for (final entry in _backendRegistry.availableEntries) {
          final candidate = entry.backend;
          if (candidate == null || candidate.backendId == backend.backendId) {
            continue;
          }
          final candidateSummary = await candidate.getWalletSummary();
          if (candidateSummary != null) {
            backend = candidate;
            summary = candidateSummary;
            selectedBackendId = candidate.backendId;
            await _backendRegistry.selectBackend(selectedBackendId);
            break;
          }
        }
      }
      final biometricsEnabled = await backend.isBiometricUnlockEnabled();
      final biometricsAvailable = await backend.isBiometricUnlockAvailable();
      final externalRuntimeState = backend is ExternalDeviceDemoBackend
          ? await backend.loadRuntimeState()
          : null;
      if (_disposed) {
        return;
      }
      _selectedBackendId = selectedBackendId;
      _summary = summary;
      _externalRuntimeState = externalRuntimeState;
      _biometricsEnabled = biometricsEnabled;
      _biometricsAvailable = biometricsAvailable;
      // An existing wallet opens STRAIGHT to the read-only dashboard
      // (WalletFlowStage.unlocked, whose semantics are now "read-only
      // dashboard"): no PIN/biometric/PBKDF2 just to view it. The private key is
      // only touched per-operation. _material stays null — the dashboard renders
      // from _summary. (locked is retained for a future "lock app on open".)
      _stage = summary == null
          ? WalletFlowStage.welcome
          : WalletFlowStage.unlocked;
      _notify();
    } on VaultFailure catch (error) {
      // A corrupt or unsupported at-rest payload must not crash startup; surface
      // it and fall back to the welcome flow so the wallet can be re-created.
      if (_disposed) {
        return;
      }
      _errorMessage = error.message;
      _stage = WalletFlowStage.welcome;
      _notify();
    }
  }

  Future<void> selectBackend(String backendId) async {
    await _runGuarded(() async {
      await _backendRegistry.selectBackend(backendId);
      _selectedBackendId = backendId;
      if (backendId == _externalDeviceBackend.backendId) {
        _externalRuntimeState = await _externalDeviceBackend.loadRuntimeState();
      } else {
        _externalRuntimeState = null;
      }
      _errorMessage = null;
    });
  }

  void goToWelcome() {
    _errorMessage = null;
    _stage = WalletFlowStage.welcome;
    _notify();
  }

  void goToCreateWallet() {
    _errorMessage = null;
    _stage = WalletFlowStage.createWallet;
    _notify();
  }

  void goToImportWallet() {
    _errorMessage = null;
    _stage = WalletFlowStage.importWallet;
    _notify();
  }

  Future<void> createWallet({required String pin}) async {
    final busy = isExternalBackendSelected
        ? 'Подключаем устройство…'
        : 'Создаём кошелёк…';
    await _runBusy(busy, () async {
      final backend = activeBackend;
      final material = await backend.createWallet(pin: pin);
      _summary = StoredWalletSummary(
        address: material.address,
        backendId: backend.backendId,
        createdAtUtc: DateTime.now().toUtc(),
      );
      _material = material;
      _pendingBiometricPin = pin;
      _lastUnlockAuthMethod = isExternalBackendSelected
          ? WalletAuthMethod.externalDevice
          : WalletAuthMethod.pin;
      if (isExternalBackendSelected) {
        _seedPhraseToShow = null;
        _biometricsEnabled = false;
        _biometricsAvailable = false;
        _material = null;
        backend.lock();
        _externalRuntimeState = await _externalDeviceBackend.loadRuntimeState();
        // Land on the read-only dashboard; the device "tap + PIN" path runs
        // per private-key operation.
        _stage = WalletFlowStage.unlocked;
      } else {
        _seedPhraseToShow = material.mnemonic;
        _stage = WalletFlowStage.showSeed;
      }
    });
  }

  Future<void> importWallet({
    required String mnemonic,
    required String pin,
  }) async {
    final busy = isExternalBackendSelected
        ? 'Подключаем устройство…'
        : 'Импортируем кошелёк…';
    await _runBusy(busy, () async {
      final backend = activeBackend;
      final material = await backend.importWallet(mnemonic: mnemonic, pin: pin);
      _summary = StoredWalletSummary(
        address: material.address,
        backendId: backend.backendId,
        createdAtUtc: DateTime.now().toUtc(),
      );
      _material = material;
      _pendingBiometricPin = pin;
      _seedPhraseToShow = null;
      _lastUnlockAuthMethod = isExternalBackendSelected
          ? WalletAuthMethod.externalDevice
          : WalletAuthMethod.pin;
      if (isExternalBackendSelected) {
        _biometricsEnabled = false;
        _biometricsAvailable = false;
        _material = null;
        backend.lock();
        _externalRuntimeState = await _externalDeviceBackend.loadRuntimeState();
        // Land on the read-only dashboard; the device "tap + PIN" path runs
        // per private-key operation.
        _stage = WalletFlowStage.unlocked;
      } else {
        _stage = WalletFlowStage.biometricPrompt;
      }
    });
  }

  /// Retained for a FUTURE "lock app on open" toggle: the default flow no longer
  /// routes through a [WalletFlowStage.locked] screen (the dashboard is
  /// read-only and each key op authenticates on demand). Kept so the locked
  /// shell can be re-enabled without re-deriving this logic.
  Future<void> unlockWallet(String pin) async {
    await _runBusy('Разблокируем кошелёк…', () async {
      _material = await activeBackend.unlock(pin: pin);
      _lastUnlockAuthMethod = activeBackend is ExternalDeviceKeyStorageBackend
          ? WalletAuthMethod.externalDevice
          : WalletAuthMethod.pin;
      if (activeBackend is ExternalDeviceDemoBackend) {
        _externalRuntimeState = await _externalDeviceBackend.loadRuntimeState();
      }
      _stage = WalletFlowStage.unlocked;
    });
  }

  void finishSeedBackup() {
    _stage = WalletFlowStage.biometricPrompt;
    _notify();
  }

  Future<void> completeBiometricChoice(bool enabled) async {
    await _runGuarded(() async {
      final pin = _pendingBiometricPin;
      if (enabled) {
        if (pin == null || pin.isEmpty) {
          throw const VaultFailure(
            'Не удалось включить биометрию: PIN текущей сессии недоступен.',
          );
        }
        await activeBackend.setBiometricUnlockEnabled(enabled: true, pin: pin);
      } else {
        await activeBackend.setBiometricUnlockEnabled(enabled: false, pin: '');
      }

      _biometricsEnabled = enabled;
      _material = null;
      _pendingBiometricPin = null;
      _seedPhraseToShow = null;
      // Onboarding ends on the read-only dashboard; the key is re-derived per
      // private-key operation. We still lock the backend + drop _material.
      _stage = WalletFlowStage.unlocked;
      activeBackend.lock();
      if (activeBackend is ExternalDeviceDemoBackend) {
        _externalRuntimeState = await _externalDeviceBackend.loadRuntimeState();
      }
    });
  }

  /// Retained for a FUTURE "lock app on open" toggle (see [unlockWallet]); the
  /// default flow no longer enters a locked screen to unlock the whole app.
  Future<void> unlockWithBiometrics() async {
    await _runGuarded(() async {
      _material = await activeBackend.unlockWithBiometrics();
      _lastUnlockAuthMethod = WalletAuthMethod.biometric;
      _stage = WalletFlowStage.unlocked;
    });
  }

  Future<void> refreshExternalRuntimeState() async {
    if (activeBackend is! ExternalDeviceDemoBackend) {
      return;
    }
    final runtimeState = await (activeBackend as ExternalDeviceDemoBackend)
        .loadRuntimeState();
    if (_disposed) {
      return;
    }
    _externalRuntimeState = runtimeState;
    _notify();
  }

  Future<void> simulateExternalDeviceOffline() async {
    await _runGuarded(() async {
      await _externalDeviceBackend.simulateDeviceUnavailable();
      // Stay on the read-only dashboard: viewing never needed the key, and the
      // device's offline state is reflected in the runtime tiles. The "tap +
      // PIN" reconnect happens lazily on the next private-key op.
      _material = null;
      await refreshExternalRuntimeState();
    });
  }

  Future<void> reconnectExternalDevice() async {
    await _runGuarded(() async {
      await _externalDeviceBackend.reconnectDevice();
      await refreshExternalRuntimeState();
    });
  }

  Future<void> disconnectExternalSession() async {
    await _runGuarded(() async {
      await _externalDeviceBackend.disconnectSession();
      // Stay on the read-only dashboard; the session is re-established on the
      // next private-key op via the device "tap + PIN" path.
      _material = null;
      await refreshExternalRuntimeState();
    });
  }

  Future<void> pingExternalDevice() {
    return _performExternalPkcs11Operation(
      const ExternalDevicePkcs11Operation(
        kind: ExternalDevicePkcs11OperationKind.probeSession,
      ),
    );
  }

  Future<void> readExternalAddress() {
    return _performExternalPkcs11Operation(
      const ExternalDevicePkcs11Operation(
        kind: ExternalDevicePkcs11OperationKind.readPublicAddress,
      ),
    );
  }

  Future<void> _performExternalPkcs11Operation(
    ExternalDevicePkcs11Operation operation,
  ) async {
    await _runGuarded(() async {
      await _externalDeviceBackend.performPkcs11Operation(operation);
      await refreshExternalRuntimeState();
    });
  }

  /// Pairs with a dApp from a `wc:` URI; a proposal arrives via the proposals
  /// stream and surfaces as [pendingProposal].
  Future<void> pairWalletConnect({required String uri}) async {
    await _runGuarded(() async {
      await _walletConnectService.pair(uri: uri);
    });
  }

  /// Approves [pendingProposal], binding this wallet's account (CAIP-10) across
  /// each requested chain. No-op when there is no pending proposal or no wallet.
  Future<void> approvePendingProposal() async {
    await _runGuarded(() async {
      final proposal = _pendingProposal;
      final address = _summary?.address;
      if (proposal == null || address == null) {
        return;
      }
      final accounts = proposal.requiredChains
          .map((chain) => '$chain:$address')
          .toList();
      await _walletConnectService.approveSession(
        proposal: proposal,
        accounts: accounts,
      );
      _pendingProposal = null;
      _walletConnectSessions = _walletConnectService.activeSessions;
    });
  }

  /// Rejects [pendingProposal] and clears it.
  Future<void> rejectPendingProposal() async {
    await _runGuarded(() async {
      final proposal = _pendingProposal;
      if (proposal == null) {
        return;
      }
      await _walletConnectService.rejectSession(proposal: proposal);
      _pendingProposal = null;
    });
  }

  /// Disconnects an active WalletConnect session by [topic].
  Future<void> disconnectWalletConnectSession({required String topic}) async {
    await _runGuarded(() async {
      await _walletConnectService.disconnect(topic: topic);
      _walletConnectSessions = _walletConnectService.activeSessions;
    });
  }

  /// Approves [pendingRequest]: signs it with the active backend and responds to
  /// the dApp via the inbound coordinator (broadcast for `eth_sendTransaction`,
  /// signed-tx hex for `eth_signTransaction`). A private-key operation, so it
  /// freshly unlocks for this request only (PIN or biometric for the phone
  /// vault; device "tap + PIN" for the external device) and re-locks after.
  /// The queue head is removed after the coordinator has answered the dApp; a
  /// wrong PIN/cancel leaves it visible to retry, while later requests remain
  /// queued instead of overwriting it.
  Future<void> approvePendingRequest({
    String? pin,
    bool useBiometrics = false,
  }) async {
    final request = pendingRequest;
    if (request == null || _isHandlingWalletConnectRequest) {
      return;
    }
    _isHandlingWalletConnectRequest = true;
    _notify();
    try {
      final coordinator = _walletConnectCoordinator();
      const codec = WalletConnectV2RequestCodec();
      if (codec.isChainSwitchMethod(request.method)) {
        await _runGuarded(() async {
          await coordinator.handleRequest(request: request);
          _removePendingRequest(request);
        });
        return;
      }
      final transactionPreview = codec.isTransactionMethod(request.method)
          ? _pendingRequestPreview
          : null;
      if (codec.isTransactionMethod(request.method) &&
          transactionPreview == null) {
        _errorMessage =
            _pendingRequestPreviewError ??
            'Дождитесь безопасной проверки транзакции через RPC.';
        return;
      }
      await _withFreshlyAuthorizedSigner(
        pin: pin,
        useBiometrics: useBiometrics,
        action: (signer) async {
          await coordinator.handleRequest(
            request: request,
            signer: signer,
            transactionPreview: transactionPreview,
          );
          _removePendingRequest(request);
        },
      );
    } finally {
      _isHandlingWalletConnectRequest = false;
      _notify();
    }
  }

  /// Rejects [pendingRequest] with a JSON-RPC error to the dApp.
  Future<void> rejectPendingRequest() async {
    await _runGuarded(() async {
      final request = pendingRequest;
      if (request == null || _isHandlingWalletConnectRequest) {
        return;
      }
      await _walletConnectService.respondError(
        request: request,
        message: 'Запрос отклонён пользователем.',
      );
      _removePendingRequest(request);
    });
  }

  WalletConnectInboundCoordinator _walletConnectCoordinator() {
    return WalletConnectInboundCoordinator(
      service: _walletConnectService,
      transactionService: _transactionService,
      broadcaster: _transactionBroadcaster,
      nonceProvider: _nonceProvider,
      preflight: _walletConnectPreflight,
    );
  }

  Future<void> _autoRespondCapabilities(WalletConnectRequest request) async {
    try {
      await _walletConnectCoordinator().handleRequest(
        request: request,
        walletAddress: _summary?.address,
      );
    } catch (error) {
      _errorMessage = 'WalletConnect capabilities: $error';
      _notify();
    }
  }

  Future<void> _preparePendingRequestPreview() async {
    final request = pendingRequest;
    const codec = WalletConnectV2RequestCodec();
    if (request == null || !codec.isTransactionMethod(request.method)) {
      _pendingRequestPreview = null;
      _pendingRequestPreviewError = null;
      _isPendingRequestPreviewLoading = false;
      _notify();
      return;
    }
    final address = _summary?.address;
    if (address == null) {
      _pendingRequestPreview = null;
      _pendingRequestPreviewError = 'Кошелёк не инициализирован.';
      _isPendingRequestPreviewLoading = false;
      _notify();
      return;
    }

    _pendingRequestPreview = null;
    _pendingRequestPreviewError = null;
    _isPendingRequestPreviewLoading = true;
    _notify();
    try {
      final preview = await _walletConnectPreflight.inspect(
        request: request,
        walletAddress: address,
      );
      if (pendingRequest?.id != request.id ||
          pendingRequest?.topic != request.topic) {
        return;
      }
      _pendingRequestPreview = preview;
    } catch (error) {
      if (pendingRequest?.id != request.id ||
          pendingRequest?.topic != request.topic) {
        return;
      }
      _pendingRequestPreviewError = error.toString();
    } finally {
      if (pendingRequest?.id == request.id &&
          pendingRequest?.topic == request.topic) {
        _isPendingRequestPreviewLoading = false;
        _notify();
      }
    }
  }

  void _removePendingRequest(WalletConnectRequest request) {
    _pendingRequests.removeWhere(
      (queued) => queued.id == request.id && queued.topic == request.topic,
    );
    _pendingRequestPreview = null;
    _pendingRequestPreviewError = null;
    _isPendingRequestPreviewLoading = false;
    unawaited(_preparePendingRequestPreview());
  }

  /// Runs [action] with one transient signer. Hardware custody provides a
  /// secret-free [CustodySigningSession]; the phone vault keeps its existing
  /// local-material implementation behind this orchestration boundary.
  ///
  /// Auth is collected per call (no session reuse): [useBiometrics] takes the
  /// biometric fast-path, otherwise [pin] is required. Runs behind the busy
  /// overlay and through [_runGuarded] so wrong-PIN/lockout/offline
  /// [VaultFailure]s surface via [errorMessage]. The `finally` lock+wipe runs
  /// even if [action] throws, so the key never outlives the operation.
  Future<void> _withFreshlyAuthorizedSigner({
    String? pin,
    bool useBiometrics = false,
    String busyMessage = 'Разблокируем для подписи…',
    required Future<void> Function(WalletTransactionSigner signer) action,
  }) async {
    await _runBusy(busyMessage, () async {
      CustodySigningSession? custodySession;
      try {
        final backend = activeBackend;
        if (backend is WalletCustodyBackend) {
          if (useBiometrics) {
            throw const BiometricUnavailableFailure();
          }
          final custodyBackend = backend as WalletCustodyBackend;
          final openedSession = await custodyBackend.openSigningSession(
            pin: pin!,
          );
          custodySession = openedSession;
          _lastUnlockAuthMethod = WalletAuthMethod.externalDevice;
          final operation = walletOperationAuthorizer.authorizeCustodySession(
            session: openedSession,
          );
          await action(operation.signer);
          return;
        }
        if (useBiometrics) {
          _material = await activeBackend.unlockWithBiometrics();
          _lastUnlockAuthMethod = WalletAuthMethod.biometric;
        } else {
          _material = await activeBackend.unlock(pin: pin!);
          _lastUnlockAuthMethod =
              activeBackend is ExternalDeviceKeyStorageBackend
              ? WalletAuthMethod.externalDevice
              : WalletAuthMethod.pin;
        }
        final operation = walletOperationAuthorizer
            .authorizeUnlockedLocalSigning(
              backend: backend,
              walletMaterial: _material,
              authMethod: _lastUnlockAuthMethod,
            );
        await action(operation.signer);
      } finally {
        try {
          await custodySession?.close();
        } finally {
          activeBackend.lock();
          _material = null;
          if (activeBackend is ExternalDeviceDemoBackend) {
            _externalRuntimeState = await _externalDeviceBackend
                .loadRuntimeState();
          }
        }
      }
    });
  }

  /// Authorizes, signs and submits a transfer from the read-only dashboard send
  /// form. A private-key operation: freshly unlocks for this send only and
  /// re-locks after (no [_material] is held after this returns). The widget
  /// keeps the read-only `prepareTransfer` validation/preview; this method moves
  /// the authorize + (external-device PKCS#11 sign op) + `submitAuthorized
  /// TransferFlow` here so signing happens while the key is briefly in memory.
  ///
  /// Returns the [HardenedSubmitResult] (incl. the async `trackingFuture`) so
  /// the widget can render the result + drive tracking; throws on failure so
  /// the caller's wrapper surfaces it. Errors are also mirrored to
  /// [errorMessage] via [_runGuarded].
  Future<HardenedSubmitResult?> authorizeAndSubmitTransfer({
    required WalletChainSnapshot snapshot,
    required String fromAddress,
    required String toAddress,
    required String amountText,
    required TransferAssetOption asset,
    required TransactionTracker tracker,
    String? pin,
    bool useBiometrics = false,
  }) async {
    final transactionService = _transactionService;
    if (transactionService is! HardenedTransactionService) {
      throw const TransactionFailure(
        'Текущий transaction service не поддерживает Phase 6 hardened flow.',
      );
    }

    HardenedSubmitResult? result;
    await _withFreshlyAuthorizedSigner(
      pin: pin,
      useBiometrics: useBiometrics,
      action: (signer) async {
        result = await transactionService.submitAuthorizedTransferFlow(
          snapshot: snapshot,
          fromAddress: fromAddress,
          toAddress: toAddress,
          amountText: amountText,
          asset: asset,
          signer: signer,
          broadcaster: _transactionBroadcaster,
          nonceProvider: _nonceProvider,
          tracker: tracker,
        );
      },
    );
    return result;
  }

  /// Exports only the account-level extended PUBLIC key as `crypto-hdkey`, for
  /// MetaMask's QR hardware-wallet account import.
  Future<void> prepareAirGapAccountExport({
    String? pin,
    bool useBiometrics = false,
  }) async {
    final backend = activeBackend;
    if (backend is WalletCustodyBackend) {
      final custodyBackend = backend as WalletCustodyBackend;
      await _runBusy('Готовим публичный QR аккаунта…', () async {
        if (useBiometrics) {
          throw const BiometricUnavailableFailure();
        }
        final publicAccount = await custodyBackend.readAccountPublicKey(
          pin: pin!,
        );
        final export = const AccountExportDeriver().deriveFromPublicAccount(
          publicAccount: publicAccount,
          name: 'Wallet Demo',
        );
        _airGapAccountExportPayload = const Eip4527Codec().encodeHdKey(export);
      });
    } else {
      await _withFreshlyAuthorizedSigner(
        pin: pin,
        useBiometrics: useBiometrics,
        busyMessage: 'Готовим публичный QR аккаунта…',
        action: (_) async {
          final material = _material;
          if (material == null) {
            throw const VaultFailure('Ключ кошелька недоступен.');
          }
          final export = const AccountExportDeriver().deriveAccountExport(
            mnemonic: material.mnemonic,
            name: 'Wallet Demo',
          );
          _airGapAccountExportPayload = const Eip4527Codec().encodeHdKey(
            export,
          );
        },
      );
    }
  }

  /// Decodes and validates an EIP-4527 request without unlocking the key.
  Future<void> loadAirGapRequest(String payload) async {
    await _runGuarded(() async {
      final normalized = normalizeUr(payload);
      if (normalized.split('/').length != 2) {
        throw const UrQrException(
          'Multipart UR нужно полностью отсканировать камерой.',
        );
      }
      final request = const Eip4527Codec().decodeSignRequest(normalized);
      if (request.chainId != 1 && request.chainId != 11155111) {
        throw Eip4527Exception(
          'AirGap поддерживает только Ethereum Mainnet и Sepolia (получен chainId ${request.chainId}).',
        );
      }
      if (request.dataType != EthSignDataType.transaction &&
          request.dataType != EthSignDataType.typedTransaction) {
        throw const Eip4527Exception(
          'В базовом AirGap режиме поддерживаются только ETH-транзакции.',
        );
      }
      if (request.dataType == EthSignDataType.transaction &&
          request.chainId != 1) {
        throw const Eip4527Exception(
          'Legacy EIP-155 AirGap поддержан только для Mainnet; для Sepolia MetaMask должен использовать EIP-1559.',
        );
      }
      final expectedAddress = _summary?.address.toLowerCase();
      final requestAddress = request.addressHex?.toLowerCase();
      if (requestAddress != null && requestAddress != expectedAddress) {
        throw Eip4527Exception(
          'Запрос адресован другому аккаунту ($requestAddress).',
        );
      }
      if (requestAddress == null &&
          request.derivationPath.toPathString() != "M/44'/60'/0'/0/0") {
        throw Eip4527Exception(
          'Запрос без адреса использует неизвестный путь ${request.derivationPath.toPathString()}.',
        );
      }
      final preview = const Eip4527TransactionPreviewDecoder().decode(request);
      _airGapRequestPayload = normalized;
      _airGapRequest = request;
      _airGapRequestPreview = preview;
      _airGapResponsePayload = null;
    });
  }

  Future<void> scanAirGapRequestWithCamera() async {
    final payload = await _runQr(
      () => _qrScanner.scanUrWithCamera(
        title: 'MetaMask eth-sign-request',
        expectedType: Eip4527Codec.signRequestType,
      ),
    );
    if (payload != null) {
      await loadAirGapRequest(payload);
    }
  }

  Future<void> loadAirGapRequestFromFile() async {
    final payload = await _runQr(_qrScanner.loadFromFile);
    if (payload != null) {
      await loadAirGapRequest(payload);
    }
  }

  /// Signs the exact request that produced the visible preview. The online
  /// MetaMask instance remains responsible for assembly and broadcast.
  Future<void> signPendingAirGapRequest({
    String? pin,
    bool useBiometrics = false,
  }) async {
    final requestPayload = _airGapRequestPayload;
    if (requestPayload == null || _airGapRequest == null) {
      await _runGuarded(() async {
        throw const Eip4527Exception('Сначала отсканируйте запрос MetaMask.');
      });
      return;
    }
    await _withFreshlyAuthorizedSigner(
      pin: pin,
      useBiometrics: useBiometrics,
      action: (signer) async {
        _airGapResponsePayload = await const Eip4527InboundCoordinator()
            .signRequestUr(
              requestUr: requestPayload,
              signer: signer,
              transactionService: _transactionService,
            );
      },
    );
  }

  /// Clears the request/signature while keeping the reusable account QR.
  void clearAirGapRequest() {
    _airGapRequestPayload = null;
    _airGapRequest = null;
    _airGapRequestPreview = null;
    _airGapResponsePayload = null;
    _errorMessage = null;
    _notify();
  }

  /// Scans a QR with the camera; returns the decoded text or null. Surfaces a
  /// clear message via [errorMessage] on failure (paste stays as the fallback).
  Future<String?> scanQrWithCamera({String title = ''}) =>
      _runQr(() => _qrScanner.scanWithCamera(title: title));

  /// Loads a QR from a picked image file (works on every platform, incl.
  /// Windows); returns the decoded text or null.
  Future<String?> loadQrFromFile() => _runQr(_qrScanner.loadFromFile);

  Future<String?> _runQr(Future<String?> Function() action) async {
    try {
      final result = await action();
      _errorMessage = null;
      _notify();
      return result;
    } on QrScannerException catch (error) {
      _errorMessage = error.message;
      _notify();
      return null;
    }
  }

  /// Opens the Connections screen (from the unlocked dashboard).
  void openConnections() {
    _errorMessage = null;
    _stage = WalletFlowStage.connections;
    _notify();
  }

  /// Returns from the Connections screen to the unlocked dashboard.
  void closeConnections() {
    _errorMessage = null;
    _stage = WalletFlowStage.unlocked;
    _notify();
  }

  /// Retained for a FUTURE "lock app on open" toggle (see [unlockWallet]); the
  /// default flow stays on the read-only dashboard rather than entering a locked
  /// screen.
  void lockWallet() {
    activeBackend.lock();
    if (activeBackend is ExternalDeviceDemoBackend) {
      _externalDeviceBackend.loadRuntimeState().then((runtimeState) {
        if (_disposed) {
          return;
        }
        _externalRuntimeState = runtimeState;
        _notify();
      });
    }
    _material = null;
    _pendingBiometricPin = null;
    _stage = WalletFlowStage.locked;
    _notify();
  }

  /// Runs a long action behind a progress overlay: sets [busyMessage] (UI shows
  /// the overlay), runs it through [_runGuarded] (error handling + notify), then
  /// clears the overlay. Pairs with the off-isolate key derivation in the vault
  /// so the overlay actually animates instead of freezing.
  Future<void> _runBusy(String message, Future<void> Function() action) async {
    _busyMessage = message;
    _notify();
    try {
      await _runGuarded(action);
    } finally {
      _busyMessage = null;
      _notify();
    }
  }

  Future<void> _runGuarded(Future<void> Function() action) async {
    try {
      await action();
      _errorMessage = null;
      _notify();
    } on VaultFailure catch (error) {
      _errorMessage = error.message;
      _notify();
    } on WalletConnectServiceException catch (error) {
      _errorMessage = error.message;
      _notify();
    } on Eip4527Exception catch (error) {
      _errorMessage = error.message;
      _notify();
    } on Eip4527SignException catch (error) {
      _errorMessage = error.message;
      _notify();
    } on UrQrException catch (error) {
      _errorMessage = error.message;
      _notify();
    } catch (error) {
      // Catch-all: any other failure (e.g. an unexpected WalletConnect SDK /
      // relay error while signing or responding to a request) must surface,
      // not vanish — otherwise an action like "approve request" looks like the
      // button does nothing. The message carries the cause for diagnosis.
      _errorMessage = 'Не удалось выполнить операцию: $error';
      _notify();
    }
  }
}
