import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/airgap/airgap_signing.dart';
import 'package:mobile_wallet_demo/src/auth/wallet_operation_auth.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/sessions/remote_signing_session.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';

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
  test('builds a request from a native prepared transfer', () {
    final request = const AirGapPayloadCodec().buildRequest(
      preparedTransfer: buildPrepared(),
      nonce: 5,
      fromAddress: sender,
    );

    expect(request.chainId, 'eip155:1');
    expect(request.fromAddress, sender);
    expect(request.toAddress, recipient);
    expect(request.nonce, 5);
    expect(request.dataHex, '0x');
    expect(request.requestId, 'eip155:1:$sender:5');
  });

  test('round-trips the export request through the codec', () {
    const codec = AirGapPayloadCodec();
    final request = codec.buildRequest(
      preparedTransfer: buildPrepared(erc20: true),
      nonce: 2,
      fromAddress: sender,
    );

    final payload = codec.encodeRequest(request);
    expect(payload, startsWith('airgap-tx:'));

    final decoded = codec.decodeRequest(payload);
    expect(decoded.requestId, request.requestId);
    expect(decoded.toAddress, tokenContract);
    expect(decoded.dataHex, startsWith('0xa9059cbb'));
  });

  test('round-trips the signed response through the codec', () {
    const codec = AirGapPayloadCodec();
    final payload = codec.encodeResponse(
      const AirGapSignedResponse(
        requestId: 'r1',
        rawSignedTransactionHex: '0x02ab',
      ),
    );
    expect(payload, startsWith('airgap-sig:'));

    final decoded = codec.decodeResponse(payload);
    expect(decoded.requestId, 'r1');

    final bytes = codec.toSignedBytes(decoded, expectedRequestId: 'r1');
    expect(bytes, <int>[2, 171]);
  });

  test('rejects a response whose request id does not match', () {
    const codec = AirGapPayloadCodec();
    const response = AirGapSignedResponse(
      requestId: 'r1',
      rawSignedTransactionHex: '0x02',
    );

    expect(
      () => codec.toSignedBytes(response, expectedRequestId: 'r2'),
      throwsA(isA<AirGapPayloadException>()),
    );
  });

  test('rejects an empty signature and a wrong-scheme payload', () {
    const codec = AirGapPayloadCodec();
    const empty = AirGapSignedResponse(
      requestId: 'r1',
      rawSignedTransactionHex: '0x',
    );

    expect(
      () => codec.toSignedBytes(empty, expectedRequestId: 'r1'),
      throwsA(isA<AirGapPayloadException>()),
    );
    expect(
      () => codec.decodeResponse('airgap-tx:zzz'),
      throwsA(isA<AirGapPayloadException>()),
    );
  });

  test('connects and signs through the export/import round-trip', () async {
    final connector = DemoAirGapOfflineConnector(device: _StubAirGapDevice());
    addTearDown(connector.dispose);

    await connector.connect(accountAddress: sender);
    expect(connector.state.status, RemoteSigningSessionStatus.connected);

    final raw = await connector.requestSignedTransaction(
      preparedTransfer: buildPrepared(),
      nonce: 1,
      fromAddress: sender,
    );
    expect(raw, <int>[2, 171, 205, 239]);
    expect(connector.lastExportPayload, startsWith('airgap-tx:'));
    expect(connector.state.status, RemoteSigningSessionStatus.connected);
  });

  test('moves to error on a mismatched device response', () async {
    final connector = DemoAirGapOfflineConnector(
      device: _StubAirGapDevice(requestIdOverride: 'wrong'),
    );
    addTearDown(connector.dispose);
    await connector.connect(accountAddress: sender);

    await expectLater(
      connector.requestSignedTransaction(
        preparedTransfer: buildPrepared(),
        nonce: 1,
        fromAddress: sender,
      ),
      throwsA(isA<AirGapPayloadException>()),
    );
    expect(connector.state.status, RemoteSigningSessionStatus.error);
  });

  test('composes via authorizeRemoteSigning', () async {
    final connector = DemoAirGapOfflineConnector(device: _StubAirGapDevice());
    addTearDown(connector.dispose);
    await connector.connect(accountAddress: sender);

    final operation = const WalletOperationAuthorizer().authorizeRemoteSigning(
      backendId: 'airgap',
      address: sender,
      transport: connector,
    );

    final signed = await operation.signer.signPreparedTransfer(
      transactionService: const LocalTransactionService(),
      preparedTransfer: buildPrepared(),
      nonce: 1,
    );
    expect(signed.rawTransactionHex, '0x02abcdef');
    expect(signed.signingNote, contains('airgap'));
  });
}

class _StubAirGapDevice implements AirGapResponseProvider {
  _StubAirGapDevice({this.requestIdOverride});

  final String? requestIdOverride;

  @override
  Future<String> provideSignature({
    required AirGapSigningRequest request,
    required String exportPayload,
  }) async {
    final response = AirGapSignedResponse(
      requestId: requestIdOverride ?? request.requestId,
      rawSignedTransactionHex: '0x02abcdef',
    );
    return const AirGapPayloadCodec().encodeResponse(response);
  }
}
