import 'dart:async';

import '../errors/app_error.dart';

/// Metadata about the dApp peer on the other end of a WalletConnect session.
class WalletConnectPeer {
  const WalletConnectPeer({
    required this.name,
    this.url = '',
    this.description = '',
    this.iconUrl,
  });

  final String name;
  final String url;
  final String description;
  final String? iconUrl;
}

/// An incoming WalletConnect v2 session proposal the wallet can approve/reject.
class WalletConnectSessionProposal {
  const WalletConnectSessionProposal({
    required this.id,
    required this.pairingTopic,
    required this.peer,
    required this.requiredChains,
    required this.requiredMethods,
  });

  final int id;
  final String pairingTopic;
  final WalletConnectPeer peer;

  /// CAIP-2 chains the dApp asks for, e.g. `eip155:1`.
  final List<String> requiredChains;

  /// JSON-RPC methods the dApp wants, e.g. `eth_sendTransaction`.
  final List<String> requiredMethods;
}

/// An established WalletConnect v2 session (wallet-side view).
class WalletConnectSession {
  const WalletConnectSession({
    required this.topic,
    required this.peer,
    required this.chains,
    required this.accounts,
    required this.connectedAtUtc,
  });

  final String topic;
  final WalletConnectPeer peer;

  /// CAIP-2 chains, e.g. `eip155:1`.
  final List<String> chains;

  /// CAIP-10 accounts, e.g. `eip155:1:0x...`.
  final List<String> accounts;
  final DateTime connectedAtUtc;
}

/// An incoming signing request from a connected dApp.
class WalletConnectRequest {
  const WalletConnectRequest({
    required this.id,
    required this.topic,
    required this.chainId,
    required this.method,
    required this.params,
  });

  final int id;
  final String topic;

  /// CAIP-2 chain the request targets, e.g. `eip155:1`.
  final String chainId;

  /// JSON-RPC method, e.g. `eth_sendTransaction`.
  final String method;

  /// JSON-RPC params (method-specific).
  final List<Object?> params;
}

class WalletConnectServiceException implements Exception, CodedError {
  /// A failure whose text comes from outside the app; shown as is.
  const WalletConnectServiceException(String message)
    : _message = message,
      errorCode = null,
      errorArgs = const <String, Object>{};

  const WalletConnectServiceException.coded(
    AppErrorCode this.errorCode, [
    this.errorArgs = const <String, Object>{},
  ]) : _message = null;

  final String? _message;

  @override
  final AppErrorCode? errorCode;

  @override
  final Map<String, Object> errorArgs;

  @override
  String get message => _message ?? debugDescribeError(errorCode!, errorArgs);

  @override
  String toString() => 'WalletConnectServiceException: $message';
}

/// JSON-RPC error codes sent *to dApps*: the EIP-1193 provider errors, EIP-3326's
/// unrecognized chain, JSON-RPC's own invalid-params/internal errors, and
/// WalletConnect's code for a request the user turned down.
abstract final class DappErrorCode {
  static const int userRejected = 5000;
  static const int unauthorized = 4100;
  static const int unsupportedMethod = 4200;
  static const int unrecognizedChain = 4902;
  static const int invalidParams = -32602;
  static const int internal = -32603;
}

/// JSON-RPC error texts sent *to dApps*. Protocol-facing rather than UI, so
/// they stay English whatever language the wallet itself shows.
abstract final class DappErrorText {
  static const String userRejected = 'User rejected the request.';
  static const String disconnected = 'Disconnected by the wallet.';
  static const String walletNotInitialized = 'Wallet is not initialized.';

  static String signatureRequired(String method) =>
      '$method requires a wallet signature.';
  static String unsupportedMethod(String method) =>
      '$method is not supported by this wallet.';
  static String otherAccount(String address) =>
      'The request is for another account ($address).';
  static String addressNotConnected(String address) =>
      'Address $address is not connected to this session.';
  static String unsupportedChain(int chainId) =>
      'Chain eip155:$chainId is not supported.';
}

/// Wallet-side WalletConnect v2 service: external dApps pair with this wallet,
/// send signing requests, and the wallet approves and signs with the on-device
/// vault. This is the injectable seam (Phase 9). The real `reown_walletkit`
/// implementation arrives in chunk 9.2; [UnavailableWalletConnectService] is the
/// shippable default until then, and [FakeWalletConnectService] drives tests.
abstract interface class WalletConnectService {
  /// Whether a real relay-backed client is configured and usable.
  bool get isAvailable;

  /// Initializes the underlying client (idempotent).
  Future<void> init();

  /// Pairs with a dApp using a `wc:` URI (from a QR scan or paste).
  Future<void> pair({required String uri});

  /// Incoming session proposals awaiting approve/reject.
  Stream<WalletConnectSessionProposal> get sessionProposals;

  /// Approves [proposal], binding the given CAIP-10 [accounts].
  Future<WalletConnectSession> approveSession({
    required WalletConnectSessionProposal proposal,
    required List<String> accounts,
  });

  /// Rejects [proposal].
  Future<void> rejectSession({
    required WalletConnectSessionProposal proposal,
    String? reason,
  });

  /// Currently active sessions.
  List<WalletConnectSession> get activeSessions;

  /// Emits the full active-session list on every change.
  Stream<List<WalletConnectSession>> get sessionsChanges;

  /// Incoming session requests from connected dApps (signing and wallet
  /// methods such as `wallet_switchEthereumChain`).
  Stream<WalletConnectRequest> get requests;

  /// Responds to [request] with a successful JSON-RPC result (e.g. a tx hash,
  /// a signed-tx/signature hex string, or null for EIP-1193 wallet methods).
  Future<void> respondResult({
    required WalletConnectRequest request,
    required Object? result,
  });

  /// Responds to [request] with a JSON-RPC error: one of [DappErrorCode] and
  /// a [DappErrorText] message.
  Future<void> respondError({
    required WalletConnectRequest request,
    required int code,
    required String message,
  });

  /// Makes `eip155:[chainId]` the dApp's chain in session [topic]: adds it to
  /// the session's namespace when the dApp never asked for it, then emits
  /// `chainChanged`, which is what a dApp waits for after
  /// `wallet_switchEthereumChain`.
  Future<void> switchSessionChain({
    required String topic,
    required int chainId,
  });

  /// Disconnects the session identified by [topic].
  Future<void> disconnect({required String topic});

  /// Releases resources / closes streams.
  Future<void> dispose();
}

/// Default production [WalletConnectService] until the real SDK lands (chunk
/// 9.2): it reports unavailable and refuses actions, so the app can show a clear
/// "not configured" state instead of crashing.
class UnavailableWalletConnectService implements WalletConnectService {
  const UnavailableWalletConnectService();

  static const WalletConnectServiceException _notConfigured =
      WalletConnectServiceException.coded(AppErrorCode.wcNotConfigured);

  @override
  bool get isAvailable => false;

  @override
  Future<void> init() async {}

  @override
  Future<void> pair({required String uri}) async {
    throw _notConfigured;
  }

  @override
  Stream<WalletConnectSessionProposal> get sessionProposals =>
      Stream<WalletConnectSessionProposal>.empty();

  @override
  Future<WalletConnectSession> approveSession({
    required WalletConnectSessionProposal proposal,
    required List<String> accounts,
  }) async {
    throw _notConfigured;
  }

  @override
  Future<void> rejectSession({
    required WalletConnectSessionProposal proposal,
    String? reason,
  }) async {}

  @override
  List<WalletConnectSession> get activeSessions =>
      const <WalletConnectSession>[];

  @override
  Stream<List<WalletConnectSession>> get sessionsChanges =>
      Stream<List<WalletConnectSession>>.empty();

  @override
  Stream<WalletConnectRequest> get requests =>
      Stream<WalletConnectRequest>.empty();

  @override
  Future<void> respondResult({
    required WalletConnectRequest request,
    required Object? result,
  }) async {}

  @override
  Future<void> respondError({
    required WalletConnectRequest request,
    required int code,
    required String message,
  }) async {}

  @override
  Future<void> switchSessionChain({
    required String topic,
    required int chainId,
  }) async {
    throw _notConfigured;
  }

  @override
  Future<void> disconnect({required String topic}) async {}

  @override
  Future<void> dispose() async {}
}

/// In-memory [WalletConnectService] for tests and demo/DI: no relay. Tests drive
/// it with [simulateProposal] / [simulateRequest] and inspect [respondedResults]
/// / [respondedErrors]. [pair] auto-emits a proposal so flows are exercisable.
class FakeWalletConnectService implements WalletConnectService {
  FakeWalletConnectService({
    DateTime Function()? now,
    this.proposeOnPair = true,
    this.acknowledgeApproval = true,
  }) : _now = now ?? _defaultNow;

  /// False simulates a dApp whose relay link died: pairing succeeds but no
  /// proposal ever arrives.
  final bool proposeOnPair;

  /// False simulates a dApp that never acknowledges an approved session.
  final bool acknowledgeApproval;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  final DateTime Function() _now;

  final StreamController<WalletConnectSessionProposal> _proposals =
      StreamController<WalletConnectSessionProposal>.broadcast();
  final StreamController<WalletConnectRequest> _requests =
      StreamController<WalletConnectRequest>.broadcast();
  final StreamController<List<WalletConnectSession>> _sessions =
      StreamController<List<WalletConnectSession>>.broadcast();
  final List<WalletConnectSession> _active = <WalletConnectSession>[];

  /// Successful responses recorded for assertions, in arrival order.
  final List<({int id, Object? result})> respondedResults =
      <({int id, Object? result})>[];

  /// Error responses recorded for assertions, in arrival order.
  final List<({int id, int code, String message})> respondedErrors =
      <({int id, int code, String message})>[];

  /// Chain switches announced to dApps, in arrival order.
  final List<({String topic, int chainId})> switchedChains =
      <({String topic, int chainId})>[];

  int _idSeq = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<void> init() async {}

  @override
  Future<void> pair({required String uri}) async {
    if (!uri.startsWith('wc:')) {
      throw const WalletConnectServiceException.coded(
        AppErrorCode.wcInvalidUri,
      );
    }
    if (!proposeOnPair) {
      return;
    }
    // Simulate the relay delivering a proposal shortly after pairing.
    simulateProposal(
      peer: const WalletConnectPeer(
        name: 'Demo dApp',
        url: 'https://demo.dapp',
      ),
    );
  }

  /// Test/demo hook: emit a session proposal as if it came from the relay.
  WalletConnectSessionProposal simulateProposal({
    required WalletConnectPeer peer,
    String pairingTopic = 'demo-pairing',
    List<String> chains = const <String>['eip155:1', 'eip155:11155111'],
    List<String> methods = const <String>[
      'eth_sendTransaction',
      'eth_signTransaction',
      'personal_sign',
    ],
  }) {
    final proposal = WalletConnectSessionProposal(
      id: ++_idSeq,
      pairingTopic: pairingTopic,
      peer: peer,
      requiredChains: chains,
      requiredMethods: methods,
    );
    _proposals.add(proposal);
    return proposal;
  }

  /// Test/demo hook: emit an incoming request on an existing [topic].
  WalletConnectRequest simulateRequest({
    required String topic,
    required String method,
    required List<Object?> params,
    String chainId = 'eip155:1',
  }) {
    final request = WalletConnectRequest(
      id: ++_idSeq,
      topic: topic,
      chainId: chainId,
      method: method,
      params: params,
    );
    _requests.add(request);
    return request;
  }

  @override
  Stream<WalletConnectSessionProposal> get sessionProposals =>
      _proposals.stream;

  @override
  Future<WalletConnectSession> approveSession({
    required WalletConnectSessionProposal proposal,
    required List<String> accounts,
  }) async {
    if (!acknowledgeApproval) {
      return Completer<WalletConnectSession>().future;
    }
    final session = WalletConnectSession(
      topic: 'topic-${proposal.id}',
      peer: proposal.peer,
      chains: proposal.requiredChains,
      accounts: accounts,
      connectedAtUtc: _now(),
    );
    _active.add(session);
    _sessions.add(List<WalletConnectSession>.unmodifiable(_active));
    return session;
  }

  @override
  Future<void> rejectSession({
    required WalletConnectSessionProposal proposal,
    String? reason,
  }) async {}

  @override
  List<WalletConnectSession> get activeSessions =>
      List<WalletConnectSession>.unmodifiable(_active);

  @override
  Stream<List<WalletConnectSession>> get sessionsChanges => _sessions.stream;

  @override
  Stream<WalletConnectRequest> get requests => _requests.stream;

  @override
  Future<void> respondResult({
    required WalletConnectRequest request,
    required Object? result,
  }) async {
    respondedResults.add((id: request.id, result: result));
  }

  @override
  Future<void> respondError({
    required WalletConnectRequest request,
    required int code,
    required String message,
  }) async {
    respondedErrors.add((id: request.id, code: code, message: message));
  }

  @override
  Future<void> switchSessionChain({
    required String topic,
    required int chainId,
  }) async {
    switchedChains.add((topic: topic, chainId: chainId));
  }

  @override
  Future<void> disconnect({required String topic}) async {
    _active.removeWhere((session) => session.topic == topic);
    _sessions.add(List<WalletConnectSession>.unmodifiable(_active));
  }

  @override
  Future<void> dispose() async {
    await _proposals.close();
    await _requests.close();
    await _sessions.close();
  }
}
