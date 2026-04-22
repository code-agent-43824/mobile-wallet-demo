import 'package:flutter/material.dart';

import 'app_version.dart';
import 'home_screen.dart';
import 'widgets/version_banner.dart';

class MobileWalletDemoApp extends StatelessWidget {
  const MobileWalletDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      home: const HomeScreen(),
    );
  }
}
