import 'package:flutter/material.dart';

import 'app_version.dart';
import 'blockchain/blockchain_provider.dart';
import 'key_storage/secure_key_value_store.dart';
import 'wallet_flow_screen.dart';
import 'widgets/version_banner.dart';

class MobileWalletDemoApp extends StatelessWidget {
  const MobileWalletDemoApp({
    super.key,
    SecureKeyValueStore? store,
    BlockchainProvider? blockchainProvider,
  }) : _store = store,
       _blockchainProvider = blockchainProvider;

  final SecureKeyValueStore? _store;
  final BlockchainProvider? _blockchainProvider;

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
      ),
    );
  }
}
