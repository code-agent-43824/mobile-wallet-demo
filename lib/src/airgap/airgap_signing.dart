import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/crypto.dart';

import '../sessions/remote_signing_session.dart';
import '../transactions/transaction_service.dart';

class AirGapPayloadException implements Exception {
  const AirGapPayloadException(this.message);

  final String message;

  @override
  String toString() => 'AirGapPayloadException: $message';
}

/// Export payload: the unsigned request an air-gapped device receives (e.g. as a
/// QR). Tx fields are hex strings so the payload is chain-agnostic and compact.
class AirGapSigningRequest {
  const AirGapSigningRequest({
    required this.requestId,
    required this.chainId,
    required this.fromAddress,
    required this.toAddress,
    required this.valueWeiHex,
    required this.dataHex,
    required this.nonce,
    required this.gasLimit,
    required this.maxFeePerGasWeiHex,
    required this.maxPriorityFeePerGasWeiHex,
  });

  factory AirGapSigningRequest.fromJson(Map<String, Object?> json) {
    return AirGapSigningRequest(
      requestId: json['requestId'] as String,
      chainId: json['chainId'] as String,
      fromAddress: json['from'] as String,
      toAddress: json['to'] as String,
      valueWeiHex: json['value'] as String,
      dataHex: json['data'] as String,
      nonce: json['nonce'] as int,
      gasLimit: json['gas'] as int,
      maxFeePerGasWeiHex: json['maxFeePerGas'] as String,
      maxPriorityFeePerGasWeiHex: json['maxPriorityFeePerGas'] as String,
    );
  }

  final String requestId;
  final String chainId;
  final String fromAddress;
  final String toAddress;
  final String valueWeiHex;
  final String dataHex;
  final int nonce;
  final int gasLimit;
  final String maxFeePerGasWeiHex;
  final String maxPriorityFeePerGasWeiHex;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requestId': requestId,
      'chainId': chainId,
      'from': fromAddress,
      'to': toAddress,
      'value': valueWeiHex,
      'data': dataHex,
      'nonce': nonce,
      'gas': gasLimit,
      'maxFeePerGas': maxFeePerGasWeiHex,
      'maxPriorityFeePerGas': maxPriorityFeePerGasWeiHex,
    };
  }
}

/// Import payload: the signed response an air-gapped device returns (e.g. as a
/// QR the app scans back).
class AirGapSignedResponse {
  const AirGapSignedResponse({
    required this.requestId,
    required this.rawSignedTransactionHex,
  });

  factory AirGapSignedResponse.fromJson(Map<String, Object?> json) {
    return AirGapSignedResponse(
      requestId: json['requestId'] as String,
      rawSignedTransactionHex: json['rawSignedTransaction'] as String,
    );
  }

  final String requestId;
  final String rawSignedTransactionHex;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requestId': requestId,
      'rawSignedTransaction': rawSignedTransactionHex,
    };
  }
}

/// Serializes the AirGap export/import payloads (the offline-QR contract) and
/// maps a [PreparedTransfer] into a request. No QR/scanner here — just the wire
/// format, scheme-prefixed base64url JSON.
class AirGapPayloadCodec {
  const AirGapPayloadCodec();

  static const String requestScheme = 'airgap-tx';
  static const String responseScheme = 'airgap-sig';

  AirGapSigningRequest buildRequest({
    required PreparedTransfer preparedTransfer,
    required int nonce,
    required String fromAddress,
    String? requestId,
  }) {
    final preview = preparedTransfer.preview;
    final isNative = preview.asset.kind == TransferAssetKind.native;
    final to = isNative ? preview.toAddress : preview.asset.contractAddress!;
    final value = isNative ? preparedTransfer.amountUnits : BigInt.zero;
    final data = preparedTransfer.transaction.data ?? Uint8List(0);
    final chainId = 'eip155:${preparedTransfer.networkConfig.chainId}';

    return AirGapSigningRequest(
      requestId: requestId ?? '$chainId:$fromAddress:$nonce',
      chainId: chainId,
      fromAddress: fromAddress,
      toAddress: to,
      valueWeiHex: '0x${value.toRadixString(16)}',
      dataHex: bytesToHex(data, include0x: true),
      nonce: nonce,
      gasLimit: preview.gasLimit,
      maxFeePerGasWeiHex:
          '0x${preparedTransfer.maxFeePerGasWei.toRadixString(16)}',
      maxPriorityFeePerGasWeiHex:
          '0x${preparedTransfer.maxPriorityFeePerGasWei.toRadixString(16)}',
    );
  }

  String encodeRequest(AirGapSigningRequest request) {
    return '$requestScheme:${_encode(request.toJson())}';
  }

  AirGapSigningRequest decodeRequest(String payload) {
    return AirGapSigningRequest.fromJson(_decode(payload, requestScheme));
  }

  String encodeResponse(AirGapSignedResponse response) {
    return '$responseScheme:${_encode(response.toJson())}';
  }

  AirGapSignedResponse decodeResponse(String payload) {
    return AirGapSignedResponse.fromJson(_decode(payload, responseScheme));
  }

  /// Validates that [response] answers the request identified by
  /// [expectedRequestId], then returns the raw signed transaction bytes.
  Uint8List toSignedBytes(
    AirGapSignedResponse response, {
    required String expectedRequestId,
  }) {
    if (response.requestId != expectedRequestId) {
      throw const AirGapPayloadException(
        'AirGap response does not match the request (request id mismatch).',
      );
    }
    final hex = response.rawSignedTransactionHex;
    final normalized = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (normalized.isEmpty) {
      throw const AirGapPayloadException('AirGap returned an empty signature.');
    }
    return Uint8List.fromList(hexToBytes(normalized));
  }

  String _encode(Map<String, Object?> json) {
    return base64Url.encode(utf8.encode(jsonEncode(json)));
  }

  Map<String, Object?> _decode(String payload, String scheme) {
    final prefix = '$scheme:';
    if (!payload.startsWith(prefix)) {
      throw AirGapPayloadException('Expected a "$prefix..." payload.');
    }
    try {
      final body = payload.substring(prefix.length);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(body)));
      if (decoded is! Map<String, Object?>) {
        throw const AirGapPayloadException('AirGap payload is malformed.');
      }
      return decoded;
    } on AirGapPayloadException {
      rethrow;
    } catch (_) {
      throw const AirGapPayloadException('AirGap payload is malformed.');
    }
  }
}

/// The air-gapped device side: given the export payload it returns the response
/// payload. A real flow shows the request QR, the device signs offline, and the
/// user scans the response QR back; the demo/tests inject one.
abstract interface class AirGapResponseProvider {
  Future<String> provideSignature({
    required AirGapSigningRequest request,
    required String exportPayload,
  });
}

/// AirGap offline-signing connector. It is a [RemoteSigningSessionController]
/// (chunk B) so it plugs into [WalletOperationAuthorizer.authorizeRemoteSigning];
/// it additionally exposes the last export payload (the QR to show the device).
abstract interface class AirGapOfflineConnector
    implements RemoteSigningSessionController {
  /// The last request payload produced for the air-gapped device (QR content).
  String? get lastExportPayload;
}

class DemoAirGapOfflineConnector implements AirGapOfflineConnector {
  DemoAirGapOfflineConnector({
    required AirGapResponseProvider device,
    AirGapPayloadCodec codec = const AirGapPayloadCodec(),
    DateTime Function()? now,
  }) {
    _session = DemoRemoteSigningSessionController(
      label: 'airgap',
      peerLabel: 'AirGap offline device',
      signer: _AirGapRoundTripSigner(
        codec: codec,
        device: device,
        onExport: (payload) => _lastExportPayload = payload,
      ),
      now: now,
    );
  }

  late final DemoRemoteSigningSessionController _session;
  String? _lastExportPayload;

  @override
  String get label => _session.label;

  @override
  RemoteSigningSession get state => _session.state;

  @override
  Stream<RemoteSigningSession> get changes => _session.changes;

  @override
  String? get lastExportPayload => _lastExportPayload;

  @override
  Future<RemoteSigningSession> connect({String? accountAddress}) {
    return _session.connect(accountAddress: accountAddress);
  }

  @override
  Future<Uint8List> requestSignedTransaction({
    required PreparedTransfer preparedTransfer,
    required int nonce,
    required String fromAddress,
  }) {
    return _session.requestSignedTransaction(
      preparedTransfer: preparedTransfer,
      nonce: nonce,
      fromAddress: fromAddress,
    );
  }

  @override
  Future<void> disconnect() => _session.disconnect();

  @override
  Future<void> dispose() => _session.dispose();
}

/// Internal: drives the AirGap export → sign → import round-trip through the
/// codec, exposing the produced export payload via [onExport].
class _AirGapRoundTripSigner implements RemoteSessionSigner {
  _AirGapRoundTripSigner({
    required AirGapPayloadCodec codec,
    required AirGapResponseProvider device,
    required void Function(String exportPayload) onExport,
  }) : _codec = codec,
       _device = device,
       _onExport = onExport;

  final AirGapPayloadCodec _codec;
  final AirGapResponseProvider _device;
  final void Function(String exportPayload) _onExport;

  @override
  Future<Uint8List> sign({
    required PreparedTransfer preparedTransfer,
    required int nonce,
    required String fromAddress,
  }) async {
    final request = _codec.buildRequest(
      preparedTransfer: preparedTransfer,
      nonce: nonce,
      fromAddress: fromAddress,
    );
    final exportPayload = _codec.encodeRequest(request);
    _onExport(exportPayload);

    final responsePayload = await _device.provideSignature(
      request: request,
      exportPayload: exportPayload,
    );
    final response = _codec.decodeResponse(responsePayload);
    return _codec.toSignedBytes(response, expectedRequestId: request.requestId);
  }
}
