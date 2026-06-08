import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_service.dart';

void main() {
  group('FakeWalletConnectService', () {
    test('pair emits a proposal, approve creates an active session', () async {
      final wc = FakeWalletConnectService();
      addTearDown(wc.dispose);

      final proposalFuture = wc.sessionProposals.first;
      await wc.pair(uri: 'wc:topic@2?relay-protocol=irn');
      final proposal = await proposalFuture;

      expect(proposal.peer.name, isNotEmpty);
      expect(proposal.requiredChains, contains('eip155:1'));
      expect(proposal.requiredMethods, contains('eth_sendTransaction'));

      final sessionsFuture = wc.sessionsChanges.first;
      final session = await wc.approveSession(
        proposal: proposal,
        accounts: const <String>['eip155:1:0xabc'],
      );

      expect(session.topic, 'topic-${proposal.id}');
      expect(session.accounts, contains('eip155:1:0xabc'));
      expect(wc.activeSessions, hasLength(1));
      expect((await sessionsFuture).single.topic, session.topic);
    });

    test('rejects a non-wc pairing URI', () async {
      final wc = FakeWalletConnectService();
      addTearDown(wc.dispose);

      await expectLater(
        wc.pair(uri: 'https://not-walletconnect'),
        throwsA(isA<WalletConnectServiceException>()),
      );
      expect(wc.activeSessions, isEmpty);
    });

    test('answers an incoming request with result or error', () async {
      final wc = FakeWalletConnectService();
      addTearDown(wc.dispose);

      final requestFuture = wc.requests.first;
      final emitted = wc.simulateRequest(
        topic: 'topic-1',
        method: 'eth_sendTransaction',
        params: const <Object?>[],
      );
      final request = await requestFuture;

      expect(request.id, emitted.id);
      expect(request.method, 'eth_sendTransaction');
      expect(request.chainId, 'eip155:1');

      await wc.respondResult(request: request, result: '0xdeadbeef');
      expect(wc.respondedResults.single.id, request.id);
      expect(wc.respondedResults.single.result, '0xdeadbeef');

      await wc.respondError(request: request, message: 'отклонено');
      expect(wc.respondedErrors.single.message, 'отклонено');
    });

    test('disconnect removes the matching session', () async {
      final wc = FakeWalletConnectService();
      addTearDown(wc.dispose);

      final proposal = wc.simulateProposal(
        peer: const WalletConnectPeer(name: 'Demo dApp'),
      );
      final session = await wc.approveSession(
        proposal: proposal,
        accounts: const <String>[],
      );
      expect(wc.activeSessions, hasLength(1));

      await wc.disconnect(topic: session.topic);
      expect(wc.activeSessions, isEmpty);
    });
  });

  group('UnavailableWalletConnectService', () {
    test('reports unavailable and refuses pairing', () async {
      const wc = UnavailableWalletConnectService();

      expect(wc.isAvailable, isFalse);
      expect(wc.activeSessions, isEmpty);
      await wc.init();

      await expectLater(
        wc.pair(uri: 'wc:topic@2'),
        throwsA(isA<WalletConnectServiceException>()),
      );
    });
  });
}
