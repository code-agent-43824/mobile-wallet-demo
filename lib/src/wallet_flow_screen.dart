import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'auth/biometric_auth.dart';
import 'auth/wallet_operation_auth.dart';
import 'blockchain/blockchain_provider.dart';
import 'blockchain/network_config.dart';
import 'key_storage/backend_registry.dart';
import 'key_storage/external_device_demo_backend.dart';
import 'key_storage/external_device_pkcs11.dart';
import 'key_storage/key_storage_backend.dart';
import 'key_storage/phone_secure_vault.dart';
import 'key_storage/secure_key_value_store.dart';
import 'sessions/remote_signer_registry.dart';
import 'sessions/remote_signing_session.dart';
import 'transactions/hardened_transaction_service.dart';
import 'transactions/transaction_service.dart';
import 'transactions/transaction_tracker.dart';

// The presentational widgets for each WalletFlowStage live in part files to keep
// this orchestrator focused on state-machine wiring. See:
part 'wallet_flow_screen_widgets.dart';
part 'wallet_flow_screen_onboarding.dart';
part 'wallet_flow_screen_unlocked.dart';

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
    required this.trackingTransport,
    required this.biometricAuthGateway,
    super.key,
  });

  final SecureKeyValueStore store;
  final BlockchainProvider blockchainProvider;
  final TransactionService transactionService;
  final TransactionBroadcaster transactionBroadcaster;
  final NonceProvider nonceProvider;
  final JsonRpcTransport trackingTransport;
  final BiometricAuthGateway biometricAuthGateway;

  @override
  State<WalletFlowScreen> createState() => _WalletFlowScreenState();
}

class _WalletFlowScreenState extends State<WalletFlowScreen> {
  late final PhoneSecureVault _vault;
  late final ExternalDeviceDemoBackend _externalDeviceBackend;
  late final WalletBackendRegistry _backendRegistry;
  final WalletOperationAuthorizer _walletOperationAuthorizer =
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

  @override
  void initState() {
    super.initState();
    _vault = PhoneSecureVault(
      store: widget.store,
      biometricAuth: widget.biometricAuthGateway,
    );
    _externalDeviceBackend = ExternalDeviceDemoBackend(store: widget.store);
    _backendRegistry = WalletBackendRegistry(
      store: widget.store,
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
    _loadInitialState();
  }

  KeyStorageBackend get _activeBackend {
    final selectedBackendId = _selectedBackendId;
    if (selectedBackendId != null) {
      final backend = _backendRegistry.backendById(selectedBackendId);
      if (backend != null) {
        return backend;
      }
    }
    return _vault;
  }

  bool get _isExternalBackendSelected =>
      _activeBackend is ExternalDeviceKeyStorageBackend;

  Future<void> _selectBackend(String backendId) async {
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

  Future<void> _loadInitialState() async {
    try {
      final selectedBackendId = await _backendRegistry.loadSelectedBackendId();
      final activeBackend =
          _backendRegistry.backendById(selectedBackendId) ?? _vault;
      final summary = await activeBackend.getWalletSummary();
      final biometricsEnabled = await activeBackend.isBiometricUnlockEnabled();
      final biometricsAvailable = await activeBackend
          .isBiometricUnlockAvailable();
      final externalRuntimeState = activeBackend is ExternalDeviceDemoBackend
          ? await activeBackend.loadRuntimeState()
          : null;
      if (!mounted) {
        return;
      }

      setState(() {
        _selectedBackendId = selectedBackendId;
        _summary = summary;
        _externalRuntimeState = externalRuntimeState;
        _biometricsEnabled = biometricsEnabled;
        _biometricsAvailable = biometricsAvailable;
        _stage = summary == null
            ? WalletFlowStage.welcome
            : WalletFlowStage.locked;
      });
    } on VaultFailure catch (error) {
      // A corrupt or unsupported at-rest payload must not crash startup; surface
      // it and fall back to the welcome flow so the wallet can be re-created.
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _stage = WalletFlowStage.welcome;
      });
    }
  }

  Future<void> _createWallet({required String pin}) async {
    await _runGuarded(() async {
      final backend = _activeBackend;
      final material = await backend.createWallet(pin: pin);
      _summary = StoredWalletSummary(
        address: material.address,
        backendId: backend.backendId,
        createdAtUtc: DateTime.now().toUtc(),
      );
      _material = material;
      _pendingBiometricPin = pin;
      _lastUnlockAuthMethod = _isExternalBackendSelected
          ? WalletAuthMethod.externalDevice
          : WalletAuthMethod.pin;
      if (_isExternalBackendSelected) {
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

  Future<void> _importWallet({
    required String mnemonic,
    required String pin,
  }) async {
    await _runGuarded(() async {
      final backend = _activeBackend;
      final material = await backend.importWallet(mnemonic: mnemonic, pin: pin);
      _summary = StoredWalletSummary(
        address: material.address,
        backendId: backend.backendId,
        createdAtUtc: DateTime.now().toUtc(),
      );
      _material = material;
      _pendingBiometricPin = pin;
      _seedPhraseToShow = null;
      _lastUnlockAuthMethod = _isExternalBackendSelected
          ? WalletAuthMethod.externalDevice
          : WalletAuthMethod.pin;
      if (_isExternalBackendSelected) {
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

  Future<void> _unlockWallet(String pin) async {
    await _runGuarded(() async {
      _material = await _activeBackend.unlock(pin: pin);
      _lastUnlockAuthMethod = _activeBackend is ExternalDeviceKeyStorageBackend
          ? WalletAuthMethod.externalDevice
          : WalletAuthMethod.pin;
      if (_activeBackend is ExternalDeviceDemoBackend) {
        _externalRuntimeState = await _externalDeviceBackend.loadRuntimeState();
      }
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

  Future<void> _completeBiometricChoice(bool enabled) async {
    await _runGuarded(() async {
      final pin = _pendingBiometricPin;
      if (enabled) {
        if (pin == null || pin.isEmpty) {
          throw const VaultFailure(
            'Не удалось включить биометрию: PIN текущей сессии недоступен.',
          );
        }
        await _activeBackend.setBiometricUnlockEnabled(enabled: true, pin: pin);
      } else {
        await _activeBackend.setBiometricUnlockEnabled(enabled: false, pin: '');
      }

      _biometricsEnabled = enabled;
      _material = null;
      _pendingBiometricPin = null;
      _seedPhraseToShow = null;
      _stage = WalletFlowStage.locked;
      _activeBackend.lock();
      if (_activeBackend is ExternalDeviceDemoBackend) {
        _externalRuntimeState = await _externalDeviceBackend.loadRuntimeState();
      }
    });
  }

  Future<void> _unlockWithBiometrics() async {
    await _runGuarded(() async {
      _material = await _activeBackend.unlockWithBiometrics();
      _lastUnlockAuthMethod = WalletAuthMethod.biometric;
      _stage = WalletFlowStage.unlocked;
    });
  }

  Future<void> _refreshExternalRuntimeState() async {
    if (_activeBackend is! ExternalDeviceDemoBackend) {
      return;
    }
    final runtimeState = await (_activeBackend as ExternalDeviceDemoBackend)
        .loadRuntimeState();
    if (!mounted) {
      return;
    }
    setState(() {
      _externalRuntimeState = runtimeState;
    });
  }

  Future<void> _simulateExternalDeviceOffline() async {
    await _runGuarded(() async {
      await _externalDeviceBackend.simulateDeviceUnavailable();
      _material = null;
      _stage = WalletFlowStage.locked;
      await _refreshExternalRuntimeState();
    });
  }

  Future<void> _reconnectExternalDevice() async {
    await _runGuarded(() async {
      await _externalDeviceBackend.reconnectDevice();
      await _refreshExternalRuntimeState();
    });
  }

  Future<void> _disconnectExternalSession() async {
    await _runGuarded(() async {
      await _externalDeviceBackend.disconnectSession();
      _material = null;
      _stage = WalletFlowStage.locked;
      await _refreshExternalRuntimeState();
    });
  }

  Future<void> _performExternalPkcs11Operation(
    ExternalDevicePkcs11Operation operation,
  ) async {
    await _runGuarded(() async {
      await _externalDeviceBackend.performPkcs11Operation(operation);
      await _refreshExternalRuntimeState();
    });
  }

  void _lockWallet() {
    _activeBackend.lock();
    if (_activeBackend is ExternalDeviceDemoBackend) {
      _externalDeviceBackend.loadRuntimeState().then((runtimeState) {
        if (!mounted) {
          return;
        }
        setState(() {
          _externalRuntimeState = runtimeState;
        });
      });
    }
    setState(() {
      _material = null;
      _pendingBiometricPin = null;
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
          backendEntries: _backendRegistry.entries,
          selectedBackendId:
              _selectedBackendId ?? _backendRegistry.defaultBackendId,
          isExternalBackendSelected: _isExternalBackendSelected,
          onBackendSelected: _selectBackend,
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
          title: _isExternalBackendSelected
              ? 'Подключить demo NFC-устройство'
              : 'Создать новый кошелёк',
          description: _isExternalBackendSelected
              ? 'Это отдельная UX-ветка для внешнего backend. Задаём PIN устройства для demo-подписанта и сохраняем linked-device runtime.'
              : 'Сначала задаём обязательный PIN. После этого приложение создаст seed-фразу и покажет её один раз для резервного сохранения.',
          actionLabel: _isExternalBackendSelected
              ? 'Подключить устройство'
              : 'Создать кошелёк',
          onSubmit: _createWallet,
          onBack: _goToWelcome,
        );
      case WalletFlowStage.importWallet:
        return _ImportWalletStage(
          isExternalBackendSelected: _isExternalBackendSelected,
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
          isAvailable: _biometricsAvailable,
          isWindowsSimulation: Platform.isWindows,
          onSkip: () => _completeBiometricChoice(false),
          onEnable: _biometricsAvailable
              ? () => _completeBiometricChoice(true)
              : null,
        );
      case WalletFlowStage.locked:
        return _LockedStage(
          summary: _summary,
          backendLabel:
              _backendRegistry
                  .descriptorById(
                    _summary?.backendId ?? _selectedBackendId ?? '',
                  )
                  ?.label ??
              'Unknown backend',
          isExternalBackend: _activeBackend is ExternalDeviceKeyStorageBackend,
          externalRuntimeState: _externalRuntimeState,
          biometricsEnabled: _biometricsEnabled,
          onUnlock: _unlockWallet,
          onUnlockWithBiometrics: _biometricsEnabled && _biometricsAvailable
              ? _unlockWithBiometrics
              : null,
          onReconnectExternalDevice: _isExternalBackendSelected
              ? _reconnectExternalDevice
              : null,
          onSimulateExternalOffline: _isExternalBackendSelected
              ? _simulateExternalDeviceOffline
              : null,
        );
      case WalletFlowStage.unlocked:
        return _UnlockedStage(
          blockchainProvider: widget.blockchainProvider,
          transactionService: widget.transactionService,
          transactionBroadcaster: widget.transactionBroadcaster,
          nonceProvider: widget.nonceProvider,
          trackingTransport: widget.trackingTransport,
          walletOperationAuthorizer: _walletOperationAuthorizer,
          activeBackend: _activeBackend,
          authMethod: _lastUnlockAuthMethod,
          material: _material,
          summary: _summary,
          backendLabel:
              _backendRegistry
                  .descriptorById(
                    _summary?.backendId ?? _selectedBackendId ?? '',
                  )
                  ?.label ??
              'Unknown backend',
          externalRuntimeState: _externalRuntimeState,
          biometricsEnabled: _biometricsEnabled,
          onLock: _lockWallet,
          onReconnectExternalDevice: _isExternalBackendSelected
              ? _reconnectExternalDevice
              : null,
          onDisconnectExternalSession: _isExternalBackendSelected
              ? _disconnectExternalSession
              : null,
          onSimulateExternalOffline: _isExternalBackendSelected
              ? _simulateExternalDeviceOffline
              : null,
          onPingExternalDevice: _isExternalBackendSelected
              ? () => _performExternalPkcs11Operation(
                  const ExternalDevicePkcs11Operation(
                    kind: ExternalDevicePkcs11OperationKind.probeSession,
                  ),
                )
              : null,
          onReadExternalAddress: _isExternalBackendSelected
              ? () => _performExternalPkcs11Operation(
                  const ExternalDevicePkcs11Operation(
                    kind: ExternalDevicePkcs11OperationKind.readPublicAddress,
                  ),
                )
              : null,
          onRefreshExternalRuntimeState: _isExternalBackendSelected
              ? _refreshExternalRuntimeState
              : null,
        );
    }
  }
}
