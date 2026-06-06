import 'dart:typed_data';

import 'package:web3dart/crypto.dart';

import '../sessions/remote_signing_session.dart';
import '../transactions/transaction_service.dart';

/// A WalletConnect v2 JSON-RPC request. This is just the wire shape — there is
/// no relay/SDK here (that stays a Phase 8 non-goal).
class WalletConnectRpcRequest {
  const WalletConnectRpcRequest({
    required this.chainId,
    required this.method,
    required this.params,
  });

  /// CAIP-2 chain id, e.g. `eip155:1`.
  final String chainId;

  /// JSON-RPC method, e.g. `eth_signTransaction`.
  final String method;

  /// JSON-RPC params (a single transaction object for `eth_signTransaction`).
  final List<Object?> params;
}

/// Maps the app's prepared transfer to/from the WalletConnect v2 wire format.
/// This is the WC v2 integration contract: a real connector puts these requests
/// on a relay and reads the wallet's response; here it is pure serialization.
class WalletConnectV2RequestCodec {
  const WalletConnectV2RequestCodec();

  static const String signTransactionMethod = 'eth_signTransaction';

  WalletConnectRpcRequest encodeSignTransaction({
    required PreparedTransfer preparedTransfer,
    required int nonce,
    required String fromAddress,
  }) {
    final preview = preparedTransfer.preview;
    final isNative = preview.asset.kind == TransferAssetKind.native;
    final to = isNative ? preview.toAddress : preview.asset.contractAddress!;
    final value = isNative ? preparedTransfer.amountUnits : BigInt.zero;
    final data = preparedTransfer.transaction.data ?? Uint8List(0);

    final txObject = <String, Object?>{
      'from': fromAddress,
      'to': to,
      'data': bytesToHex(data, include0x: true),
      'nonce': _toHex(BigInt.from(nonce)),
      'value': _toHex(value),
      'gas': _toHex(BigInt.from(preview.gasLimit)),
      'maxFeePerGas': _toHex(preparedTransfer.maxFeePerGasWei),
      'maxPriorityFeePerGas': _toHex(preparedTransfer.maxPriorityFeePerGasWei),
    };

    return WalletConnectRpcRequest(
      chainId: 'eip155:${preparedTransfer.networkConfig.chainId}',
      method: signTransactionMethod,
      params: <Object?>[txObject],
    );
  }

  /// Decodes the wallet's `eth_signTransaction` response (a raw signed-tx hex
  /// string) into bytes the app can broadcast itself.
  Uint8List decodeSignedTransaction(String responseHex) {
    final normalized = responseHex.startsWith('0x')
        ? responseHex.substring(2)
        : responseHex;
    if (normalized.isEmpty) {
      throw const RemoteSigningSessionException(
        'WalletConnect вернул пустую подпись.',
      );
    }
    return Uint8List.fromList(hexToBytes(normalized));
  }

  String _toHex(BigInt value) => '0x${value.toRadixString(16)}';
}

/// Metadata about an established WalletConnect v2 session.
class WalletConnectSessionInfo {
  const WalletConnectSessionInfo({
    required this.topic,
    required this.peerName,
    required this.chains,
    required this.accounts,
  });

  final String topic;
  final String peerName;

  /// CAIP-2 chains the session covers, e.g. `eip155:1`.
  final List<String> chains;

  /// CAIP-10 accounts, e.g. `eip155:1:0x...`.
  final List<String> accounts;
}

/// WalletConnect v2 client contract. It is a [RemoteSigningSessionController]
/// (chunk B), so it plugs straight into
/// [WalletOperationAuthorizer.authorizeRemoteSigning]; on top it adds WC pairing
/// and session metadata. [DemoWalletConnectV2Connector] simulates it in-memory.
abstract interface class WalletConnectV2Connector
    implements RemoteSigningSessionController {
  WalletConnectSessionInfo? get sessionInfo;

  /// The last WC request built for a signature (for inspection / UI).
  WalletConnectRpcRequest? get lastRequest;

  /// Pairs using a `wc:` URI and establishes a session.
  Future<RemoteSigningSession> pair({
    required String wcUri,
    String? accountAddress,
  });
}

/// In-memory WC v2 connector: reuses [DemoRemoteSigningSessionController] for the
/// lifecycle, validates the `wc:` URI on pair, builds the WC request via the
/// codec, and delegates the actual signing to an injected [RemoteSessionSigner]
/// (the demo stand-in for the relay round-trip). No networking.
class DemoWalletConnectV2Connector implements WalletConnectV2Connector {
  DemoWalletConnectV2Connector({
    required RemoteSessionSigner signer,
    this.peerName = 'Demo WalletConnect wallet',
    WalletConnectV2RequestCodec codec = const WalletConnectV2RequestCodec(),
    DateTime Function()? now,
  }) : _codec = codec,
       _session = DemoRemoteSigningSessionController(
         label: 'walletconnect',
         peerLabel: peerName,
         signer: signer,
         now: now,
       );

  final String peerName;
  final WalletConnectV2RequestCodec _codec;
  final DemoRemoteSigningSessionController _session;

  WalletConnectSessionInfo? _sessionInfo;
  WalletConnectRpcRequest? _lastRequest;

  @override
  String get label => _session.label;

  @override
  RemoteSigningSession get state => _session.state;

  @override
  Stream<RemoteSigningSession> get changes => _session.changes;

  @override
  WalletConnectSessionInfo? get sessionInfo => _sessionInfo;

  @override
  WalletConnectRpcRequest? get lastRequest => _lastRequest;

  @override
  Future<RemoteSigningSession> connect({String? accountAddress}) {
    return _session.connect(accountAddress: accountAddress);
  }

  @override
  Future<RemoteSigningSession> pair({
    required String wcUri,
    String? accountAddress,
  }) async {
    if (!wcUri.startsWith('wc:')) {
      throw const RemoteSigningSessionException(
        'Некорректный WalletConnect URI (ожидался формат wc:...).',
      );
    }

    final session = await _session.connect(accountAddress: accountAddress);
    _sessionInfo = WalletConnectSessionInfo(
      topic: _topicFromUri(wcUri),
      peerName: peerName,
      chains: const <String>['eip155:1', 'eip155:11155111'],
      accounts: accountAddress == null
          ? const <String>[]
          : <String>['eip155:1:$accountAddress'],
    );
    return session;
  }

  @override
  Future<Uint8List> requestSignedTransaction({
    required PreparedTransfer preparedTransfer,
    required int nonce,
    required String fromAddress,
  }) {
    // Build the WC request so the mapping is exercised; the demo shortcuts the
    // relay round-trip by delegating to the session's injected signer.
    _lastRequest = _codec.encodeSignTransaction(
      preparedTransfer: preparedTransfer,
      nonce: nonce,
      fromAddress: fromAddress,
    );
    return _session.requestSignedTransaction(
      preparedTransfer: preparedTransfer,
      nonce: nonce,
      fromAddress: fromAddress,
    );
  }

  @override
  Future<void> disconnect() async {
    _sessionInfo = null;
    await _session.disconnect();
  }

  @override
  Future<void> dispose() => _session.dispose();

  String _topicFromUri(String wcUri) {
    final withoutScheme = wcUri.substring(3);
    final at = withoutScheme.indexOf('@');
    return at > 0 ? withoutScheme.substring(0, at) : withoutScheme;
  }
}
