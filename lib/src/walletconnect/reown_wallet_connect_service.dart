import 'dart:async';

import 'package:reown_walletkit/reown_walletkit.dart';

import '../blockchain/network_config.dart';
import 'wallet_connect_service.dart';
import 'wallet_connect_v2.dart';
import 'wc_config.dart';

/// Real relay-backed [WalletConnectService] over `reown_walletkit` (Phase 9
/// chunk 9.2). Maps reown's `ReownWalletKit` + its `Event<T>` callbacks onto our
/// interface and broadcast streams. Android/iOS only (reown isn't supported on
/// Windows/desktop) — `MobileWalletDemoApp` only selects this on mobile when a
/// `WC_PROJECT_ID` is configured; otherwise the `UnavailableWalletConnectService`
/// is used and the `FakeWalletConnectService` drives tests.
///
/// Only the integration is here; it can't be unit-tested without a live relay,
/// so correctness of the *flows* is covered by the fake + the inbound coordinator
/// tests, and this path is validated by on-device dogfooding.
class ReownWalletConnectService implements WalletConnectService {
  ReownWalletConnectService({String? projectId, PairingMetadata? metadata})
    : _projectId = projectId ?? wcProjectId,
      _metadata = metadata ?? _defaultMetadata;

  static const PairingMetadata _defaultMetadata = PairingMetadata(
    name: 'Wallet Demo',
    description: 'Flutter EVM wallet demo — WalletConnect v2 wallet side.',
    url: 'https://github.com/code-agent-43824/mobile-wallet-demo',
    icons: <String>['https://avatars.githubusercontent.com/u/37784886'],
  );

  final String _projectId;
  final PairingMetadata _metadata;

  ReownWalletKit? _kit;
  bool _initStarted = false;

  final StreamController<WalletConnectSessionProposal> _proposals =
      StreamController<WalletConnectSessionProposal>.broadcast();
  final StreamController<WalletConnectRequest> _requests =
      StreamController<WalletConnectRequest>.broadcast();
  final StreamController<List<WalletConnectSession>> _sessions =
      StreamController<List<WalletConnectSession>>.broadcast();

  /// Keeps the original reown proposal data (by id) so [approveSession] can
  /// build the response namespaces (chains/methods/events) faithfully.
  final Map<int, ProposalData> _pendingProposals = <int, ProposalData>{};

  @override
  bool get isAvailable => _projectId.isNotEmpty;

  @override
  Future<void> init() async {
    if (_initStarted) {
      return;
    }
    _initStarted = true;
    try {
      final kit = await ReownWalletKit.createInstance(
        projectId: _projectId,
        metadata: _metadata,
      );
      kit.onSessionProposal.subscribe(_onProposal);
      kit.onSessionRequest.subscribe(_onRequest);
      kit.onSessionConnect.subscribe(_onSessionConnect);
      kit.onSessionDelete.subscribe(_onSessionDelete);
      _kit = kit;
      _emitSessions();
    } catch (error) {
      // Relay unreachable / init failure: stay constructed but inert. The UI
      // shows availability from [isAvailable]; pair/respond then surface a clear
      // error rather than crashing the (unawaited) init.
      _initStarted = false;
    }
  }

  ReownWalletKit _requireKit() {
    final kit = _kit;
    if (kit == null) {
      throw const WalletConnectServiceException(
        'WalletConnect ещё не инициализирован (нет связи с реле?).',
      );
    }
    return kit;
  }

  @override
  Future<void> pair({required String uri}) async {
    final Uri parsed;
    try {
      parsed = Uri.parse(uri.trim());
    } on FormatException {
      throw const WalletConnectServiceException(
        'Некорректный WalletConnect URI.',
      );
    }
    await _requireKit().pair(uri: parsed);
  }

  @override
  Stream<WalletConnectSessionProposal> get sessionProposals =>
      _proposals.stream;

  @override
  Future<WalletConnectSession> approveSession({
    required WalletConnectSessionProposal proposal,
    required List<String> accounts,
  }) async {
    final data = _pendingProposals[proposal.id];
    if (data == null) {
      throw const WalletConnectServiceException(
        'Это предложение сессии больше не активно.',
      );
    }
    final response = await _requireKit().approveSession(
      id: proposal.id,
      namespaces: _approvedNamespaces(data, accounts),
    );
    _pendingProposals.remove(proposal.id);
    final session = response.session;
    _emitSessions();
    if (session == null) {
      throw const WalletConnectServiceException(
        'Реле не вернуло данные сессии после одобрения.',
      );
    }
    return _mapSession(session);
  }

  @override
  Future<void> rejectSession({
    required WalletConnectSessionProposal proposal,
    String? reason,
  }) async {
    _pendingProposals.remove(proposal.id);
    final kit = _kit;
    if (kit == null) {
      return;
    }
    await kit.rejectSession(
      id: proposal.id,
      reason: ReownSignError(
        code: 5000,
        message: reason ?? 'Запрос отклонён пользователем.',
      ),
    );
  }

  @override
  List<WalletConnectSession> get activeSessions {
    final kit = _kit;
    if (kit == null) {
      return const <WalletConnectSession>[];
    }
    return kit.getActiveSessions().values.map(_mapSession).toList();
  }

  @override
  Stream<List<WalletConnectSession>> get sessionsChanges => _sessions.stream;

  @override
  Stream<WalletConnectRequest> get requests => _requests.stream;

  @override
  Future<void> respondResult({
    required WalletConnectRequest request,
    required Object? result,
  }) async {
    final JsonRpcResponse response = JsonRpcResponse(
      id: request.id,
      jsonrpc: '2.0',
      result: result,
    );
    await _requireKit().respondSessionRequest(
      topic: request.topic,
      response: response,
    );
  }

  @override
  Future<void> respondError({
    required WalletConnectRequest request,
    required String message,
  }) async {
    final JsonRpcResponse response = JsonRpcResponse(
      id: request.id,
      jsonrpc: '2.0',
      error: JsonRpcError(code: 5000, message: message),
    );
    await _requireKit().respondSessionRequest(
      topic: request.topic,
      response: response,
    );
  }

  @override
  Future<void> disconnect({required String topic}) async {
    final kit = _kit;
    if (kit == null) {
      return;
    }
    await kit.disconnectSession(
      topic: topic,
      reason: const ReownSignError(code: 6000, message: 'Отключено кошельком.'),
    );
    _emitSessions();
  }

  @override
  Future<void> dispose() async {
    await _proposals.close();
    await _requests.close();
    await _sessions.close();
  }

  // --- reown event handlers ---

  void _onProposal(SessionProposalEvent event) {
    _pendingProposals[event.id] = event.params;
    if (!_proposals.isClosed) {
      _proposals.add(_mapProposal(event.id, event.params));
    }
  }

  void _onRequest(SessionRequestEvent event) {
    if (!_requests.isClosed) {
      _requests.add(_mapRequest(event));
    }
  }

  void _onSessionConnect(SessionConnect event) => _emitSessions();

  void _onSessionDelete(SessionDelete event) => _emitSessions();

  void _emitSessions() {
    if (!_sessions.isClosed) {
      _sessions.add(activeSessions);
    }
  }

  // --- mapping helpers ---

  WalletConnectPeer _mapPeer(PairingMetadata m) {
    return WalletConnectPeer(
      name: m.name,
      url: m.url,
      description: m.description,
      iconUrl: m.icons.isNotEmpty ? m.icons.first : null,
    );
  }

  WalletConnectSessionProposal _mapProposal(int id, ProposalData data) {
    final chains = <String>{};
    final methods = <String>{};
    void collect(String key, RequiredNamespace ns) {
      final nsChains = ns.chains;
      if (nsChains != null) {
        chains.addAll(nsChains);
      } else if (key.contains(':')) {
        chains.add(key);
      }
      methods.addAll(ns.methods);
    }

    data.requiredNamespaces.forEach(collect);
    data.optionalNamespaces.forEach(collect);
    return WalletConnectSessionProposal(
      id: id,
      pairingTopic: data.pairingTopic,
      peer: _mapPeer(data.proposer.metadata),
      requiredChains: chains.toList(),
      requiredMethods: methods.toList(),
    );
  }

  WalletConnectSession _mapSession(SessionData s) {
    final chains = <String>{};
    final accounts = <String>{};
    s.namespaces.forEach((key, ns) {
      accounts.addAll(ns.accounts);
      final nsChains = ns.chains;
      if (nsChains != null) {
        chains.addAll(nsChains);
      }
      for (final account in ns.accounts) {
        final parts = account.split(':');
        if (parts.length >= 2) {
          chains.add('${parts[0]}:${parts[1]}');
        }
      }
    });
    return WalletConnectSession(
      topic: s.topic,
      peer: _mapPeer(s.peer.metadata),
      chains: chains.toList(),
      accounts: accounts.toList(),
      connectedAtUtc: DateTime.now().toUtc(),
    );
  }

  WalletConnectRequest _mapRequest(SessionRequestEvent event) {
    final params = event.params;
    return WalletConnectRequest(
      id: event.id,
      topic: event.topic,
      chainId: event.chainId,
      method: event.method,
      params: params is List ? List<Object?>.from(params) : <Object?>[params],
    );
  }

  /// Builds the approval namespaces from the original proposal, attaching the
  /// wallet's CAIP-10 [accounts] to each namespace by chain/prefix.
  Map<String, Namespace> _approvedNamespaces(
    ProposalData data,
    List<String> accounts,
  ) => const WalletConnectNamespacePolicy().build(
    requiredNamespaces: data.requiredNamespaces,
    optionalNamespaces: data.optionalNamespaces,
    accounts: accounts,
  );
}

/// Pure namespace policy kept outside the relay client so required rejection
/// and optional filtering are regression-testable without a live pairing.
class WalletConnectNamespacePolicy {
  const WalletConnectNamespacePolicy();

  Map<String, Namespace> build({
    required Map<String, RequiredNamespace> requiredNamespaces,
    required Map<String, RequiredNamespace> optionalNamespaces,
    required List<String> accounts,
  }) {
    final supportedChains = <String>{
      for (final config in evmNetworkConfigs.values) 'eip155:${config.chainId}',
    };
    final supportedMethods = WalletConnectV2RequestCodec.supportedMethods;
    final approved = <String, _ApprovedNamespace>{};

    requiredNamespaces.forEach((key, namespace) {
      final chains = _namespaceChains(key, namespace);
      final unsupportedChains = chains.difference(supportedChains);
      final unsupportedMethods = namespace.methods
          .where((method) => !supportedMethods.contains(method))
          .toList();
      if (unsupportedChains.isNotEmpty || unsupportedMethods.isNotEmpty) {
        throw WalletConnectServiceException(
          'dApp требует неподдерживаемые WalletConnect возможности: '
          'сети ${unsupportedChains.join(', ')}, '
          'методы ${unsupportedMethods.join(', ')}.',
        );
      }
      approved
          .putIfAbsent(key, _ApprovedNamespace.new)
          .add(
            chains: chains,
            methods: namespace.methods,
            events: namespace.events,
          );
    });

    optionalNamespaces.forEach((key, namespace) {
      final chains = _namespaceChains(
        key,
        namespace,
      ).intersection(supportedChains);
      final methods = namespace.methods
          .where(supportedMethods.contains)
          .toList();
      if (chains.isEmpty || methods.isEmpty) {
        return;
      }
      approved
          .putIfAbsent(key, _ApprovedNamespace.new)
          .add(chains: chains, methods: methods, events: namespace.events);
    });

    return <String, Namespace>{
      for (final entry in approved.entries)
        entry.key: Namespace(
          accounts: accounts.where((account) {
            final parts = account.split(':');
            final chain = parts.length >= 2
                ? '${parts[0]}:${parts[1]}'
                : account;
            return entry.value.chains.contains(chain);
          }).toList(),
          methods: entry.value.methods.toList(),
          events: entry.value.events.toList(),
          chains: entry.value.chains.toList(),
        ),
    };
  }

  Set<String> _namespaceChains(String key, RequiredNamespace namespace) =>
      (namespace.chains ?? <String>[if (key.contains(':')) key]).toSet();
}

class _ApprovedNamespace {
  final Set<String> chains = <String>{};
  final Set<String> methods = <String>{};
  final Set<String> events = <String>{};

  void add({
    required Iterable<String> chains,
    required Iterable<String> methods,
    required Iterable<String> events,
  }) {
    this.chains.addAll(chains);
    this.methods.addAll(methods);
    this.events.addAll(events);
  }
}
