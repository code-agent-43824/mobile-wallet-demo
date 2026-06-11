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
  }) {
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
  }

  late final PhoneSecureVault _vault;
  late final ExternalDeviceDemoBackend _externalDeviceBackend;
  late final WalletBackendRegistry _backendRegistry;

  /// Stateless signing authorizer used by the unlocked send flow.
  final WalletOperationAuthorizer walletOperationAuthorizer =
      const WalletOperationAuthorizer();

  WalletFlowStage _stage = WalletFlowStage.loading;
  StoredWalletSummary? _summary;
  WalletMaterial? _material;
  String? _seedPhraseToShow;
  String? _errorMessage;
  String? _pendingBiometricPin;
  String? _selectedBackendId;
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
      _stage = summary == null
          ? WalletFlowStage.welcome
          : WalletFlowStage.locked;
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
    await _runGuarded(() async {
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
        _stage = WalletFlowStage.locked;
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
    await _runGuarded(() async {
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
        _stage = WalletFlowStage.locked;
      } else {
        _stage = WalletFlowStage.biometricPrompt;
      }
    });
  }

  Future<void> unlockWallet(String pin) async {
    await _runGuarded(() async {
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
      _stage = WalletFlowStage.locked;
      activeBackend.lock();
      if (activeBackend is ExternalDeviceDemoBackend) {
        _externalRuntimeState = await _externalDeviceBackend.loadRuntimeState();
      }
    });
  }

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
      _material = null;
      _stage = WalletFlowStage.locked;
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
      _material = null;
      _stage = WalletFlowStage.locked;
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

  Future<void> _runGuarded(Future<void> Function() action) async {
    try {
      await action();
      _errorMessage = null;
      _notify();
    } on VaultFailure catch (error) {
      _errorMessage = error.message;
      _notify();
    }
  }
}
