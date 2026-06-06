import 'dart:async';
import 'dart:typed_data';

import '../auth/wallet_operation_auth.dart';
import '../transactions/transaction_service.dart';

/// Lifecycle of a remote/protocol-driven signing session (WalletConnect, AirGap,
/// ...). Generalises the Phase 7 external-device session so the same flow/UX can
/// drive a connected wallet or an offline signer.
enum RemoteSigningSessionStatus {
  idle,
  connecting,
  connected,
  awaitingSignature,
  disconnected,
  error,
}

class RemoteSigningSessionException implements Exception {
  const RemoteSigningSessionException(this.message);

  final String message;

  @override
  String toString() => 'RemoteSigningSessionException: $message';
}

/// Immutable snapshot of a remote signing session.
class RemoteSigningSession {
  const RemoteSigningSession({
    required this.transportLabel,
    this.status = RemoteSigningSessionStatus.idle,
    this.sessionId,
    this.peerLabel,
    this.accountAddress,
    this.connectedAtUtc,
    this.lastEventAtUtc,
    this.pendingRequestSummary,
    this.lastError,
  });

  final String transportLabel;
  final RemoteSigningSessionStatus status;
  final String? sessionId;
  final String? peerLabel;
  final String? accountAddress;
  final DateTime? connectedAtUtc;
  final DateTime? lastEventAtUtc;
  final String? pendingRequestSummary;
  final String? lastError;

  bool get isConnected =>
      status == RemoteSigningSessionStatus.connected ||
      status == RemoteSigningSessionStatus.awaitingSignature;

  bool get canRequestSignature =>
      status == RemoteSigningSessionStatus.connected;

  RemoteSigningSession copyWith({
    RemoteSigningSessionStatus? status,
    String? sessionId,
    String? peerLabel,
    String? accountAddress,
    DateTime? connectedAtUtc,
    DateTime? lastEventAtUtc,
    String? pendingRequestSummary,
    bool clearPendingRequest = false,
    String? lastError,
    bool clearError = false,
  }) {
    return RemoteSigningSession(
      transportLabel: transportLabel,
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
      peerLabel: peerLabel ?? this.peerLabel,
      accountAddress: accountAddress ?? this.accountAddress,
      connectedAtUtc: connectedAtUtc ?? this.connectedAtUtc,
      lastEventAtUtc: lastEventAtUtc ?? this.lastEventAtUtc,
      pendingRequestSummary: clearPendingRequest
          ? null
          : (pendingRequestSummary ?? this.pendingRequestSummary),
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Produces the raw signed transaction for a remote session. WalletConnect
/// (chunk C) and AirGap (chunk D) implement this with a real protocol
/// round-trip; the demo/tests inject one that delegates to local signing.
abstract interface class RemoteSessionSigner {
  Future<Uint8List> sign({
    required PreparedTransfer preparedTransfer,
    required int nonce,
    required String fromAddress,
  });
}

/// Drives a remote signing session and exposes it as a [RemoteSigningTransport]
/// (chunk A), so [WalletOperationAuthorizer.authorizeRemoteSigning] can sign
/// through the connected session. WalletConnect (chunk C) and AirGap (chunk D)
/// will provide concrete implementations; [DemoRemoteSigningSessionController]
/// simulates one in-memory.
abstract interface class RemoteSigningSessionController
    implements RemoteSigningTransport {
  RemoteSigningSession get state;

  /// Emits a new snapshot on every lifecycle transition.
  Stream<RemoteSigningSession> get changes;

  Future<RemoteSigningSession> connect({String? accountAddress});

  Future<void> disconnect();

  Future<void> dispose();
}

/// In-memory session that mirrors the Phase 7 external-device demo: it walks the
/// real lifecycle (connect → sign → disconnect) but delegates the actual signing
/// to an injected [RemoteSessionSigner] instead of talking to a real protocol.
class DemoRemoteSigningSessionController
    implements RemoteSigningSessionController {
  DemoRemoteSigningSessionController({
    required String label,
    required RemoteSessionSigner signer,
    this.peerLabel,
    DateTime Function()? now,
  }) : _signer = signer,
       _now = now ?? _defaultNow,
       _state = RemoteSigningSession(transportLabel: label);

  static DateTime _defaultNow() => DateTime.now().toUtc();

  final RemoteSessionSigner _signer;
  final DateTime Function() _now;
  final String? peerLabel;
  final StreamController<RemoteSigningSession> _changes =
      StreamController<RemoteSigningSession>.broadcast();

  RemoteSigningSession _state;

  @override
  String get label => _state.transportLabel;

  @override
  RemoteSigningSession get state => _state;

  @override
  Stream<RemoteSigningSession> get changes => _changes.stream;

  void _emit(RemoteSigningSession next) {
    _state = next;
    if (!_changes.isClosed) {
      _changes.add(next);
    }
  }

  @override
  Future<RemoteSigningSession> connect({String? accountAddress}) async {
    _emit(
      _state.copyWith(
        status: RemoteSigningSessionStatus.connecting,
        lastEventAtUtc: _now(),
        clearError: true,
      ),
    );

    final connectedAt = _now();
    _emit(
      _state.copyWith(
        status: RemoteSigningSessionStatus.connected,
        sessionId: 'demo-session-${connectedAt.microsecondsSinceEpoch}',
        peerLabel: peerLabel,
        accountAddress: accountAddress,
        connectedAtUtc: connectedAt,
        lastEventAtUtc: connectedAt,
      ),
    );
    return _state;
  }

  @override
  Future<Uint8List> requestSignedTransaction({
    required PreparedTransfer preparedTransfer,
    required int nonce,
    required String fromAddress,
  }) async {
    if (!_state.canRequestSignature) {
      throw const RemoteSigningSessionException(
        'Сессия внешнего signer не подключена.',
      );
    }

    _emit(
      _state.copyWith(
        status: RemoteSigningSessionStatus.awaitingSignature,
        lastEventAtUtc: _now(),
        pendingRequestSummary:
            '${preparedTransfer.preview.amountFormatted} → ${preparedTransfer.preview.toAddress}',
        clearError: true,
      ),
    );

    try {
      final raw = await _signer.sign(
        preparedTransfer: preparedTransfer,
        nonce: nonce,
        fromAddress: fromAddress,
      );
      _emit(
        _state.copyWith(
          status: RemoteSigningSessionStatus.connected,
          lastEventAtUtc: _now(),
          clearPendingRequest: true,
        ),
      );
      return raw;
    } catch (error) {
      _emit(
        _state.copyWith(
          status: RemoteSigningSessionStatus.error,
          lastEventAtUtc: _now(),
          lastError: error.toString(),
          clearPendingRequest: true,
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _emit(
      RemoteSigningSession(
        transportLabel: _state.transportLabel,
        status: RemoteSigningSessionStatus.disconnected,
        lastEventAtUtc: _now(),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _changes.close();
  }
}
