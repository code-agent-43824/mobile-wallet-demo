import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';
import 'package:mobile_wallet_demo/src/walletconnect/reown_wallet_connect_service.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_inbound.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_service.dart';
import 'package:reown_walletkit/reown_walletkit.dart';

const String _topic = 'session-topic';
const String _address = '0x1111111111111111111111111111111111111111';

/// The wallet's Reown kit as a dApp on `@walletconnect/sign-client` drives it:
/// a session update is acknowledged, a session event never is, so Reown's
/// future for it never completes.
class _SignClientDappKit implements IReownWalletKit {
  _SignClientDappKit(this.session);

  SessionData session;
  final List<Map<String, Namespace>> updates = <Map<String, Namespace>>[];
  final List<({String chainId, SessionEventParams event})> events =
      <({String chainId, SessionEventParams event})>[];
  final List<JsonRpcResponse> responses = <JsonRpcResponse>[];

  @override
  Map<String, SessionData> getActiveSessions() => <String, SessionData>{
    session.topic: session,
  };

  @override
  Future<void> updateSession({
    required String topic,
    required Map<String, Namespace> namespaces,
  }) async {
    updates.add(namespaces);
    session = session.copyWith(namespaces: namespaces);
  }

  @override
  Future<void> emitSessionEvent({
    required String topic,
    required String chainId,
    required SessionEventParams event,
  }) {
    events.add((chainId: chainId, event: event));
    return Completer<void>().future;
  }

  @override
  Future<void> respondSessionRequest({
    required String topic,
    required JsonRpcResponse response,
  }) async {
    responses.add(response);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Unused implements TransactionBroadcaster, NonceProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

SessionData _sepoliaSession() {
  const metadata = PairingMetadata(
    name: 'dApp',
    description: '',
    url: 'https://dapp.example',
    icons: <String>[],
  );
  return SessionData(
    topic: _topic,
    pairingTopic: 'pairing-topic',
    relay: Relay('irn'),
    expiry: 4102444800,
    acknowledged: true,
    controller: 'wallet-key',
    namespaces: <String, Namespace>{
      'eip155': const Namespace(
        chains: <String>['eip155:11155111'],
        accounts: <String>['eip155:11155111:$_address'],
        methods: <String>['wallet_switchEthereumChain', 'personal_sign'],
        events: <String>['chainChanged', 'accountsChanged'],
      ),
    },
    self: const ConnectionMetadata(publicKey: 'wallet-key', metadata: metadata),
    peer: const ConnectionMetadata(publicKey: 'dapp-key', metadata: metadata),
  );
}

void main() {
  test('a chain switch is answered although the dApp never acknowledges '
      'chainChanged', () async {
    final kit = _SignClientDappKit(_sepoliaSession());
    final unused = _Unused();
    final coordinator = WalletConnectInboundCoordinator(
      service: ReownWalletConnectService.withKit(kit),
      transactionService: const LocalTransactionService(),
      broadcaster: unused,
      nonceProvider: unused,
    );
    const request = WalletConnectRequest(
      id: 42,
      topic: _topic,
      chainId: 'eip155:11155111',
      method: 'wallet_switchEthereumChain',
      params: <Object?>[
        <String, Object?>{'chainId': '0x1'},
      ],
    );

    // Awaiting the unacknowledged event used to hang here, so the dApp never
    // got its answer and the wallet's request queue stopped.
    await coordinator
        .handleRequest(request: request)
        .timeout(const Duration(seconds: 5));

    final namespace = kit.updates.single['eip155']!;
    expect(namespace.chains, <String>['eip155:11155111', 'eip155:1']);
    expect(namespace.accounts, contains('eip155:1:$_address'));
    expect(kit.events.single.chainId, 'eip155:1');
    expect(kit.events.single.event.name, 'chainChanged');
    expect(kit.events.single.event.data, 1);
    final response = kit.responses.single;
    expect(response.id, 42);
    expect(response.result, isTrue);
    expect(response.error, isNull);
  });
}
