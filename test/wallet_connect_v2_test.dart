import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/auth/wallet_operation_auth.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/sessions/remote_signing_session.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_v2.dart';

const network = EvmNetwork.ethereumMainnet;
const sender = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
const recipient = '0x1111111111111111111111111111111111111111';
const tokenContract = '0x1111111111111111111111111111111111110000';
const walletMaterial = WalletMaterial(
  address: sender,
  mnemonic: 'test test test test test test test test test test test junk',
  privateKeyHex:
      'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
);

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
      throwsA(isA<RemoteSigningSessionException>()),
    );
  });

  test('rejects pairing with a non-wc URI', () async {
    final connector = DemoWalletConnectV2Connector(
      signer: _LocalSessionSigner(),
    );
    addTearDown(connector.dispose);

    await expectLater(
      connector.pair(wcUri: 'https://not-walletconnect'),
      throwsA(isA<RemoteSigningSessionException>()),
    );
  });

  test('pairs, records session info, and signs', () async {
    final connector = DemoWalletConnectV2Connector(
      signer: _LocalSessionSigner(),
    );
    addTearDown(connector.dispose);

    await connector.pair(
      wcUri: 'wc:topic123@2?relay-protocol=irn',
      accountAddress: sender,
    );
    expect(connector.state.status, RemoteSigningSessionStatus.connected);
    expect(connector.sessionInfo, isNotNull);
    expect(connector.sessionInfo!.topic, 'topic123');
    expect(connector.sessionInfo!.peerName, isNotEmpty);

    final raw = await connector.requestSignedTransaction(
      preparedTransfer: buildPrepared(),
      nonce: 1,
      fromAddress: sender,
    );
    expect(raw, isNotEmpty);
    expect(connector.lastRequest, isNotNull);
    expect(connector.lastRequest!.method, 'eth_signTransaction');
    expect(connector.state.status, RemoteSigningSessionStatus.connected);

    await connector.disconnect();
    expect(connector.sessionInfo, isNull);
    expect(connector.state.status, RemoteSigningSessionStatus.disconnected);
  });

  test('composes via authorizeRemoteSigning', () async {
    final connector = DemoWalletConnectV2Connector(
      signer: _LocalSessionSigner(),
    );
    addTearDown(connector.dispose);
    await connector.pair(wcUri: 'wc:t@2', accountAddress: sender);

    final operation = const WalletOperationAuthorizer().authorizeRemoteSigning(
      backendId: 'walletconnect',
      address: sender,
      transport: connector,
    );

    final signed = await operation.signer.signPreparedTransfer(
      transactionService: const LocalTransactionService(),
      preparedTransfer: buildPrepared(),
      nonce: 1,
    );
    expect(signed.rawTransactionHex, startsWith('0x'));
    expect(signed.signingNote, contains('walletconnect'));
  });
}

class _LocalSessionSigner implements RemoteSessionSigner {
  @override
  Future<Uint8List> sign({
    required PreparedTransfer preparedTransfer,
    required int nonce,
    required String fromAddress,
  }) async {
    final signed = const LocalTransactionService().signPreparedTransfer(
      preparedTransfer: preparedTransfer,
      walletMaterial: walletMaterial,
      nonce: nonce,
    );
    return signed.rawTransactionBytes;
  }
}
