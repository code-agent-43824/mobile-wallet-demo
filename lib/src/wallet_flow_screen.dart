import 'dart:async';
import 'dart:collection';
import 'dart:io';

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
import 'key_storage/backend_registry.dart';
import 'key_storage/custody_backend.dart';
import 'key_storage/external_device_demo_backend.dart';
import 'key_storage/external_device_pkcs11.dart';
import 'key_storage/key_storage_backend.dart';
import 'key_storage/phone_secure_vault.dart';
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
part 'wallet_flow_screen_connections.dart';

enum WalletFlowStage {
  loading,
  welcome,
  createWallet,
  importWallet,
  showSeed,
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

  @override
  State<WalletFlowScreen> createState() => _WalletFlowScreenState();
}

class _WalletFlowScreenState extends State<WalletFlowScreen> {
  late final WalletFlowController _controller;

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
    )..addListener(_onControllerChanged);
    _controller.loadInitialState();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            _BusyOverlay(message: message),
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
          onBackendSelected: controller.selectBackend,
          onCreatePressed: controller.goToCreateWallet,
          onImportPressed: controller.goToImportWallet,
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
          onReconnectExternalDevice: controller.isExternalBackendSelected
              ? controller.reconnectExternalDevice
              : null,
          onSimulateExternalOffline: controller.isExternalBackendSelected
              ? controller.simulateExternalDeviceOffline
              : null,
        );
      case WalletFlowStage.unlocked:
        // unlocked == the read-only dashboard. No key material is held here; the
        // send form authorizes per-op via controller.authorizeAndSubmitTransfer.
        return _UnlockedStage(
          blockchainProvider: widget.blockchainProvider,
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
          onReconnectExternalDevice: controller.isExternalBackendSelected
              ? controller.reconnectExternalDevice
              : null,
          onDisconnectExternalSession: controller.isExternalBackendSelected
              ? controller.disconnectExternalSession
              : null,
          onSimulateExternalOffline: controller.isExternalBackendSelected
              ? controller.simulateExternalDeviceOffline
              : null,
          onPingExternalDevice: controller.isExternalBackendSelected
              ? controller.pingExternalDevice
              : null,
          onReadExternalAddress: controller.isExternalBackendSelected
              ? controller.readExternalAddress
              : null,
          onRefreshExternalRuntimeState: controller.isExternalBackendSelected
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
          isExternalBackend: controller.isExternalBackendSelected,
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
