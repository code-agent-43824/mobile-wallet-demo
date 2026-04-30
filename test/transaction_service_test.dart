import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';

void main() {
  const service = ReadOnlyTransactionService();
  const network = EvmNetwork.ethereumMainnet;

  WalletChainSnapshot buildSnapshot() {
    return WalletChainSnapshot(
      network: network,
      address: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      nativeBalanceWei: BigInt.parse('1230000000000000000'),
      nativeBalanceFormatted: '1.23',
      baseFeeGwei: 12.0,
      providerLabel: 'fake-rpc.local',
      fetchedAtUtc: DateTime.utc(2026, 4, 25, 15, 32),
      tokenBalances: <TokenBalanceSnapshot>[
        TokenBalanceSnapshot(
          symbol: 'USDC',
          name: 'USD Coin',
          balanceFormatted: '42.5',
          rawBalance: BigInt.from(42500000),
          decimals: 6,
          contractAddress: '0x1111111111111111111111111111111111110000',
        ),
      ],
      recentTransactions: const <RecentTransactionSnapshot>[],
    );
  }

  const walletMaterial = WalletMaterial(
    address: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
    mnemonic: 'test test test test test test test test test test test junk',
    privateKeyHex:
        'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
  );

  test('builds native transfer preview with gas estimate', () {
    final snapshot = buildSnapshot();
    final asset = service
        .availableAssets(
          snapshot: snapshot,
          networkConfig: evmNetworkConfigs[network]!,
        )
        .first;

    final preview = service.preparePreview(
      snapshot: snapshot,
      fromAddress: snapshot.address,
      toAddress: '0x1111111111111111111111111111111111111111',
      amountText: '0.1',
      asset: asset,
    );

    expect(preview.gasLimit, 21000);
    expect(preview.amountFormatted, '0.1 ETH');
    expect(preview.estimatedNetworkFeeNativeFormatted, contains('ETH'));
  });

  test('builds token transfer preview with separate native fee', () {
    final snapshot = buildSnapshot();
    final asset = service
        .availableAssets(
          snapshot: snapshot,
          networkConfig: evmNetworkConfigs[network]!,
        )
        .last;

    final preview = service.preparePreview(
      snapshot: snapshot,
      fromAddress: snapshot.address,
      toAddress: '0x1111111111111111111111111111111111111111',
      amountText: '2.5',
      asset: asset,
    );

    expect(preview.gasLimit, 65000);
    expect(preview.amountFormatted, '2.5 USDC');
    expect(preview.totalDebitFormatted, contains('ETH fee'));
  });

  test('rejects invalid recipient address', () {
    final snapshot = buildSnapshot();
    final asset = service
        .availableAssets(
          snapshot: snapshot,
          networkConfig: evmNetworkConfigs[network]!,
        )
        .first;

    expect(
      () => service.preparePreview(
        snapshot: snapshot,
        fromAddress: snapshot.address,
        toAddress: '0xabc',
        amountText: '0.1',
        asset: asset,
      ),
      throwsA(isA<TransactionFailure>()),
    );
  });

  test(
    'signs native transfer as typed transaction after one prepared flow',
    () {
      final snapshot = buildSnapshot();
      final asset = service
          .availableAssets(
            snapshot: snapshot,
            networkConfig: evmNetworkConfigs[network]!,
          )
          .first;

      final prepared = service.prepareTransfer(
        snapshot: snapshot,
        fromAddress: snapshot.address,
        toAddress: '0x2222222222222222222222222222222222222222',
        amountText: '0.1',
        asset: asset,
      );
      final signed = service.signPreparedTransfer(
        preparedTransfer: prepared,
        walletMaterial: walletMaterial,
        nonce: 7,
      );

      expect(signed.rawTransactionHex, startsWith('0x02'));
      expect(signed.transactionHashHex, hasLength(66));
      expect(signed.signingNote, contains('PIN нужен только один раз'));
    },
  );

  test('signs erc20 transfer with transfer selector in calldata', () {
    final snapshot = buildSnapshot();
    final asset = service
        .availableAssets(
          snapshot: snapshot,
          networkConfig: evmNetworkConfigs[network]!,
        )
        .last;

    final prepared = service.prepareTransfer(
      snapshot: snapshot,
      fromAddress: snapshot.address,
      toAddress: '0x3333333333333333333333333333333333333333',
      amountText: '2.5',
      asset: asset,
    );
    final signed = service.signPreparedTransfer(
      preparedTransfer: prepared,
      walletMaterial: walletMaterial,
      nonce: 8,
    );

    expect(signed.rawTransactionHex, contains('a9059cbb'));
    expect(signed.rawTransactionHex, startsWith('0x02'));
  });

  test('rejects signing when wallet material does not match sender', () {
    final snapshot = buildSnapshot();
    final asset = service
        .availableAssets(
          snapshot: snapshot,
          networkConfig: evmNetworkConfigs[network]!,
        )
        .first;

    final prepared = service.prepareTransfer(
      snapshot: snapshot,
      fromAddress: snapshot.address,
      toAddress: '0x2222222222222222222222222222222222222222',
      amountText: '0.1',
      asset: asset,
    );

    expect(
      () => service.signPreparedTransfer(
        preparedTransfer: prepared,
        walletMaterial: const WalletMaterial(
          address: '0x0000000000000000000000000000000000000001',
          mnemonic: 'x',
          privateKeyHex:
              'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        ),
        nonce: 0,
      ),
      throwsA(isA<TransactionFailure>()),
    );
  });

  test('submits signed transaction through broadcaster abstraction', () async {
    final snapshot = buildSnapshot();
    final asset = service
        .availableAssets(
          snapshot: snapshot,
          networkConfig: evmNetworkConfigs[network]!,
        )
        .first;

    final prepared = service.prepareTransfer(
      snapshot: snapshot,
      fromAddress: snapshot.address,
      toAddress: '0x2222222222222222222222222222222222222222',
      amountText: '0.1',
      asset: asset,
    );
    final signed = service.signPreparedTransfer(
      preparedTransfer: prepared,
      walletMaterial: walletMaterial,
      nonce: 9,
    );

    final submitted = await service.submitSignedTransfer(
      signedTransfer: signed,
      broadcaster: PublicRpcTransactionBroadcaster(
        rpcTransport: _FakeJsonRpcTransport(
          responses: <String, Map<String, dynamic>>{
            'ethereum-rpc.publicnode.com': <String, dynamic>{
              'jsonrpc': '2.0',
              'id': 1,
              'result':
                  '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            },
          },
        ),
      ),
    );

    expect(submitted.providerLabel, 'ethereum-rpc.publicnode.com');
    expect(submitted.networkTransactionHash, startsWith('0xaaaa'));
  });
}

class _FakeJsonRpcTransport implements JsonRpcTransport {
  _FakeJsonRpcTransport({required this.responses});

  final Map<String, Map<String, dynamic>> responses;

  @override
  Future<Map<String, dynamic>> post({
    required Uri uri,
    required Map<String, dynamic> payload,
  }) async {
    final response = responses[uri.host];
    if (response == null) {
      throw const BlockchainFailure('missing fake response');
    }
    return response;
  }
}
