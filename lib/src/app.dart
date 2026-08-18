import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_version.dart';
import 'auth/biometric_auth.dart';
import 'blockchain/blockchain_provider.dart';
import 'design/app_theme.dart';
import 'key_storage/secure_key_value_store.dart';
import 'key_storage/custody_backend.dart';
import 'key_storage/rutoken_method_channel_adapter.dart';
import 'qr/camera_qr_scanner.dart';
import 'qr/file_qr_scanner.dart';
import 'qr/qr_scanner.dart';
import 'transactions/transaction_service.dart';
import 'transactions/hardened_transaction_service.dart';
import 'wallet_flow_screen.dart';
import 'walletconnect/reown_wallet_connect_service.dart';
import 'walletconnect/wallet_connect_preflight.dart';
import 'walletconnect/wallet_connect_service.dart';
import 'walletconnect/wc_config.dart';
import 'widgets/version_banner.dart';

/// The production [WalletConnectService]: the real reown impl on mobile when a
/// `WC_PROJECT_ID` is configured (reown is Android/iOS only), otherwise the
/// inert [UnavailableWalletConnectService]. Tests inject [FakeWalletConnectService].
WalletConnectService _defaultWalletConnectService() {
  if (isWalletConnectConfigured && (Platform.isAndroid || Platform.isIOS)) {
    return ReownWalletConnectService();
  }
  return const UnavailableWalletConnectService();
}

/// Global navigator key installed on the app's `MaterialApp`, so the
/// [CameraQrScanner] can push the camera-scanner route without a `BuildContext`
/// (the `QrScanner` seam is UI-agnostic). There is one app `Navigator`, so one
/// key for the app's lifetime is correct.
final GlobalKey<NavigatorState> _appNavigatorKey = GlobalKey<NavigatorState>();

/// The production [QrScanner]: live camera + file load on Android/iOS (via
/// [CameraQrScanner]), file load only elsewhere (Windows x64, where camera
/// plugins don't exist). Tests inject [FakeQrScanner].
QrScanner _defaultQrScanner() {
  if (Platform.isAndroid || Platform.isIOS) {
    return CameraQrScanner(navigatorKey: _appNavigatorKey);
  }
  return FileQrScanner();
}

class MobileWalletDemoApp extends StatelessWidget {
  const MobileWalletDemoApp({
    super.key,
    SecureKeyValueStore? store,
    BlockchainProvider? blockchainProvider,
    TransactionService? transactionService,
    TransactionBroadcaster? transactionBroadcaster,
    NonceProvider? nonceProvider,
    JsonRpcTransport? trackingTransport,
    BiometricAuthGateway? biometricAuthGateway,
    WalletConnectService? walletConnectService,
    WalletConnectTransactionPreflight? walletConnectPreflight,
    QrScanner? qrScanner,
    RutokenNativeAdapter? rutokenNativeAdapter,
    Locale? locale,
  }) : _store = store,
       _locale = locale,
       _blockchainProvider = blockchainProvider,
       _transactionService = transactionService,
       _transactionBroadcaster = transactionBroadcaster,
       _nonceProvider = nonceProvider,
       _trackingTransport = trackingTransport,
       _biometricAuthGateway = biometricAuthGateway,
       _walletConnectService = walletConnectService,
       _walletConnectPreflight = walletConnectPreflight,
       _qrScanner = qrScanner,
       _rutokenNativeAdapter = rutokenNativeAdapter;

  final SecureKeyValueStore? _store;
  final BlockchainProvider? _blockchainProvider;
  final TransactionService? _transactionService;
  final TransactionBroadcaster? _transactionBroadcaster;
  final NonceProvider? _nonceProvider;
  final JsonRpcTransport? _trackingTransport;
  final BiometricAuthGateway? _biometricAuthGateway;
  final WalletConnectService? _walletConnectService;
  final WalletConnectTransactionPreflight? _walletConnectPreflight;
  final QrScanner? _qrScanner;
  final RutokenNativeAdapter? _rutokenNativeAdapter;

  /// Overrides the UI language. `null` follows the system locale, falling back
  /// to Russian. Widget tests pin this so copy assertions stay deterministic.
  final Locale? _locale;

  @override
  Widget build(BuildContext context) {
    final effectiveStore = _store ?? FlutterSecureKeyValueStore();
    final effectiveRpcTransport = _trackingTransport ?? HttpJsonRpcTransport();
    final theme = buildNocturneTheme();

    return MaterialApp(
      title: 'Wallet Demo',
      debugShowCheckedModeBanner: false,
      navigatorKey: _appNavigatorKey,
      // Nocturne is a dark-only system, so both slots carry the same theme and
      // the mode is pinned — the OS light/dark setting must not change the app.
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Russian is the product's primary language: an unsupported system locale
      // falls back to it rather than to the ARB template (English).
      localeResolutionCallback: (locale, supported) {
        if (locale != null) {
          for (final candidate in supported) {
            if (candidate.languageCode == locale.languageCode) {
              return candidate;
            }
          }
        }
        return const Locale('ru');
      },
      builder: (context, child) {
        // The build strip takes real layout space above the app instead of
        // floating over it, and absorbs the status-bar inset for the content.
        return Column(
          children: [
            const VersionBanner(label: appVersionLabel),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
      home: WalletFlowScreen(
        store: effectiveStore,
        blockchainProvider:
            _blockchainProvider ??
            PublicRpcBlockchainProvider(cacheStore: effectiveStore),
        transactionService:
            _transactionService ??
            const HardenedTransactionServiceImplementation(),
        transactionBroadcaster:
            _transactionBroadcaster ?? PublicRpcTransactionBroadcaster(),
        nonceProvider: _nonceProvider ?? PublicRpcNonceProvider(),
        trackingTransport: effectiveRpcTransport,
        biometricAuthGateway:
            _biometricAuthGateway ?? defaultBiometricAuthGateway(),
        walletConnectService:
            _walletConnectService ?? _defaultWalletConnectService(),
        walletConnectPreflight:
            _walletConnectPreflight ??
            PublicRpcWalletConnectTransactionPreflight(
              rpcTransport: effectiveRpcTransport,
            ),
        qrScanner: _qrScanner ?? _defaultQrScanner(),
        rutokenNativeAdapter:
            _rutokenNativeAdapter ??
            (Platform.isAndroid ? MethodChannelRutokenNativeAdapter() : null),
      ),
    );
  }
}
