import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_v2.dart';

const network = EvmNetwork.ethereumMainnet;
const sender = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
const recipient = '0x1111111111111111111111111111111111111111';
const tokenContract = '0x1111111111111111111111111111111111110000';

WalletChainSnapshot buildSnapshot({bool withToken = false}) {
  return WalletChainSnapshot(
    network: network,
    address: sender,
    nativeBalanceWei: BigInt.parse('1230000000000000000'),
    nativeBalanceFormatted: '1.23',
    baseFeeGwei: 12.0,
    providerLabel: 'fake-rpc.local',
    fetchedAtUtc: DateTime.utc(2026, 6, 1),
    tokenBalances: withToken
        ? <TokenBalanceSnapshot>[
            TokenBalanceSnapshot(
              symbol: 'USDC',
              name: 'USD Coin',
              balanceFormatted: '42.5',
              rawBalance: BigInt.from(42500000),
              decimals: 6,
              contractAddress: tokenContract,
            ),
          ]
        : const <TokenBalanceSnapshot>[],
    recentTransactions: const <RecentTransactionSnapshot>[],
  );
}

PreparedTransfer buildPrepared({bool erc20 = false}) {
  final snapshot = buildSnapshot(withToken: erc20);
  final assets = const LocalTransactionService().availableAssets(
    snapshot: snapshot,
    networkConfig: evmNetworkConfigs[network]!,
  );
  return const LocalTransactionService().prepareTransfer(
    snapshot: snapshot,
    fromAddress: sender,
    toAddress: recipient,
    amountText: erc20 ? '2.5' : '0.1',
    asset: erc20 ? assets.last : assets.first,
  );
}

void main() {
  test('encodes a native transfer as an eth_signTransaction request', () {
    final request = const WalletConnectV2RequestCodec().encodeSignTransaction(
      preparedTransfer: buildPrepared(),
      nonce: 7,
      fromAddress: sender,
    );

    expect(request.method, 'eth_signTransaction');
    expect(request.chainId, 'eip155:1');
    final tx = request.params.first as Map<String, Object?>;
    expect(tx['from'], sender);
    expect(tx['to'], recipient);
    expect(tx['nonce'], '0x7');
    expect(tx['data'], '0x');
  });

  test('encodes an ERC-20 transfer with calldata', () {
    final request = const WalletConnectV2RequestCodec().encodeSignTransaction(
      preparedTransfer: buildPrepared(erc20: true),
      nonce: 3,
      fromAddress: sender,
    );

    final tx = request.params.first as Map<String, Object?>;
    expect(tx['to'], tokenContract);
    expect(tx['value'], '0x0');
    expect(tx['data'], startsWith('0xa9059cbb'));
  });

  test('decodes a signed-tx hex response into bytes', () {
    const codec = WalletConnectV2RequestCodec();
    expect(codec.decodeSignedTransaction('0x0203'), <int>[2, 3]);
    expect(codec.decodeSignedTransaction('0203'), <int>[2, 3]);
    expect(
      () => codec.decodeSignedTransaction('0x'),
      throwsA(isA<WalletConnectCodecException>()),
    );
  });
}
