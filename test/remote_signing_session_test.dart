import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/auth/wallet_operation_auth.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/sessions/remote_signing_session.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';

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
  test('walks connect -> sign -> connected -> disconnect', () async {
    final signer = _RecordingSessionSigner();
    final controller = DemoRemoteSigningSessionController(
      label: 'demo',
      peerLabel: 'Demo Wallet',
      signer: signer,
    );
    signer.controller = controller;
    addTearDown(controller.dispose);

    expect(controller.state.status, RemoteSigningSessionStatus.idle);

    await controller.connect(accountAddress: sender);
    expect(controller.state.status, RemoteSigningSessionStatus.connected);
    expect(controller.state.accountAddress, sender);
    expect(controller.state.sessionId, isNotNull);
    expect(controller.state.peerLabel, 'Demo Wallet');

    final raw = await controller.requestSignedTransaction(
      preparedTransfer: buildPrepared(),
      nonce: 1,
      fromAddress: sender,
    );
    expect(raw, isNotEmpty);
    expect(
      signer.statusWhenCalled,
      RemoteSigningSessionStatus.awaitingSignature,
    );
    expect(controller.state.status, RemoteSigningSessionStatus.connected);
    expect(controller.state.pendingRequestSummary, isNull);

    await controller.disconnect();
    expect(controller.state.status, RemoteSigningSessionStatus.disconnected);
  });

  test('rejects signing before the session is connected', () async {
    final controller = DemoRemoteSigningSessionController(
      label: 'demo',
      signer: _RecordingSessionSigner(),
    );
    addTearDown(controller.dispose);

    await expectLater(
      controller.requestSignedTransaction(
        preparedTransfer: buildPrepared(),
        nonce: 1,
        fromAddress: sender,
      ),
      throwsA(isA<RemoteSigningSessionException>()),
    );
  });

  test('moves to error when the remote signer fails', () async {
    final controller = DemoRemoteSigningSessionController(
      label: 'demo',
      signer: _ThrowingSessionSigner(),
    );
    addTearDown(controller.dispose);
    await controller.connect();

    await expectLater(
      controller.requestSignedTransaction(
        preparedTransfer: buildPrepared(),
        nonce: 1,
        fromAddress: sender,
      ),
      throwsA(isA<StateError>()),
    );
    expect(controller.state.status, RemoteSigningSessionStatus.error);
    expect(controller.state.lastError, contains('declined'));
  });

  test('signs through authorizeRemoteSigning as a transport', () async {
    final controller = DemoRemoteSigningSessionController(
      label: 'walletconnect',
      signer: _LocalSessionSigner(),
    );
    addTearDown(controller.dispose);
    await controller.connect(accountAddress: sender);

    const authorizer = WalletOperationAuthorizer();
    final operation = authorizer.authorizeRemoteSigning(
      backendId: 'walletconnect',
      address: sender,
      transport: controller,
    );
    expect(operation.signer, isA<RemoteWalletTransactionSigner>());

    final signed = await operation.signer.signPreparedTransfer(
      transactionService: const LocalTransactionService(),
      preparedTransfer: buildPrepared(),
      nonce: 1,
    );
    expect(signed.rawTransactionHex, startsWith('0x'));
    expect(signed.signingNote, contains('walletconnect'));
    expect(controller.state.status, RemoteSigningSessionStatus.connected);
  });
}

class _RecordingSessionSigner implements RemoteSessionSigner {
  DemoRemoteSigningSessionController? controller;
  RemoteSigningSessionStatus? statusWhenCalled;

  @override
  Future<Uint8List> sign({
    required PreparedTransfer preparedTransfer,
    required int nonce,
    required String fromAddress,
  }) async {
    statusWhenCalled = controller?.state.status;
    return Uint8List.fromList(const [9, 9, 9]);
  }
}

class _ThrowingSessionSigner implements RemoteSessionSigner {
  @override
  Future<Uint8List> sign({
    required PreparedTransfer preparedTransfer,
    required int nonce,
    required String fromAddress,
  }) async {
    throw StateError('remote signer declined');
  }
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
