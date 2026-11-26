// Deleting the phone wallet (owner, 2026-11-26): what is erased, what is
// closed, and that the settings make it hard to do by accident.
// Flutter 3.50 deprecates the library in favour of package:material_ui;
// see docs/PLAN.md for the migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/app.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/blockchain/snapshot_cache.dart';
import 'package:mobile_wallet_demo/src/key_storage/phone_secure_vault.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_service.dart';
import 'package:mobile_wallet_demo/src/wallet_flow_screen.dart';

class _FakeBlockchainProvider implements BlockchainProvider {
  @override
  Future<WalletChainSnapshot> loadSnapshot({
    required EvmNetwork network,
    required String address,
  }) async => _snapshot(network, address);
}

WalletChainSnapshot _snapshot(EvmNetwork network, String address) =>
    WalletChainSnapshot(
      network: network,
      address: address,
      nativeBalanceWei: BigInt.one,
      nativeBalanceFormatted: '0.000000000000000001',
      baseFeeGwei: 1,
      providerLabel: 'fake-rpc.local',
      fetchedAtUtc: DateTime.utc(2026, 11, 26),
      tokenBalances: const <TokenBalanceSnapshot>[],
      recentTransactions: const <RecentTransactionSnapshot>[],
    );

void main() {
  setUp(() => PhoneSecureVault.debugIterationsOverride = 2);
  tearDown(() => PhoneSecureVault.debugIterationsOverride = null);

  test('erases the seed, its cached balances, its sessions and its account '
      'QR, and returns to the welcome screen', () async {
    final store = InMemorySecureKeyValueStore();
    final service = FakeWalletConnectService();
    final controller = WalletFlowController(
      store: store,
      biometricAuthGateway: const SimulatedBiometricAuthGateway(),
      walletConnectService: service,
    );
    await controller.loadInitialState();
    await controller.createWallet(pin: '1234');
    controller.finishSeedBackup();
    await controller.completeBiometricChoice(false);
    final address = controller.summary!.address;

    final cache = SnapshotCache(store);
    for (final network in EvmNetwork.values) {
      await cache.write(_snapshot(network, address));
    }
    await controller.pairWalletConnect(uri: 'wc:demo@2');
    await pumpEventQueue();
    await controller.approvePendingProposal();
    expect(controller.walletConnectSessions, hasLength(1));
    await controller.prepareAirGapAccountExport(pin: '1234');
    expect(controller.airGapAccountExportPayload, isNotNull);

    await controller.deletePhoneWallet();

    expect(controller.stage, WalletFlowStage.welcome);
    expect(controller.summary, isNull);
    expect(await store.read(PhoneSecureVault.storageKey), isNull);
    for (final network in EvmNetwork.values) {
      expect(
        await cache.read(network: network, address: address),
        isNull,
        reason: network.name,
      );
    }
    expect(controller.walletConnectSessions, isEmpty);
    expect(controller.airGapAccountExportPayload, isNull);

    // A fresh start finds no wallet, and a new one gets a new address.
    controller.dispose();
    final restarted = WalletFlowController(
      store: store,
      biometricAuthGateway: const SimulatedBiometricAuthGateway(),
    );
    await restarted.loadInitialState();
    expect(restarted.stage, WalletFlowStage.welcome);
    await restarted.createWallet(pin: '5678');
    restarted.finishSeedBackup();
    await restarted.completeBiometricChoice(false);
    expect(restarted.summary!.address, isNot(address));
    restarted.dispose();
    await service.dispose();
  });

  testWidgets('Settings: the danger zone asks, and a tick arms the button', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = InMemorySecureKeyValueStore();
    await tester.pumpWidget(
      MobileWalletDemoApp(
        locale: const Locale('ru'),
        store: store,
        blockchainProvider: _FakeBlockchainProvider(),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> tapShown(Finder finder) async {
      await tester.ensureVisible(finder.last);
      await tester.pumpAndSettle();
      await tester.tap(finder.last);
      await tester.pumpAndSettle();
    }

    await tapShown(find.text('Создать кошелёк'));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '1234');
    await tester.enterText(fields.at(1), '1234');
    await tapShown(find.text('Создать кошелёк'));
    await tapShown(find.text('Я сохранил seed-фразу'));
    await tapShown(find.text('Пока без биометрии'));
    await tapShown(find.text('Настройки'));

    expect(find.text('Опасная зона'), findsOneWidget);
    await tapShown(find.text('Удалить кошелёк с телефона'));
    expect(find.text('Удалить кошелёк?'), findsOneWidget);
    expect(find.textContaining('будут потеряны навсегда'), findsOneWidget);
    FilledButton deleteButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Удалить навсегда'),
    );
    expect(deleteButton().onPressed, isNull, reason: 'not before the tick');

    // Cancelling keeps everything.
    await tapShown(find.text('Отмена'));
    expect(await store.read(PhoneSecureVault.storageKey), isNotNull);
    expect(find.text('Опасная зона'), findsOneWidget);

    await tapShown(find.text('Удалить кошелёк с телефона'));
    await tapShown(
      find.text('Я сохранил seed-фразу или согласен потерять средства'),
    );
    expect(deleteButton().onPressed, isNotNull);
    await tapShown(find.text('Удалить навсегда'));

    expect(await store.read(PhoneSecureVault.storageKey), isNull);
    expect(find.text('Создать кошелёк'), findsOneWidget);
    expect(find.text('Опасная зона'), findsNothing);
  });
}
