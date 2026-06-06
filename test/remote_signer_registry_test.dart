import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/airgap/airgap_signing.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/sessions/remote_signer_registry.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_v2.dart';

const network = EvmNetwork.ethereumMainnet;
const sender = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
const recipient = '0x1111111111111111111111111111111111111111';
const walletMaterial = WalletMaterial(
  address: sender,
  mnemonic: 'test test test test test test test test test test test junk',
  privateKeyHex:
      'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
);

WalletChainSnapshot buildSnapshot() {
  return WalletChainSnapshot(
    network: network,
    address: sender,
    nativeBalanceWei: BigInt.parse('1230000000000000000'),
    nativeBalanceFormatted: '1.23',
    baseFeeGwei: 12.0,
    providerLabel: 'fake-rpc.local',
    fetchedAtUtc: DateTime.utc(2026, 6, 1),
    tokenBalances: const <TokenBalanceSnapshot>[],
    recentTransactions: const <RecentTransactionSnapshot>[],
  );
}

PreparedTransfer buildPrepared() {
  final snapshot = buildSnapshot();
  final asset = const LocalTransactionService()
      .availableAssets(
        snapshot: snapshot,
        networkConfig: evmNetworkConfigs[network]!,
      )
      .first;
  return const LocalTransactionService().prepareTransfer(
    snapshot: snapshot,
    fromAddress: sender,
    toAddress: recipient,
    amountText: '0.1',
    asset: asset,
  );
}

void main() {
  const catalog = RemoteSignerCatalog();

  test('lists WalletConnect and AirGap signers', () {
    final kinds = catalog.descriptors.map((d) => d.kind).toList();
    expect(
      kinds,
      containsAll(const <RemoteSignerKind>[
        RemoteSignerKind.walletConnectV2,
        RemoteSignerKind.airGap,
      ]),
    );
  });

  test('creates the expected connector type per kind', () {
    final wc = catalog.createDemoConnector(
      kind: RemoteSignerKind.walletConnectV2,
      walletMaterial: walletMaterial,
      transactionService: const LocalTransactionService(),
    );
    addTearDown(wc.dispose);
    final ag = catalog.createDemoConnector(
      kind: RemoteSignerKind.airGap,
      walletMaterial: walletMaterial,
      transactionService: const LocalTransactionService(),
    );
    addTearDown(ag.dispose);

    expect(wc, isA<WalletConnectV2Connector>());
    expect(ag, isA<AirGapOfflineConnector>());
  });

  test('WalletConnect demo connector signs the prepared tx', () async {
    final connector = catalog.createDemoConnector(
      kind: RemoteSignerKind.walletConnectV2,
      walletMaterial: walletMaterial,
      transactionService: const LocalTransactionService(),
    );
    addTearDown(connector.dispose);
    await connector.connect(accountAddress: sender);

    final raw = await connector.requestSignedTransaction(
      preparedTransfer: buildPrepared(),
      nonce: 7,
      fromAddress: sender,
    );
    expect(raw, isNotEmpty);
    expect(raw.first, 0x02);
  });

  test('AirGap demo connector rebuilds and signs the request', () async {
    final connector = catalog.createDemoConnector(
      kind: RemoteSignerKind.airGap,
      walletMaterial: walletMaterial,
      transactionService: const LocalTransactionService(),
    );
    addTearDown(connector.dispose);
    await connector.connect(accountAddress: sender);

    final raw = await connector.requestSignedTransaction(
      preparedTransfer: buildPrepared(),
      nonce: 7,
      fromAddress: sender,
    );
    expect(raw, isNotEmpty);
    expect(raw.first, 0x02);
  });
}
