part of 'wallet_flow_screen.dart';

/// One row of the wallet switcher.
///
/// A wallet is no longer the same thing as a storage backend: the card backend
/// can hold several registered cards, each its own wallet, so a row names the
/// backend *and* — for a card — which registered profile it means.
class SwitchableWallet {
  const SwitchableWallet({
    required this.backendId,
    required this.label,
    required this.address,
    required this.isCardStorage,
    this.cardProfileId,
    this.serial,
  });

  final String backendId;

  /// True for both a registered card and the card backend's empty row, so the
  /// UI can word that row as "add a card" rather than as a generic empty slot.
  final bool isCardStorage;

  /// Translated name of the storage, not of this particular wallet.
  final String label;

  /// The wallet's address, or null for a slot that holds no wallet yet —
  /// selecting such a row starts the flow that creates or connects one.
  final String? address;

  /// Which registered card this row means. Null for the phone vault and for
  /// the card backend's empty slot.
  final String? cardProfileId;

  /// The card's own serial, when it was reported when the card was registered.
  final String? serial;

  bool get isCard => cardProfileId != null;
  bool get isEmptySlot => address == null;
}

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
    RutokenNativeAdapter? rutokenNativeAdapter,
    AppLocalizations? messages,
  }) : _messages = messages ?? lookupAppLocalizations(const Locale('ru')),
       _store = store,
       _walletConnectService = walletConnectService,
       _walletConnectPreflight = walletConnectPreflight,
       _qrScanner = qrScanner,
       _rutokenNativeAdapter = rutokenNativeAdapter,
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
    _rutokenProvisioning = rutokenNativeAdapter == null
        ? null
        : RutokenProvisioningService(
            adapter: rutokenNativeAdapter,
            store: store,
          );
    _rutokenBiometricPinStore = rutokenNativeAdapter == null
        ? null
        : RutokenBiometricPinStore(
            store: store,
            biometricAuth: biometricAuthGateway,
          );
    _rutokenBackend =
        rutokenNativeAdapter == null || _rutokenProvisioning == null
        ? null
        : RutokenCustodyBackend(
            adapter: rutokenNativeAdapter,
            publicAccountLoader: _rutokenProvisioning.loadPublicAccount,
            accountLoader: _rutokenProvisioning.loadAccountDescriptor,
            biometricPinStore: _rutokenBiometricPinStore,
          );
    // The catalogue's label/description are technical identifiers for
    // diagnostics, not product copy — the UI derives what it shows from
    // [WalletBackendDescriptor.kind] via [_labelForBackendKind].
    _backendRegistry = WalletBackendRegistry(
      store: store,
      entries: <WalletBackendCatalogEntry>[
        WalletBackendCatalogEntry(
          descriptor: const WalletBackendDescriptor(
            id: 'phone_secure_vault',
            kind: WalletBackendKind.phoneSecureVault,
            label: 'Phone Secure Vault',
            description:
                'BIP-39 seed encrypted at rest on this device under a '
                'PIN-derived key, with optional biometric unlock.',
          ),
          backend: _vault,
        ),
        if (_rutokenBackend case final backend?)
          WalletBackendCatalogEntry(
            descriptor: const WalletBackendDescriptor(
              id: 'rutoken_nfc',
              kind: WalletBackendKind.externalDevice,
              label: 'Rutoken NFC',
              description:
                  'Non-exporting ECDSA custody: only the public profile is '
                  'retained in the app, and every signature needs an NFC tap '
                  'and the card PIN.',
            ),
            backend: backend,
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

  /// Source of every user-visible string this controller produces.
  ///
  /// The controller has no `BuildContext`, so the localizations are injected
  /// like every other collaborator (see the DI seam in `app.dart`): an optional
  /// constructor argument defaulting to the production implementation, which
  /// here is the Russian bundle. [WalletFlowScreen] re-points it at the
  /// context's bundle whenever the locale changes, so the next action speaks
  /// the chosen language. Strings already produced and stored (an
  /// [errorMessage], a diagnostic result) keep the wording they were created
  /// with — retranslating them would mean re-running the operation.
  AppLocalizations _messages;

  set messages(AppLocalizations value) => _messages = value;

  late final PhoneSecureVault _vault;
  late final WalletBackendRegistry _backendRegistry;
  final SecureKeyValueStore _store;
  final WalletConnectService _walletConnectService;
  final WalletConnectTransactionPreflight _walletConnectPreflight;
  final QrScanner _qrScanner;
  final RutokenNativeAdapter? _rutokenNativeAdapter;
  late final RutokenProvisioningService? _rutokenProvisioning;
  late final RutokenBiometricPinStore? _rutokenBiometricPinStore;
  late final RutokenCustodyBackend? _rutokenBackend;
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
  bool _awaitingCard = false;
  Future<void> Function()? _busyCancelAction;
  bool _busyCancellationRequested = false;
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
  WalletAuthMethod _lastUnlockAuthMethod = WalletAuthMethod.pin;
  bool _biometricsEnabled = false;
  bool _biometricsAvailable = false;
  bool _disposed = false;
  String? _rutokenDiagnosticResult;
  RutokenGeneratedBackup? _rutokenGeneratedBackup;
  String? _rutokenProvisioningResult;
  String? _pendingRutokenBiometricPin;

  static const String _rutokenRegistrationStorageKey =
      'wallet.rutoken_backend_registered.v1';

  // Read-only surface consumed by the widget layer.
  WalletFlowStage get stage => _stage;
  StoredWalletSummary? get summary => _summary;
  WalletMaterial? get material => _material;
  String? get seedPhraseToShow => _seedPhraseToShow;
  String? get errorMessage => _errorMessage;

  /// Non-null while a long operation (create/import/unlock) runs; the UI shows a
  /// progress overlay with this message so key derivation isn't a frozen screen.
  String? get busyMessage => _busyMessage;
  bool get canCancelBusyOperation => _busyCancelAction != null;

  /// True while the app is waiting for the user to hold the card against the
  /// phone. The UI renders the tap animation for this state, so it is an
  /// explicit flag rather than an inference from the busy message or from the
  /// operation happening to be cancellable.
  bool get isAwaitingCard => _awaitingCard;
  bool get isBusyCancellationRequested => _busyCancellationRequested;
  String? get selectedBackendId => _selectedBackendId;
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
  bool get hasRutokenNativeAdapter => _rutokenNativeAdapter != null;
  String? get rutokenDiagnosticResult => _rutokenDiagnosticResult;
  RutokenGeneratedBackup? get rutokenGeneratedBackup => _rutokenGeneratedBackup;
  String? get rutokenProvisioningResult => _rutokenProvisioningResult;
  bool get hasPendingRutokenBiometricOffer =>
      _pendingRutokenBiometricPin != null && _busyMessage == null;

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

  WalletBackend get activeBackend {
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

  bool get isExternalBackendSelected => activeBackend is WalletCustodyBackend;

  bool get isRutokenSelected => activeBackend is RutokenCustodyBackend;

  /// Display label for the active/selected backend (locked & unlocked stages).
  ///
  /// The catalogue's own `label` is a technical identifier ("Phone Secure
  /// Vault", "Rutoken NFC") used in diagnostics; the UI shows the translated
  /// name of the *kind*, so the vendor name never reaches the product surface.
  String get backendLabel {
    final id = _summary?.backendId ?? _selectedBackendId ?? '';
    final kind = _backendRegistry.descriptorById(id)?.kind;
    return _labelForBackendKind(kind);
  }

  String _labelForBackendKind(WalletBackendKind? kind) => switch (kind) {
    WalletBackendKind.phoneSecureVault => _messages.custodyPhone,
    WalletBackendKind.externalDevice => _messages.custodyCard,
    null => _messages.storageUnknown,
  };

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
      final rutokenBackend = _rutokenBackend;
      // v1.47 could provision a real token but intentionally did not register
      // it as the active wallet. Migrate that active public profile exactly
      // once; later explicit backend choices remain authoritative.
      if (rutokenBackend != null &&
          await _store.read(_rutokenRegistrationStorageKey) != '1' &&
          await rutokenBackend.hasWallet()) {
        selectedBackendId = rutokenBackend.backendId;
        await _backendRegistry.selectBackend(selectedBackendId);
        await _store.write(_rutokenRegistrationStorageKey, '1');
      }
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
      if (_disposed) {
        return;
      }
      _selectedBackendId = selectedBackendId;
      _summary = summary;
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

  /// Physical transport probe. It does not provision or mutate master keys: it
  /// verifies NFC/login, the address public point, one per-operation child-key
  /// derivation,
  /// one raw CKM_ECDSA operation and unconditional native-session teardown.
  Future<void> runRutokenTransportDiagnostic(String pin) async {
    final adapter = _rutokenNativeAdapter;
    if (adapter == null) return;
    await _runBusy(
      _messages.tapCardTitle,
      () async {
        final session = await adapter.openSession(pin: pin);
        Object? primaryFailure;
        try {
          final account = await adapter.readAccountDescriptor(session);
          if (account == null) {
            throw StateError(_messages.errorCardNoWallet);
          }
          final digest = Uint8List.fromList(List<int>.generate(32, (i) => i));
          final signature = await adapter.signDigest(
            session: session,
            derivationPath: account.derivationPath,
            digest: digest,
          );
          _rutokenDiagnosticResult = _messages.cardCheckSuccess(
            account.address,
            signature.toBytes().length,
          );
        } catch (error) {
          primaryFailure = error;
          rethrow;
        } finally {
          try {
            await adapter.closeSession(session);
          } catch (_) {
            if (primaryFailure == null) rethrow;
          }
        }
      },
      onCancel: adapter.cancelPendingOperation,
      awaitingCard: true,
    );
  }

  /// The wallets the user can switch between: the phone vault, plus one entry
  /// per registered card rather than a single "card" row.
  ///
  /// Everything here is read from software-retained data, so listing costs no
  /// NFC tap — including the serials, which were recorded when each card was
  /// registered.
  Future<List<SwitchableWallet>> listSwitchableWallets() async {
    final result = <SwitchableWallet>[];
    for (final entry in _backendRegistry.availableEntries) {
      final backend = entry.backend;
      if (backend == null) {
        continue;
      }
      if (entry.descriptor.kind == WalletBackendKind.externalDevice) {
        final profiles =
            await _rutokenProvisioning?.loadProfiles() ??
            const <RutokenCardProfile>[];
        for (final profile in profiles) {
          result.add(
            SwitchableWallet(
              backendId: entry.descriptor.id,
              label: _labelForBackendKind(entry.descriptor.kind),
              address: profile.account.address,
              isCardStorage: true,
              cardProfileId: profile.id,
              serial: profile.serial,
            ),
          );
        }
        // Always offer the empty slot: it is how another card gets connected
        // once the phone already holds a wallet.
        result.add(
          SwitchableWallet(
            backendId: entry.descriptor.id,
            label: _labelForBackendKind(entry.descriptor.kind),
            address: null,
            isCardStorage: true,
          ),
        );
        continue;
      }
      final summary = await backend.getWalletSummary();
      result.add(
        SwitchableWallet(
          backendId: entry.descriptor.id,
          label: _labelForBackendKind(entry.descriptor.kind),
          address: summary?.address,
          isCardStorage: false,
        ),
      );
    }
    return result;
  }

  /// The card profile operations are currently bound to, or null when the
  /// active wallet is not a card.
  Future<String?> selectedCardProfileId() async =>
      (await _rutokenProvisioning?.loadSelectedProfile())?.id;

  /// Switches the active wallet to [wallet] and reloads everything that
  /// describes it.
  ///
  /// [selectBackend] alone only records the choice — it does not reload the
  /// summary, so using it to switch would leave the previous wallet's address
  /// on screen. This mirrors the resolution [loadInitialState] performs, and
  /// drops any held material so nothing survives the switch.
  Future<void> switchActiveWallet(SwitchableWallet wallet) async {
    final currentCardProfileId = await selectedCardProfileId();
    if (!wallet.isEmptySlot &&
        wallet.backendId == effectiveBackendId &&
        wallet.cardProfileId == currentCardProfileId) {
      return;
    }
    await _runBusy(_messages.busySwitchingWallet, () async {
      // Point the card backend at this profile *before* resolving the summary,
      // so the address, the biometric PIN slot and every later operation all
      // read the same card.
      if (wallet.cardProfileId case final String profileId) {
        await _rutokenProvisioning?.selectProfile(profileId);
      }
      await _backendRegistry.selectBackend(wallet.backendId);
      final backend = _backendRegistry.backendById(wallet.backendId) ?? _vault;
      final summary = await backend.getWalletSummary();
      _selectedBackendId = wallet.backendId;
      _summary = summary;
      _material = null;
      _biometricsEnabled = await backend.isBiometricUnlockEnabled();
      _biometricsAvailable = await backend.isBiometricUnlockAvailable();
      // A backend with no wallet yet starts its own onboarding rather than
      // showing an empty dashboard. The card backend's empty row does too even
      // when a card is registered — it is the "set up another card" entry, and
      // resolving it to the already-selected card's summary would make it a
      // no-op.
      _stage = wallet.isEmptySlot || summary == null
          ? WalletFlowStage.welcome
          : WalletFlowStage.unlocked;
      _errorMessage = null;
    });
  }

  /// Drops what the phone remembers about one card. The card and its key are
  /// untouched; it can be connected again later.
  ///
  /// Forgetting the active card leaves the app on whatever wallet the store
  /// falls back to, so the reload runs through the same path as a switch.
  Future<void> forgetCard(String cardProfileId) async {
    final provisioning = _rutokenProvisioning;
    if (provisioning == null) return;
    await _runBusy(_messages.busyForgettingCard, () async {
      await provisioning.forgetProfile(cardProfileId);
      final backend = _rutokenBackend;
      if (backend == null || effectiveBackendId != backend.backendId) {
        return;
      }
      final summary = await backend.getWalletSummary();
      if (summary != null) {
        _summary = summary;
        _biometricsEnabled = await backend.isBiometricUnlockEnabled();
        _biometricsAvailable = await backend.isBiometricUnlockAvailable();
        _errorMessage = null;
        return;
      }
      // That was the last card: fall back to the phone vault, or to onboarding
      // when it holds nothing either.
      final vaultSummary = await _vault.getWalletSummary();
      await _backendRegistry.selectBackend(_vault.backendId);
      _selectedBackendId = _vault.backendId;
      _summary = vaultSummary;
      _material = null;
      _biometricsEnabled = await _vault.isBiometricUnlockEnabled();
      _biometricsAvailable = await _vault.isBiometricUnlockAvailable();
      _stage = vaultSummary == null
          ? WalletFlowStage.welcome
          : WalletFlowStage.unlocked;
      _errorMessage = null;
    });
  }

  Future<void> selectBackend(String backendId) async {
    await _runGuarded(() async {
      await _backendRegistry.selectBackend(backendId);
      _selectedBackendId = backendId;
      _errorMessage = null;
    });
  }

  void goToWelcome() {
    _errorMessage = null;
    _rutokenGeneratedBackup = null;
    _stage = WalletFlowStage.welcome;
    _notify();
  }

  void goToCreateWallet() {
    if (isRutokenSelected) {
      goToRutokenCreate();
      return;
    }
    _errorMessage = null;
    _stage = WalletFlowStage.createWallet;
    _notify();
  }

  void goToImportWallet() {
    if (isRutokenSelected) {
      goToRutokenImport();
      return;
    }
    _errorMessage = null;
    _stage = WalletFlowStage.importWallet;
    _notify();
  }

  void goToRutokenCreate() {
    if (_rutokenProvisioning == null) return;
    _errorMessage = null;
    _rutokenGeneratedBackup = null;
    _stage = WalletFlowStage.rutokenCreate;
    _notify();
  }

  void goToRutokenImport() {
    if (_rutokenProvisioning == null) return;
    _errorMessage = null;
    _rutokenGeneratedBackup = null;
    _stage = WalletFlowStage.rutokenImport;
    _notify();
  }

  void prepareRutokenGeneratedBackup({required String passphrase}) {
    final provisioning = _rutokenProvisioning;
    if (provisioning == null) return;
    _errorMessage = null;
    _rutokenGeneratedBackup = provisioning.generateBackup(
      passphrase: passphrase,
    );
    _stage = WalletFlowStage.rutokenBackup;
    _notify();
  }

  Future<void> provisionGeneratedRutoken({required String pin}) async {
    final backup = _rutokenGeneratedBackup;
    if (backup == null) return;
    await _provisionRutoken(
      mnemonic: backup.mnemonic,
      passphrase: backup.passphrase,
      pin: pin,
    );
  }

  Future<void> provisionImportedRutoken({
    required String mnemonic,
    required String passphrase,
    required String pin,
  }) {
    return _provisionRutoken(
      mnemonic: mnemonic,
      passphrase: passphrase,
      pin: pin,
    );
  }

  Future<void> adoptExistingRutoken({required String pin}) async {
    final provisioning = _rutokenProvisioning;
    final backend = _rutokenBackend;
    if (provisioning == null || backend == null) return;
    await _runBusy(
      _messages.busyTapExistingCard,
      () async {
        final account = await provisioning.adoptExisting(pin: pin);
        await _backendRegistry.selectBackend(backend.backendId);
        await _store.write(_rutokenRegistrationStorageKey, '1');
        _selectedBackendId = backend.backendId;
        _summary = StoredWalletSummary(
          address: account.address,
          backendId: backend.backendId,
          createdAtUtc: DateTime.now().toUtc(),
        );
        _material = null;
        _lastUnlockAuthMethod = WalletAuthMethod.externalDevice;
        _stage = WalletFlowStage.unlocked;
        _rutokenProvisioningResult = _messages.cardAdoptSuccess(
          account.address,
        );
        await _queueRutokenBiometricOffer(pin);
      },
      onCancel: _rutokenNativeAdapter?.cancelPendingOperation,
      awaitingCard: true,
    );
  }

  Future<void> _provisionRutoken({
    required String mnemonic,
    required String passphrase,
    required String pin,
  }) async {
    final provisioning = _rutokenProvisioning;
    if (provisioning == null) return;
    await _runBusy(
      _messages.busyTapEmptyCard,
      () async {
        final result = await provisioning.provision(
          mnemonic: mnemonic,
          passphrase: passphrase,
          pin: pin,
        );
        _rutokenProvisioningResult = _messages.cardProvisionSuccess(
          result.account.address,
        );
        final backend = _rutokenBackend;
        if (backend == null) {
          throw VaultFailure(_messages.errorCardUnsupportedBuild);
        }
        await _backendRegistry.selectBackend(backend.backendId);
        await _store.write(_rutokenRegistrationStorageKey, '1');
        _selectedBackendId = backend.backendId;
        _summary = StoredWalletSummary(
          address: result.account.address,
          backendId: backend.backendId,
          createdAtUtc: DateTime.now().toUtc(),
        );
        _material = null;
        _biometricsEnabled = false;
        _biometricsAvailable = await backend.isBiometricUnlockAvailable();
        _lastUnlockAuthMethod = WalletAuthMethod.externalDevice;
        _rutokenGeneratedBackup = null;
        _stage = WalletFlowStage.unlocked;
        await _queueRutokenBiometricOffer(pin);
      },
      onCancel: _rutokenNativeAdapter?.cancelPendingOperation,
      awaitingCard: true,
    );
  }

  Future<void> completeRutokenBiometricOffer(bool enabled) async {
    final pin = _pendingRutokenBiometricPin;
    final backend = _rutokenBackend;
    if (pin == null || backend == null) return;
    var completed = false;
    await _runBusy(
      enabled ? _messages.busySavingPinBiometrics : _messages.busySavingChoice,
      () async {
        if (enabled) {
          await backend.enableBiometricPin(pin);
        } else {
          await backend.declineBiometricPin();
        }
        _biometricsAvailable = await backend.isBiometricUnlockAvailable();
        _biometricsEnabled = await backend.isBiometricUnlockEnabled();
        completed = true;
      },
    );
    if (completed) {
      _pendingRutokenBiometricPin = null;
      _notify();
    }
  }

  Future<void> _queueRutokenBiometricOffer(String pin) async {
    final backend = _rutokenBackend;
    if (backend == null ||
        pin.isEmpty ||
        _pendingRutokenBiometricPin != null ||
        !await backend.shouldOfferBiometricPin()) {
      return;
    }
    _pendingRutokenBiometricPin = pin;
    _notify();
  }

  Future<void> createWallet({required String pin}) async {
    final busy = isExternalBackendSelected
        ? _messages.busyConnectingCard
        : _messages.busyCreatingWallet;
    await _runBusy(busy, () async {
      final backend = activeBackend;
      if (backend is! KeyStorageBackend) {
        throw VaultFailure(_messages.errorUseCardCreateFlow);
      }
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
        ? _messages.busyConnectingCard
        : _messages.busyImportingWallet;
    await _runBusy(busy, () async {
      final backend = activeBackend;
      if (backend is! KeyStorageBackend) {
        throw VaultFailure(_messages.errorUseCardImportFlow);
      }
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
    await _runBusy(_messages.busyUnlockingWallet, () async {
      final backend = activeBackend;
      if (backend is! KeyStorageBackend) {
        throw VaultFailure(_messages.errorCardUnlocksPerSignature);
      }
      _material = await backend.unlock(pin: pin);
      _lastUnlockAuthMethod = WalletAuthMethod.pin;
      _stage = WalletFlowStage.unlocked;
    });
  }

  void finishSeedBackup() {
    _stage = WalletFlowStage.biometricPrompt;
    _notify();
  }

  Future<void> completeBiometricChoice(bool enabled) async {
    await _runGuarded(() async {
      final backend = activeBackend;
      if (backend is! KeyStorageBackend) {
        throw const BiometricUnavailableFailure();
      }
      final pin = _pendingBiometricPin;
      if (enabled) {
        if (pin == null || pin.isEmpty) {
          throw VaultFailure(_messages.errorBiometricsNoPin);
        }
        await backend.setBiometricUnlockEnabled(enabled: true, pin: pin);
      } else {
        await backend.setBiometricUnlockEnabled(enabled: false, pin: '');
      }

      _biometricsEnabled = enabled;
      _material = null;
      _pendingBiometricPin = null;
      _seedPhraseToShow = null;
      // Onboarding ends on the read-only dashboard; the key is re-derived per
      // private-key operation. We still lock the backend + drop _material.
      _stage = WalletFlowStage.unlocked;
      activeBackend.lock();
    });
  }

  /// Retained for a FUTURE "lock app on open" toggle (see [unlockWallet]); the
  /// default flow no longer enters a locked screen to unlock the whole app.
  Future<void> unlockWithBiometrics() async {
    await _runGuarded(() async {
      final backend = activeBackend;
      if (backend is! KeyStorageBackend) {
        throw const BiometricUnavailableFailure();
      }
      _material = await backend.unlockWithBiometrics();
      _lastUnlockAuthMethod = WalletAuthMethod.biometric;
      _stage = WalletFlowStage.unlocked;
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
            _pendingRequestPreviewError ?? _messages.errorAwaitPreflight;
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
        message: _messages.wcRejectedByUser,
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
      _pendingRequestPreviewError = _messages.errorWalletNotInitialized;
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
    String? busyMessage,
    required Future<void> Function(WalletTransactionSigner signer) action,
  }) async {
    await _runBusy(
      busyMessage ?? _messages.busyUnlockingForSignature,
      () async {
        CustodySigningSession? custodySession;
        Object? primaryFailure;
        try {
          final backend = activeBackend;
          if (backend is WalletCustodyBackend) {
            var effectivePin = pin;
            if (useBiometrics) {
              if (backend is! RutokenCustodyBackend) {
                throw const BiometricUnavailableFailure();
              }
              effectivePin = await backend.retrievePinWithBiometrics();
            }
            if (effectivePin == null || effectivePin.isEmpty) {
              throw VaultFailure(_messages.errorEnterCardPin);
            }
            final openedSession = await backend.openSigningSession(
              pin: effectivePin,
            );
            custodySession = openedSession;
            _lastUnlockAuthMethod = useBiometrics
                ? WalletAuthMethod.biometric
                : WalletAuthMethod.externalDevice;
            final operation = walletOperationAuthorizer.authorizeCustodySession(
              session: openedSession,
            );
            await action(operation.signer);
            if (!useBiometrics && backend is RutokenCustodyBackend) {
              await _queueRutokenBiometricOffer(effectivePin);
            }
            return;
          }
          if (backend is! KeyStorageBackend) {
            throw VaultFailure(_messages.errorStorageCannotSignLocally);
          }
          if (useBiometrics) {
            _material = await backend.unlockWithBiometrics();
            _lastUnlockAuthMethod = WalletAuthMethod.biometric;
          } else {
            _material = await backend.unlock(pin: pin!);
            _lastUnlockAuthMethod = WalletAuthMethod.pin;
          }
          final operation = walletOperationAuthorizer
              .authorizeUnlockedLocalSigning(
                backend: backend,
                walletMaterial: _material,
                authMethod: _lastUnlockAuthMethod,
              );
          await action(operation.signer);
        } catch (error) {
          primaryFailure = error;
          rethrow;
        } finally {
          try {
            try {
              await custodySession?.close();
            } catch (_) {
              if (primaryFailure == null) rethrow;
            }
          } finally {
            activeBackend.lock();
            _material = null;
          }
        }
      },
      awaitingCard: activeBackend is RutokenCustodyBackend,
      onCancel: activeBackend is RutokenCustodyBackend
          ? _rutokenNativeAdapter?.cancelPendingOperation
          : null,
    );
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
      throw TransactionFailure(_messages.errorHardenedFlowUnsupported);
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
      await _runBusy(_messages.busyPreparingAccountQr, () async {
        if (useBiometrics) {
          if (backend is! RutokenCustodyBackend) {
            throw const BiometricUnavailableFailure();
          }
          await backend.retrievePinWithBiometrics();
        }
        final publicAccount = await backend.readAccountPublicKey(
          pin: pin ?? '',
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
        busyMessage: _messages.busyPreparingAccountQr,
        action: (_) async {
          final material = _material;
          if (material == null) {
            throw VaultFailure(_messages.errorWalletKeyUnavailable);
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
        throw UrQrException(_messages.errorMultipartUrNeedsCamera);
      }
      final request = const Eip4527Codec().decodeSignRequest(normalized);
      if (request.chainId != 1 && request.chainId != 11155111) {
        throw Eip4527Exception(
          _messages.errorUnsupportedChain(request.chainId),
        );
      }
      if (request.dataType != EthSignDataType.transaction &&
          request.dataType != EthSignDataType.typedTransaction) {
        throw Eip4527Exception(_messages.errorOnlyEthTransfers);
      }
      if (request.dataType == EthSignDataType.transaction &&
          request.chainId != 1) {
        throw Eip4527Exception(_messages.errorLegacyMainnetOnly);
      }
      final expectedAddress = _summary?.address.toLowerCase();
      final requestAddress = request.addressHex?.toLowerCase();
      if (requestAddress != null && requestAddress != expectedAddress) {
        throw Eip4527Exception(
          _messages.errorRequestOtherAccount(requestAddress),
        );
      }
      if (requestAddress == null &&
          request.derivationPath.toPathString() != "M/44'/60'/0'/0/0") {
        throw Eip4527Exception(
          _messages.errorRequestUnknownPath(
            request.derivationPath.toPathString(),
          ),
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
        throw Eip4527Exception(_messages.errorScanRequestFirst);
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
    _material = null;
    _pendingBiometricPin = null;
    _stage = WalletFlowStage.locked;
    _notify();
  }

  /// Runs a long action behind a progress overlay: sets [busyMessage] (UI shows
  /// the overlay), runs it through [_runGuarded] (error handling + notify), then
  /// clears the overlay. Pairs with the off-isolate key derivation in the vault
  /// so the overlay actually animates instead of freezing.
  Future<void> cancelBusyOperation() async {
    final cancel = _busyCancelAction;
    if (cancel == null || _busyCancellationRequested) return;
    _busyCancellationRequested = true;
    _notify();
    try {
      await cancel();
    } catch (error) {
      _errorMessage = _messages.errorCancelNfcFailed('$error');
    } finally {
      _notify();
    }
  }

  Future<void> _runBusy(
    String message,
    Future<void> Function() action, {
    Future<void> Function()? onCancel,
    bool awaitingCard = false,
  }) async {
    _busyMessage = message;
    _busyCancelAction = onCancel;
    _busyCancellationRequested = false;
    _awaitingCard = awaitingCard;
    _notify();
    try {
      await _runGuarded(action);
    } finally {
      _busyMessage = null;
      _busyCancelAction = null;
      _busyCancellationRequested = false;
      _awaitingCard = false;
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
      _errorMessage = _messages.errorOperationFailed('$error');
      _notify();
    }
  }
}
