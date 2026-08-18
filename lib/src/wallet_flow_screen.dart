import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zxing2/qrcode.dart';

import 'airgap/account_export.dart';
import 'airgap/eip4527.dart';
import 'airgap/eip4527_inbound.dart';
import 'airgap/eip4527_transaction_preview.dart';
import 'auth/biometric_auth.dart';
import 'auth/external_digest_signer.dart';
import 'auth/wallet_operation_auth.dart';
import 'blockchain/blockchain_provider.dart';
import 'blockchain/network_config.dart';
import '../l10n/app_localizations.dart';
import 'chain_data_controller.dart';
import 'design/app_shell.dart';
import 'design/nocturne.dart';
import 'design/platform_style.dart';
import 'key_storage/backend_registry.dart';
import 'key_storage/custody_backend.dart';
import 'key_storage/external_device_demo_backend.dart';
import 'key_storage/external_device_pkcs11.dart';
import 'key_storage/key_storage_backend.dart';
import 'key_storage/phone_secure_vault.dart';
import 'key_storage/rutoken_biometric_pin_store.dart';
import 'key_storage/rutoken_provisioning.dart';
import 'key_storage/secure_key_value_store.dart';
import 'qr/qr_scanner.dart';
import 'qr/ur_qr.dart';
import 'transactions/hardened_transaction_service.dart';
import 'transactions/transaction_service.dart';
import 'transactions/transaction_tracker.dart';
import 'walletconnect/wallet_connect_inbound.dart';
import 'walletconnect/wallet_connect_preflight.dart';
import 'walletconnect/wallet_connect_service.dart';
import 'walletconnect/wallet_connect_v2.dart';

// The wallet state machine + every domain action live in a widget-free
// WalletFlowController; the presentational widgets for each WalletFlowStage live
// in part files. This orchestrator just owns the controller and renders its
// current stage.
part 'wallet_flow_controller.dart';
part 'wallet_flow_screen_widgets.dart';
part 'wallet_flow_screen_onboarding.dart';
part 'wallet_flow_screen_unlocked.dart';
part 'wallet_flow_screen_tabs.dart';
part 'wallet_flow_screen_connections.dart';

enum WalletFlowStage {
  loading,
  welcome,
  createWallet,
  importWallet,
  showSeed,
  rutokenCreate,
  rutokenImport,
  rutokenBackup,
  biometricPrompt,
  locked,
  unlocked,
  connections,
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
    required this.walletConnectService,
    required this.walletConnectPreflight,
    required this.qrScanner,
    this.rutokenNativeAdapter,
    super.key,
  });

  final SecureKeyValueStore store;
  final BlockchainProvider blockchainProvider;
  final TransactionService transactionService;
  final TransactionBroadcaster transactionBroadcaster;
  final NonceProvider nonceProvider;
  final JsonRpcTransport trackingTransport;
  final BiometricAuthGateway biometricAuthGateway;
  final WalletConnectService walletConnectService;
  final WalletConnectTransactionPreflight walletConnectPreflight;
  final QrScanner qrScanner;
  final RutokenNativeAdapter? rutokenNativeAdapter;

  @override
  State<WalletFlowScreen> createState() => _WalletFlowScreenState();
}

class _WalletFlowScreenState extends State<WalletFlowScreen> {
  late final WalletFlowController _controller;
  late final ChainDataController _chainData;

  /// Which tab of the redesigned shell is showing. Pure presentation state, so
  /// it lives here rather than in the domain controller.
  AppTab _selectedTab = AppTab.wallet;
  bool _rutokenBiometricDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = WalletFlowController(
      store: widget.store,
      biometricAuthGateway: widget.biometricAuthGateway,
      walletConnectService: widget.walletConnectService,
      walletConnectPreflight: widget.walletConnectPreflight,
      transactionService: widget.transactionService,
      transactionBroadcaster: widget.transactionBroadcaster,
      nonceProvider: widget.nonceProvider,
      qrScanner: widget.qrScanner,
      rutokenNativeAdapter: widget.rutokenNativeAdapter,
    )..addListener(_onControllerChanged);
    _chainData = ChainDataController(
      blockchainProvider: widget.blockchainProvider,
    );
    _controller.loadInitialState();
  }

  void _onControllerChanged() {
    if (mounted) {
      // Keep the shared chain data pointed at whatever wallet is active; the
      // controller ignores a repeated address, so this is cheap on every tick.
      _chainData.setAddress(_controller.summary?.address);
      setState(() {});
      _scheduleRutokenBiometricOffer();
    }
  }

  void _scheduleRutokenBiometricOffer() {
    if (_rutokenBiometricDialogOpen ||
        !_controller.hasPendingRutokenBiometricOffer) {
      return;
    }
    _rutokenBiometricDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _rutokenBiometricDialogOpen = false;
        return;
      }
      final enabled = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Использовать биометрию для Рутокена?'),
          content: const Text(
            'Можно сохранить PIN этой карты в отдельном защищённом хранилище. '
            'В следующих операциях вместо ручного ввода PIN приложение сначала '
            'потребует системную биометрическую проверку смартфона.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Не сохранять'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Сохранить под биометрией'),
            ),
          ],
        ),
      );
      if (mounted) {
        await _controller.completeRutokenBiometricOffer(enabled ?? false);
      }
      _rutokenBiometricDialogOpen = false;
      if (mounted) {
        _scheduleRutokenBiometricOffer();
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _chainData.dispose();
    super.dispose();
  }

  /// Whether the current stage is part of the main app (which the redesign
  /// presents as four tabs) rather than the onboarding/auth flow (which stays
  /// full-screen, with no tab bar).
  bool get _isMainAppStage =>
      _controller.stage == WalletFlowStage.unlocked ||
      _controller.stage == WalletFlowStage.connections;

  void _onTabSelected(AppTab tab) {
    // `connections` is still a controller stage, so selecting its tab enters
    // that stage and leaving it returns to the dashboard.
    if (tab == AppTab.connections) {
      if (_controller.stage != WalletFlowStage.connections) {
        _controller.openConnections();
      }
    } else if (_controller.stage == WalletFlowStage.connections) {
      _controller.closeConnections();
    }
    setState(() => _selectedTab = tab);
  }

  @override
  Widget build(BuildContext context) {
    if (_isMainAppStage) {
      return _buildMainApp(context);
    }
    return _buildOnboarding(context);
  }

  Widget _buildMainApp(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The tab the shell shows follows the controller when it drives the stage
    // itself (e.g. an incoming WalletConnect request opens Connections).
    final tab = _controller.stage == WalletFlowStage.connections
        ? AppTab.connections
        : _selectedTab;
    final errorMessage = _controller.errorMessage;

    return Stack(
      children: [
        AppShell(
          title: switch (tab) {
            AppTab.wallet => l10n.tabWallet,
            AppTab.activity => l10n.tabActivity,
            AppTab.connections => l10n.tabConnections,
            AppTab.settings => l10n.tabSettings,
          },
          tabs: <AppTabItem>[
            AppTabItem(
              tab: AppTab.wallet,
              label: l10n.tabWallet,
              icon: Icons.account_balance_wallet_outlined,
            ),
            AppTabItem(
              tab: AppTab.activity,
              label: l10n.tabActivity,
              icon: Icons.history,
            ),
            AppTabItem(
              tab: AppTab.connections,
              label: l10n.tabConnections,
              icon: Icons.hub_outlined,
            ),
            AppTabItem(
              tab: AppTab.settings,
              label: l10n.tabSettings,
              icon: Icons.settings_outlined,
            ),
          ],
          currentTab: tab,
          onTabSelected: _onTabSelected,
          banner: errorMessage == null
              ? null
              : Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NocturneSpacing.gutter,
                    0,
                    NocturneSpacing.gutter,
                    NocturneSpacing.x3,
                  ),
                  child: _ErrorBanner(message: errorMessage),
                ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              NocturneSpacing.gutter,
              0,
              NocturneSpacing.gutter,
              NocturneSpacing.x8,
            ),
            child: _buildTabBody(tab),
          ),
        ),
        if (_controller.busyMessage case final String message)
          _BusyOverlay(
            message: message,
            onCancel: _controller.canCancelBusyOperation
                ? _controller.cancelBusyOperation
                : null,
            cancellationRequested: _controller.isBusyCancellationRequested,
          ),
      ],
    );
  }

  Widget _buildTabBody(AppTab tab) {
    switch (tab) {
      case AppTab.wallet:
      case AppTab.connections:
        // The dashboard and the connections screen keep their existing bodies;
        // 13.3 restyles the wallet content itself.
        return _buildStageBody();
      case AppTab.activity:
        return _ActivityTab(chainData: _chainData);
      case AppTab.settings:
        return _SettingsTab(
          chainData: _chainData,
          address: _controller.summary?.address ?? '—',
          backendLabel: _controller.backendLabel,
          biometricsEnabled: _controller.biometricsEnabled,
          isHardwareCustody:
              _controller.activeBackend is WalletCustodyBackend &&
              _controller.activeBackend is! ExternalDeviceDemoBackend,
          externalRuntimeState: _controller.externalRuntimeState,
          onLock: _controller.lockWallet,
        );
    }
  }

  Widget _buildOnboarding(BuildContext context) {
    final theme = Theme.of(context);
    final errorMessage = _controller.errorMessage;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
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
                          _Header(stage: _controller.stage),
                          if (errorMessage != null) ...[
                            const SizedBox(height: 20),
                            _ErrorBanner(message: errorMessage),
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
          if (_controller.busyMessage case final String message)
            _BusyOverlay(
              message: message,
              onCancel: _controller.canCancelBusyOperation
                  ? _controller.cancelBusyOperation
                  : null,
              cancellationRequested: _controller.isBusyCancellationRequested,
            ),
        ],
      ),
    );
  }

  Widget _buildStageBody() {
    final controller = _controller;
    switch (controller.stage) {
      case WalletFlowStage.loading:
        return const Center(child: CircularProgressIndicator());
      case WalletFlowStage.welcome:
        return _WelcomeStage(
          backendEntries: controller.backendEntries,
          selectedBackendId: controller.effectiveBackendId,
          isExternalBackendSelected: controller.isExternalBackendSelected,
          isRutokenSelected: controller.isRutokenSelected,
          onBackendSelected: controller.selectBackend,
          onCreatePressed: controller.goToCreateWallet,
          onImportPressed: controller.goToImportWallet,
          onRutokenDiagnostic: controller.hasRutokenNativeAdapter
              ? controller.runRutokenTransportDiagnostic
              : null,
          onRutokenCreate: controller.hasRutokenNativeAdapter
              ? controller.goToRutokenCreate
              : null,
          onRutokenImport: controller.hasRutokenNativeAdapter
              ? controller.goToRutokenImport
              : null,
          onRutokenAdopt: controller.hasRutokenNativeAdapter
              ? controller.adoptExistingRutoken
              : null,
          rutokenDiagnosticResult: controller.rutokenDiagnosticResult,
          rutokenProvisioningResult: controller.rutokenProvisioningResult,
        );
      case WalletFlowStage.createWallet:
        return _PinSetupStage(
          title: controller.isExternalBackendSelected
              ? 'Подключить demo NFC-устройство'
              : 'Создать новый кошелёк',
          description: controller.isExternalBackendSelected
              ? 'Это отдельная UX-ветка для внешнего backend. Задаём PIN устройства для demo-подписанта и сохраняем linked-device runtime.'
              : 'Сначала задаём обязательный PIN. После этого приложение создаст seed-фразу и покажет её один раз для резервного сохранения.',
          actionLabel: controller.isExternalBackendSelected
              ? 'Подключить устройство'
              : 'Создать кошелёк',
          onSubmit: controller.createWallet,
          onBack: controller.goToWelcome,
        );
      case WalletFlowStage.importWallet:
        return _ImportWalletStage(
          isExternalBackendSelected: controller.isExternalBackendSelected,
          onSubmit: controller.importWallet,
          onBack: controller.goToWelcome,
        );
      case WalletFlowStage.showSeed:
        return _SeedPhraseStage(
          mnemonic: controller.seedPhraseToShow ?? '',
          onContinue: controller.finishSeedBackup,
        );
      case WalletFlowStage.rutokenCreate:
        return _RutokenCreateStage(
          onGenerate: controller.prepareRutokenGeneratedBackup,
          onBack: controller.goToWelcome,
        );
      case WalletFlowStage.rutokenImport:
        return _RutokenImportStage(
          onSubmit: controller.provisionImportedRutoken,
          onBack: controller.goToWelcome,
        );
      case WalletFlowStage.rutokenBackup:
        final backup = controller.rutokenGeneratedBackup;
        if (backup == null) {
          return const SizedBox.shrink();
        }
        return _RutokenBackupStage(
          backup: backup,
          onProvision: controller.provisionGeneratedRutoken,
          onBack: controller.goToWelcome,
        );
      case WalletFlowStage.biometricPrompt:
        return _BiometricPromptStage(
          isAvailable: controller.biometricsAvailable,
          isWindowsSimulation: Platform.isWindows,
          onSkip: () => controller.completeBiometricChoice(false),
          onEnable: controller.biometricsAvailable
              ? () => controller.completeBiometricChoice(true)
              : null,
        );
      case WalletFlowStage.locked:
        return _LockedStage(
          summary: controller.summary,
          backendLabel: controller.backendLabel,
          isExternalBackend: controller.isExternalBackendSelected,
          externalRuntimeState: controller.externalRuntimeState,
          biometricsEnabled: controller.biometricsEnabled,
          onUnlock: controller.unlockWallet,
          onUnlockWithBiometrics: controller.canUnlockWithBiometrics
              ? controller.unlockWithBiometrics
              : null,
          onReconnectExternalDevice: controller.isDemoExternalBackendSelected
              ? controller.reconnectExternalDevice
              : null,
          onSimulateExternalOffline: controller.isDemoExternalBackendSelected
              ? controller.simulateExternalDeviceOffline
              : null,
        );
      case WalletFlowStage.unlocked:
        // unlocked == the read-only dashboard. No key material is held here; the
        // send form authorizes per-op via controller.authorizeAndSubmitTransfer.
        return _UnlockedStage(
          chainData: _chainData,
          transactionService: widget.transactionService,
          trackingTransport: widget.trackingTransport,
          activeBackend: controller.activeBackend,
          summary: controller.summary,
          backendLabel: controller.backendLabel,
          externalRuntimeState: controller.externalRuntimeState,
          biometricsEnabled: controller.biometricsEnabled,
          canUnlockWithBiometrics: controller.canUnlockWithBiometrics,
          onAuthorizeAndSubmit:
              ({
                required snapshot,
                required fromAddress,
                required toAddress,
                required amountText,
                required asset,
                required tracker,
                pin,
                useBiometrics = false,
              }) => controller.authorizeAndSubmitTransfer(
                snapshot: snapshot,
                fromAddress: fromAddress,
                toAddress: toAddress,
                amountText: amountText,
                asset: asset,
                tracker: tracker,
                pin: pin,
                useBiometrics: useBiometrics,
              ),
          onLock: controller.lockWallet,
          isHardwareCustody:
              controller.activeBackend is WalletCustodyBackend &&
              controller.activeBackend is! ExternalDeviceDemoBackend,
          onReconnectExternalDevice: controller.isDemoExternalBackendSelected
              ? controller.reconnectExternalDevice
              : null,
          onDisconnectExternalSession: controller.isDemoExternalBackendSelected
              ? controller.disconnectExternalSession
              : null,
          onSimulateExternalOffline: controller.isDemoExternalBackendSelected
              ? controller.simulateExternalDeviceOffline
              : null,
          onPingExternalDevice: controller.isDemoExternalBackendSelected
              ? controller.pingExternalDevice
              : null,
          onReadExternalAddress: controller.isDemoExternalBackendSelected
              ? controller.readExternalAddress
              : null,
          onRefreshExternalRuntimeState:
              controller.isDemoExternalBackendSelected
              ? controller.refreshExternalRuntimeState
              : null,
          onOpenConnections: controller.openConnections,
        );
      case WalletFlowStage.connections:
        return _ConnectionsStage(
          isAvailable: controller.isWalletConnectAvailable,
          sessions: controller.walletConnectSessions,
          pendingProposal: controller.pendingProposal,
          pendingRequest: controller.pendingRequest,
          pendingRequestPreview: controller.pendingRequestPreview,
          pendingRequestPreviewError: controller.pendingRequestPreviewError,
          isPendingRequestPreviewLoading:
              controller.isPendingRequestPreviewLoading,
          airGapAccountExportPayload: controller.airGapAccountExportPayload,
          airGapRequest: controller.airGapRequest,
          airGapRequestPreview: controller.airGapRequestPreview,
          airGapResponsePayload: controller.airGapResponsePayload,
          walletAddress: controller.summary?.address,
          isQrCameraAvailable: controller.isQrCameraAvailable,
          isQrFileLoadAvailable: controller.isQrFileLoadAvailable,
          canUnlockWithBiometrics: controller.canUnlockWithBiometrics,
          onScanQrCamera: controller.scanQrWithCamera,
          onLoadQrFromFile: controller.loadQrFromFile,
          onPair: controller.pairWalletConnect,
          onApprove: controller.approvePendingProposal,
          onReject: controller.rejectPendingProposal,
          onApproveRequest: controller.approvePendingRequest,
          onRejectRequest: controller.rejectPendingRequest,
          onPrepareAirGapAccountExport: controller.prepareAirGapAccountExport,
          onScanAirGapRequest: controller.scanAirGapRequestWithCamera,
          onLoadAirGapRequest: controller.loadAirGapRequestFromFile,
          onSignAirGapRequest: controller.signPendingAirGapRequest,
          onClearAirGapRequest: controller.clearAirGapRequest,
          onDisconnect: (topic) =>
              controller.disconnectWalletConnectSession(topic: topic),
          onBack: controller.closeConnections,
        );
    }
  }
}
