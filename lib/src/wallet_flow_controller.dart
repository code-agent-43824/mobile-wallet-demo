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
    TransactionService? transactionService,
    TransactionBroadcaster? transactionBroadcaster,
    NonceProvider? nonceProvider,
    QrScanner qrScanner = const UnavailableQrScanner(),
  }) : _walletConnectService = walletConnectService,
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
      _pendingRequest = request;
      _notify();
    });
    unawaited(_walletConnectService.init());
  }

  late final PhoneSecureVault _vault;
  late final ExternalDeviceDemoBackend _externalDeviceBackend;
  late final WalletBackendRegistry _backendRegistry;
  final WalletConnectService _walletConnectService;
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
  WalletConnectRequest? _pendingRequest;
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
  WalletConnectRequest? get pendingRequest => _pendingRequest;

  /// The most recent AirGap `airgap-sig:` response payload, if any.
  String? get airGapResponsePayload => _airGapResponsePayload;

  KeyStorageBackend get activeBackend {
    final selectedBackendId = _selectedBackendId;
    if (selectedBackendId != null) {
      final backend = _backendRegistry.backendById(selectedBackendId);
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
      final selectedBackendId = await _backendRegistry.loadSelectedBackendId();
      final backend = _backendRegistry.backendById(selectedBackendId) ?? _vault;
      final summary = await backend.getWalletSummary();
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
  /// [pendingRequest] is cleared ONLY on success — a wrong PIN/cancel leaves the
  /// request visible to retry.
  Future<void> approvePendingRequest({
    String? pin,
    bool useBiometrics = false,
  }) async {
    final request = _pendingRequest;
    if (request == null) {
      return;
    }
    await _withFreshlyUnlockedMaterial(
      pin: pin,
      useBiometrics: useBiometrics,
      action: () async {
        final signer = _activeTransactionSigner();
        final coordinator = WalletConnectInboundCoordinator(
          service: _walletConnectService,
          transactionService: _transactionService,
          broadcaster: _transactionBroadcaster,
          nonceProvider: _nonceProvider,
        );
        await coordinator.handleRequest(request: request, signer: signer);
        _pendingRequest = null;
      },
    );
  }

  /// Rejects [pendingRequest] with a JSON-RPC error to the dApp.
  Future<void> rejectPendingRequest() async {
    await _runGuarded(() async {
      final request = _pendingRequest;
      if (request == null) {
        return;
      }
      await _walletConnectService.respondError(
        request: request,
        message: 'Запрос отклонён пользователем.',
      );
      _pendingRequest = null;
    });
  }

  /// Runs [action] with the active backend transiently unlocked for a single
  /// private-key operation, then ALWAYS re-locks and wipes the in-memory key.
  ///
  /// Auth is collected per call (no session reuse): [useBiometrics] takes the
  /// biometric fast-path, otherwise [pin] is required. Runs behind the busy
  /// overlay and through [_runGuarded] so wrong-PIN/lockout/offline
  /// [VaultFailure]s surface via [errorMessage]. The `finally` lock+wipe runs
  /// even if [action] throws, so the key never outlives the operation.
  Future<void> _withFreshlyUnlockedMaterial({
    String? pin,
    bool useBiometrics = false,
    required Future<void> Function() action,
  }) async {
    await _runBusy('Разблокируем для подписи…', () async {
      try {
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
        await action();
      } finally {
        activeBackend.lock();
        _material = null;
        if (activeBackend is ExternalDeviceDemoBackend) {
          _externalRuntimeState = await _externalDeviceBackend
              .loadRuntimeState();
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
    await _withFreshlyUnlockedMaterial(
      pin: pin,
      useBiometrics: useBiometrics,
      action: () async {
        // The external device session must be open for the mock PKCS#11 sign
        // op; it runs while we hold a fresh unlock (the finally re-locks).
        final backend = activeBackend;
        if (backend is ExternalDeviceDemoBackend) {
          await backend.performPkcs11Operation(
            ExternalDevicePkcs11Operation(
              kind: ExternalDevicePkcs11OperationKind.signTransactionPreview,
              payload: '$amountText ${asset.symbol} -> $toAddress',
            ),
          );
        }

        final signer = _activeTransactionSigner();
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

  /// Builds a signer for the active backend, reading the transiently-set
  /// [_material]; throws [VaultFailure] when the backend is locked or the
  /// material is unavailable. Only valid inside [_withFreshlyUnlockedMaterial].
  WalletTransactionSigner _activeTransactionSigner() {
    final backend = activeBackend;
    if (backend is ExternalDeviceKeyStorageBackend) {
      return walletOperationAuthorizer
          .authorizeUnlockedExternalDeviceSigning(
            backend: backend,
            walletMaterial: _material,
          )
          .signer;
    }
    return walletOperationAuthorizer
        .authorizeUnlockedLocalSigning(
          backend: backend,
          walletMaterial: _material,
          authMethod: _lastUnlockAuthMethod,
        )
        .signer;
  }

  /// Signs an offline AirGap `airgap-tx:` request payload with the active
  /// backend and stores the `airgap-sig:` response in [airGapResponsePayload].
  /// A private-key operation: freshly unlocks for this signature only (PIN or
  /// biometric for the phone vault; device "tap + PIN" for the external device)
  /// and re-locks after.
  Future<void> signAirGapRequest(
    String payload, {
    String? pin,
    bool useBiometrics = false,
  }) async {
    await _withFreshlyUnlockedMaterial(
      pin: pin,
      useBiometrics: useBiometrics,
      action: () async {
        final signer = _activeTransactionSigner();
        _airGapResponsePayload = await const AirGapInboundCoordinator()
            .signRequestPayload(
              requestPayload: payload,
              transactionService: _transactionService,
              signer: signer,
            );
      },
    );
  }

  /// Clears the displayed AirGap response.
  void clearAirGapResponse() {
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
    } on AirGapPayloadException catch (error) {
      _errorMessage = error.message;
      _notify();
    }
  }
}
