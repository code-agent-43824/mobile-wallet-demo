// The iOS 26+ path of AppShell: the tabs are the system's UITabBarController
// (uikit_tab_bar), here with a fake native side standing in for UIKit.
// Flutter 3.50 deprecates the library in favour of package:material_ui;
// see docs/PLAN.md for the migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/app.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/phone_secure_vault.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:uikit_tab_bar/uikit_tab_bar.dart';

const MethodCodec _codec = StandardMethodCodec();

/// Records what the plugin asks UIKit for and delivers UIKit's events.
class _FakeUiKit {
  _FakeUiKit(this.tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        if (call.method == 'create') {
          final args = call.arguments as Map<Object?, Object?>;
          viewId = args['id']! as int;
          final params =
              const StandardMessageCodec().decodeMessage(
                    ByteData.sublistView(args['params']! as Uint8List),
                  )
                  as Map<Object?, Object?>;
          states.add(params['state']! as Map<Object?, Object?>);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            MethodChannel('uikit_tab_bar/view_$viewId'),
            (call) async {
              if (call.method == 'update') {
                final args = call.arguments as Map<Object?, Object?>;
                states.add(args['state']! as Map<Object?, Object?>);
              }
              return null;
            },
          );
        }
        return null;
      },
    );
  }

  final WidgetTester tester;
  int? viewId;
  final List<Map<Object?, Object?>> states = <Map<Object?, Object?>>[];

  Future<void> tap(String id) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'uikit_tab_bar/view_$viewId',
      _codec.encodeMethodCall(
        MethodCall('selected', <String, Object?>{'id': id}),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }
}

class _FakeBlockchainProvider implements BlockchainProvider {
  @override
  Future<WalletChainSnapshot> loadSnapshot({
    required EvmNetwork network,
    required String address,
  }) async {
    return WalletChainSnapshot(
      network: network,
      address: address,
      nativeBalanceWei: BigInt.zero,
      nativeBalanceFormatted: '0',
      baseFeeGwei: 1,
      providerLabel: 'fake-rpc.local',
      fetchedAtUtc: DateTime.utc(2026, 11, 25),
      tokenBalances: const <TokenBalanceSnapshot>[],
      recentTransactions: const <RecentTransactionSnapshot>[],
    );
  }
}

Future<void> _tapShown(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    PhoneSecureVault.debugIterationsOverride = 2;
    debugUseNativeTabBar = true;
  });
  tearDown(() {
    PhoneSecureVault.debugIterationsOverride = null;
    debugUseNativeTabBar = null;
  });

  testWidgets(
    'iOS 26+: the tabs are the system tab bar, and its taps switch tabs',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final uiKit = _FakeUiKit(tester);

      await tester.pumpWidget(
        MobileWalletDemoApp(
          locale: const Locale('ru'),
          store: InMemorySecureKeyValueStore(),
          blockchainProvider: _FakeBlockchainProvider(),
        ),
      );
      await tester.pumpAndSettle();
      await _tapShown(tester, 'Создать кошелёк');
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '1234');
      await tester.enterText(fields.at(1), '1234');
      await _tapShown(tester, 'Создать кошелёк');
      await _tapShown(tester, 'Я сохранил seed-фразу');
      await _tapShown(tester, 'Пока без биометрии');

      expect(uiKit.viewId, isNotNull);
      final tabs = (uiKit.states.last['tabs']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      expect(tabs.map((tab) => tab['id']), <String>[
        'wallet',
        'activity',
        'connections',
        'settings',
      ]);
      expect(tabs.map((tab) => tab['title']), <String>[
        'Кошелёк',
        'Активность',
        'Связи',
        'Настройки',
      ]);
      expect(
        tabs.map((tab) => (tab['icon']! as Map<Object?, Object?>)['symbol']),
        <String>['wallet.pass', 'clock.arrow.circlepath', 'link', 'gearshape'],
      );
      expect(uiKit.states.last['selectedId'], 'wallet');
      // The shell draws no bar of its own beside the system one.
      expect(find.text('Связи'), findsNothing);

      await uiKit.tap('settings');
      expect(find.text('Активный адрес'), findsOneWidget);
      expect(uiKit.states.last['selectedId'], 'settings');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
