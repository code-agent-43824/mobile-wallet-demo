import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_models.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/chain_data_controller.dart';

/// A provider whose responses are completed by the test, so a reply can be made
/// to arrive *after* the network has already been switched.
class _ControllableProvider implements BlockchainProvider {
  final List<({EvmNetwork network, Completer<WalletChainSnapshot> completer})>
  pending = [];

  @override
  Future<WalletChainSnapshot> loadSnapshot({
    required EvmNetwork network,
    required String address,
  }) {
    final completer = Completer<WalletChainSnapshot>();
    pending.add((network: network, completer: completer));
    return completer.future;
  }

  /// Completes the oldest still-pending request for [network].
  void complete(
    EvmNetwork network, {
    String balance = '1.0',
    bool fromCache = false,
  }) {
    final entry = pending.firstWhere(
      (e) => e.network == network && !e.completer.isCompleted,
    );
    entry.completer.complete(
      WalletChainSnapshot(
        network: network,
        address: '0xabc',
        nativeBalanceWei: BigInt.one,
        nativeBalanceFormatted: balance,
        baseFeeGwei: 1,
        providerLabel: 'fake',
        fetchedAtUtc: DateTime.utc(2026, 1, 1),
        tokenBalances: const <TokenBalanceSnapshot>[],
        recentTransactions: const <RecentTransactionSnapshot>[],
        loadedFromCache: fromCache,
      ),
    );
  }

  void fail(EvmNetwork network, String message) {
    pending
        .firstWhere((e) => e.network == network && !e.completer.isCompleted)
        .completer
        .completeError(BlockchainFailure(message));
  }
}

void main() {
  late _ControllableProvider provider;
  late ChainDataController controller;

  setUp(() {
    provider = _ControllableProvider();
    controller = ChainDataController(blockchainProvider: provider);
  });

  tearDown(() => controller.dispose());

  test('loads a snapshot for the address it is pointed at', () async {
    final pending = controller.setAddress('0xabc');
    expect(controller.isInitialLoad, isTrue);

    provider.complete(EvmNetwork.ethereumMainnet, balance: '2.5');
    await pending;

    expect(controller.snapshot?.nativeBalanceFormatted, '2.5');
    expect(controller.isLoading, isFalse);
    expect(controller.isInitialLoad, isFalse);
    expect(controller.errorMessage, isNull);
  });

  test('surfaces a blockchain failure as an error message', () async {
    final pending = controller.setAddress('0xabc');
    provider.fail(EvmNetwork.ethereumMainnet, 'rpc down');
    await pending;

    expect(controller.errorMessage, 'rpc down');
    expect(controller.snapshot, isNull);
    expect(controller.isLoading, isFalse);
  });

  test(
    'flags a cache-served snapshot so the UI can show the offline banner',
    () async {
      final pending = controller.setAddress('0xabc');
      provider.complete(EvmNetwork.ethereumMainnet, fromCache: true);
      await pending;

      expect(controller.isFromCache, isTrue);
    },
  );

  test('switching networks drops the previous snapshot immediately', () async {
    final first = controller.setAddress('0xabc');
    provider.complete(EvmNetwork.ethereumMainnet, balance: '9.9');
    await first;
    expect(controller.snapshot, isNotNull);

    final second = controller.selectNetwork(EvmNetwork.ethereumSepolia);
    // No stale mainnet balance may be shown under the Sepolia heading.
    expect(controller.snapshot, isNull);
    expect(controller.selectedNetwork, EvmNetwork.ethereumSepolia);

    provider.complete(EvmNetwork.ethereumSepolia, balance: '0.1');
    await second;
    expect(controller.snapshot?.nativeBalanceFormatted, '0.1');
  });

  test(
    'a late reply for the previous network never overwrites the current one',
    () async {
      // Regression guard for the v1.34 stale-balance bug: the mainnet request is
      // still in flight when the user switches to Sepolia, and lands afterwards.
      final first = controller.setAddress('0xabc');
      final second = controller.selectNetwork(EvmNetwork.ethereumSepolia);

      provider.complete(EvmNetwork.ethereumSepolia, balance: '0.1');
      await second;
      expect(controller.snapshot?.nativeBalanceFormatted, '0.1');

      // The obsolete mainnet reply arrives only now.
      provider.complete(EvmNetwork.ethereumMainnet, balance: '999');
      await first;

      expect(controller.selectedNetwork, EvmNetwork.ethereumSepolia);
      expect(
        controller.snapshot?.nativeBalanceFormatted,
        '0.1',
        reason: 'the superseded network reply must be discarded',
      );
      expect(controller.isLoading, isFalse);
    },
  );

  test(
    'pointing at a new address discards the previous wallet snapshot',
    () async {
      final first = controller.setAddress('0xabc');
      provider.complete(EvmNetwork.ethereumMainnet, balance: '5');
      await first;

      final second = controller.setAddress('0xdef');
      // One wallet's balance must never be shown under another's address.
      expect(controller.snapshot, isNull);

      provider.complete(EvmNetwork.ethereumMainnet, balance: '7');
      await second;
      expect(controller.snapshot?.nativeBalanceFormatted, '7');
    },
  );

  test('notifies listeners as loading state changes', () async {
    var notifications = 0;
    controller.addListener(() => notifications++);

    final pending = controller.setAddress('0xabc');
    provider.complete(EvmNetwork.ethereumMainnet);
    await pending;

    expect(notifications, greaterThanOrEqualTo(2));
  });
}
