import 'dart:io';

import 'package:flutter/material.dart';

import 'app_version.dart';
import 'auth/biometric_auth.dart';
import 'blockchain/blockchain_provider.dart';
import 'key_storage/secure_key_value_store.dart';
import 'qr/file_qr_scanner.dart';
import 'qr/qr_scanner.dart';
import 'transactions/transaction_service.dart';
import 'transactions/hardened_transaction_service.dart';
import 'wallet_flow_screen.dart';
import 'walletconnect/reown_wallet_connect_service.dart';
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
    QrScanner? qrScanner,
  }) : _store = store,
       _blockchainProvider = blockchainProvider,
       _transactionService = transactionService,
       _transactionBroadcaster = transactionBroadcaster,
       _nonceProvider = nonceProvider,
       _trackingTransport = trackingTransport,
       _biometricAuthGateway = biometricAuthGateway,
       _walletConnectService = walletConnectService,
       _qrScanner = qrScanner;

  final SecureKeyValueStore? _store;
  final BlockchainProvider? _blockchainProvider;
  final TransactionService? _transactionService;
  final TransactionBroadcaster? _transactionBroadcaster;
  final NonceProvider? _nonceProvider;
  final JsonRpcTransport? _trackingTransport;
  final BiometricAuthGateway? _biometricAuthGateway;
  final WalletConnectService? _walletConnectService;
  final QrScanner? _qrScanner;

  @override
  Widget build(BuildContext context) {
    final effectiveStore = _store ?? FlutterSecureKeyValueStore();
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2D6CDF)),
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'Mobile Wallet Demo',
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) {
        return Stack(
          children: [
            if (child case final Widget currentChild) currentChild,
            const SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.only(top: 12, right: 12),
                  child: VersionBanner(label: appVersionLabel),
                ),
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
        trackingTransport: _trackingTransport ?? HttpJsonRpcTransport(),
        biometricAuthGateway:
            _biometricAuthGateway ?? defaultBiometricAuthGateway(),
        walletConnectService:
            _walletConnectService ?? _defaultWalletConnectService(),
        qrScanner: _qrScanner ?? FileQrScanner(),
      ),
    );
  }
}
