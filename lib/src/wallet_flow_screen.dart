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
import 'app_locale.dart';
import 'chain_data_controller.dart';
import 'design/app_shell.dart';
import 'design/nocturne.dart';
import 'design/platform_style.dart';
import 'key_storage/backend_registry.dart';
import 'key_storage/custody_backend.dart';
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

  /// The busy/NFC overlay lives in the ROOT overlay, not in the page, so it
  /// covers modal sheets too. Rendered inside the page it sat *below* the send
  /// sheet, which hid the card-tap prompt — and with it the cancel action.
  OverlayEntry? _busyEntry;

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
    )..addListener(_onChainDataChanged);
    _controller.loadInitialState();
  }

  /// The controllers produce user-visible strings but hold no `BuildContext`,
  /// so the active bundle is pushed into them here — on first build and again
  /// whenever the locale changes.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    _controller.messages = l10n;
    _chainData.messages = l10n;
  }

  /// The tabs render from [_chainData], so the shell must rebuild when a
  /// snapshot, network or loading state changes — not only when the wallet
  /// controller ticks.
  void _onChainDataChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onControllerChanged() {
    if (mounted) {
      // Keep the shared chain data pointed at whatever wallet is active; the
      // controller ignores a repeated address, so this is cheap on every tick.
      _chainData.setAddress(_controller.summary?.address);
      // The controller can leave the connections stage on its own (its own back
      // action, or a rejected request). Follow it back to the wallet tab,
      // otherwise the shell would keep showing an emptied Связи tab.
      if (_selectedTab == AppTab.connections &&
          _controller.stage != WalletFlowStage.connections) {
        _selectedTab = AppTab.wallet;
      }
      setState(() {});
      _syncBusyOverlay();
      _scheduleRutokenBiometricOffer();
    }
  }

  void _syncBusyOverlay() {
    final message = _controller.busyMessage;
    if (message == null) {
      _busyEntry?.remove();
      _busyEntry = null;
      return;
    }
    if (_busyEntry case final OverlayEntry entry) {
      entry.markNeedsBuild();
      return;
    }
    final entry = OverlayEntry(
      builder: (_) => _BusyOverlay(
        message: _controller.busyMessage ?? message,
        onCancel: _controller.canCancelBusyOperation
            ? _controller.cancelBusyOperation
            : null,
        cancellationRequested: _controller.isBusyCancellationRequested,
        awaitingCard: _controller.isAwaitingCard,
      ),
    );
    _busyEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
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
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(l10n.cardBiometricOfferTitle),
            content: Text(l10n.cardBiometricOfferBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cardBiometricOfferDecline),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.cardBiometricOfferAccept),
              ),
            ],
          );
        },
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
    _busyEntry?.remove();
    _busyEntry = null;
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _chainData.removeListener(_onChainDataChanged);
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
          // Pull to refresh on every tab: the balance, the asset list and the
          // history all come from the same snapshot, so one gesture reloads
          // whichever tab is showing.
          child: RefreshIndicator(
            onRefresh: _chainData.refresh,
            color: NocturneColors.accent,
            backgroundColor: NocturneColors.surface,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                NocturneSpacing.gutter,
                0,
                NocturneSpacing.gutter,
                NocturneSpacing.x8,
              ),
              child: _buildTabBody(tab),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBody(AppTab tab) {
    switch (tab) {
      case AppTab.wallet:
        return _WalletTab(
          chainData: _chainData,
          address: _controller.summary?.address ?? '—',
          transactionService: widget.transactionService,
          trackingTransport: widget.trackingTransport,
          canUnlockWithBiometrics: _controller.canUnlockWithBiometrics,
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
              }) => _controller.authorizeAndSubmitTransfer(
                snapshot: snapshot,
                fromAddress: fromAddress,
                toAddress: toAddress,
                amountText: amountText,
                asset: asset,
                tracker: tracker,
                pin: pin,
                useBiometrics: useBiometrics,
              ),
          onScan: () => _onTabSelected(AppTab.connections),
        );
      case AppTab.connections:
        return _buildStageBody();
      case AppTab.activity:
        return _ActivityTab(chainData: _chainData);
      case AppTab.settings:
        return _SettingsTab(
          chainData: _chainData,
          address: _controller.summary?.address ?? '—',
          backendLabel: _controller.backendLabel,
          currentBackendId: _controller.effectiveBackendId,
          biometricsEnabled: _controller.biometricsEnabled,
          isHardwareCustody: _controller.activeBackend is WalletCustodyBackend,
          onLock: _controller.lockWallet,
          onRefresh: _chainData.refresh,
          onListWallets: _controller.listSwitchableWallets,
          onSwitchWallet: _controller.switchActiveWallet,
          onSelectedCardProfileId: _controller.selectedCardProfileId,
          onForgetCard: _controller.forgetCard,
          // Goes straight to adoption rather than back to the welcome screen:
          // that screen's «Создать кошелёк» writes a fresh seed into the phone
          // vault, and routing here would put that one tap away from a wallet
          // the user already has.
          onConnectAnotherCard: widget.rutokenNativeAdapter == null
              ? null
              : () => _connectAnotherCard(context),
        );
    }
  }

  /// Registers an additional card from Настройки. Same prompt and same NFC wait
  /// as connecting the first one; the adopted card becomes the active wallet.
  Future<void> _connectAnotherCard(BuildContext context) async {
    final auth = await _promptForAuth(
      context,
      reason: AppLocalizations.of(context).cardAdoptPinReason,
      biometricsOffered: false,
    );
    final pin = auth?.pin;
    if (pin == null) return;
    await _controller.adoptExistingRutoken(pin: pin);
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
                          const _Header(),
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
        // The card has its own provisioning stages, so this one is always the
        // phone wallet.
        return _PinSetupStage(
          title: 'Кошелёк на этом телефоне',
          description:
              'Сначала задайте PIN — им будет зашифрован кошелёк. Потом '
              'приложение создаст seed-фразу и покажет её один раз, чтобы вы '
              'сохранили резервную копию.',
          actionLabel: 'Создать кошелёк',
          onSubmit: controller.createWallet,
          onBack: controller.goToWelcome,
        );
      case WalletFlowStage.importWallet:
        return _ImportWalletStage(
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
          biometricsEnabled: controller.biometricsEnabled,
          onUnlock: controller.unlockWallet,
          onUnlockWithBiometrics: controller.canUnlockWithBiometrics
              ? controller.unlockWithBiometrics
              : null,
        );
      case WalletFlowStage.unlocked:
        // Reached only through the tab shell, which renders _WalletTab; this
        // arm keeps the switch exhaustive.
        return const SizedBox.shrink();
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
