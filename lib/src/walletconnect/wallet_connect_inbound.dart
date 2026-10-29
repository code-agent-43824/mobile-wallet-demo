import '../auth/wallet_operation_auth.dart';
import '../blockchain/network_config.dart';
import '../errors/app_error.dart';
import '../transactions/transaction_service.dart';
import 'eip712.dart';
import 'wallet_connect_preflight.dart';
import 'wallet_connect_service.dart';
import 'wallet_connect_v2.dart';

/// Handles an incoming WalletConnect signing request: decode → build a
/// [PreparedTransfer] → sign with the active account → broadcast
/// (`eth_sendTransaction`) or return the signed hex (`eth_signTransaction`) →
/// respond through the [WalletConnectService]. Every path responds (success or
/// error) so the dApp never hangs. UI/approval gating lives in the screen
/// layer; this is the pure request→sign→respond logic (testable on the fake).
class WalletConnectInboundCoordinator {
  WalletConnectInboundCoordinator({
    required WalletConnectService service,
    required TransactionService transactionService,
    required TransactionBroadcaster broadcaster,
    required NonceProvider nonceProvider,
    WalletConnectTransactionPreflight preflight =
        const RequestFieldsWalletConnectTransactionPreflight(),
    WalletConnectV2RequestCodec codec = const WalletConnectV2RequestCodec(),
  }) : _service = service,
       _txService = transactionService,
       _broadcaster = broadcaster,
       _nonceProvider = nonceProvider,
       _preflight = preflight,
       _codec = codec;

  final WalletConnectService _service;
  final TransactionService _txService;
  final TransactionBroadcaster _broadcaster;
  final NonceProvider _nonceProvider;
  final WalletConnectTransactionPreflight _preflight;
  final WalletConnectV2RequestCodec _codec;

  Future<void> handleRequest({
    required WalletConnectRequest request,
    WalletTransactionSigner? signer,
    String? walletAddress,
    WalletConnectTransactionPreview? transactionPreview,
  }) async {
    try {
      if (_codec.isCapabilitiesMethod(request.method)) {
        await _handleGetCapabilities(
          request,
          walletAddress: walletAddress ?? signer?.address,
        );
        return;
      }

      if (_codec.isChainSwitchMethod(request.method)) {
        try {
          await switchChain(request);
        } on Object {
          // switchChain has already answered the dApp; the wallet UI calls it
          // directly when it needs the failure.
        }
        return;
      }

      if (signer == null) {
        await _service.respondError(
          request: request,
          code: DappErrorCode.unauthorized,
          message: DappErrorText.signatureRequired(request.method),
        );
        return;
      }

      if (_codec.isMessageSignMethod(request.method)) {
        await _handleMessageSign(request: request, signer: signer);
        return;
      }

      if (_codec.isTypedDataMethod(request.method)) {
        await _handleTypedDataSign(request: request, signer: signer);
        return;
      }

      if (!_codec.isTransactionMethod(request.method)) {
        await _service.respondError(
          request: request,
          code: DappErrorCode.unsupportedMethod,
          message: DappErrorText.unsupportedMethod(request.method),
        );
        return;
      }

      final tx = _codec.decodeTransactionRequest(request.params);
      if (tx.fromAddress.toLowerCase() != signer.address.toLowerCase()) {
        await _service.respondError(
          request: request,
          code: DappErrorCode.unauthorized,
          message: DappErrorText.otherAccount(tx.fromAddress),
        );
        return;
      }

      final preview =
          transactionPreview ??
          await _preflight.inspect(
            request: request,
            walletAddress: signer.address,
          );
      if (!preview.matches(request)) {
        throw const WalletConnectPreflightFailure.coded(
          AppErrorCode.wcPreviewMismatch,
        );
      }
      if (preview.fromAddress.toLowerCase() != tx.fromAddress.toLowerCase() ||
          preview.toAddress.toLowerCase() != tx.toAddress.toLowerCase() ||
          preview.valueWei != tx.valueWei ||
          !_sameBytes(preview.data, tx.data)) {
        throw const WalletConnectPreflightFailure.coded(
          AppErrorCode.wcPreviewMismatch,
        );
      }

      final networkConfig = evmNetworkConfigs[preview.network]!;
      var nonce = tx.nonce;
      if (nonce == null) {
        final loaded = await _nonceProvider.loadNextNonce(
          networkConfig: networkConfig,
          address: signer.address,
        );
        nonce = loaded.nonce;
      }

      final prepared = _txService.prepareInboundTransaction(
        network: preview.network,
        fromAddress: signer.address,
        toAddress: preview.toAddress,
        valueWei: preview.valueWei,
        data: preview.data,
        gasLimit: preview.gasLimit,
        maxFeePerGasWei: preview.maxFeePerGasWei,
        maxPriorityFeePerGasWei: preview.maxPriorityFeePerGasWei,
      );

      final signed = await signer.signPreparedTransfer(
        transactionService: _txService,
        preparedTransfer: prepared,
        nonce: nonce,
      );

      final String result;
      if (request.method == WalletConnectV2RequestCodec.sendTransactionMethod) {
        final submitted = await _broadcaster.submit(signedTransfer: signed);
        result = submitted.networkTransactionHash;
      } else {
        result = signed.rawTransactionHex;
      }

      await _service.respondResult(request: request, result: result);
    } catch (error) {
      await _service.respondError(
        request: request,
        code: DappErrorCode.internal,
        message: error.toString(),
      );
    }
  }

  Future<void> _handleGetCapabilities(
    WalletConnectRequest request, {
    required String? walletAddress,
  }) async {
    if (walletAddress == null) {
      await _service.respondError(
        request: request,
        code: DappErrorCode.unauthorized,
        message: DappErrorText.walletNotInitialized,
      );
      return;
    }
    final decoded = _codec.decodeGetCapabilities(request.params);
    if (decoded.address.toLowerCase() != walletAddress.toLowerCase()) {
      await _service.respondError(
        request: request,
        code: DappErrorCode.unauthorized,
        message: DappErrorText.addressNotConnected(decoded.address),
      );
      return;
    }

    final supported = <int>{
      for (final config in evmNetworkConfigs.values) config.chainId,
    };
    final requested = decoded.chainIds == null
        ? supported
        : decoded.chainIds!
              .map(_parseHexChainId)
              .whereType<int>()
              .where(supported.contains)
              .toSet();
    final result = <String, Object?>{
      for (final chainId in requested)
        '0x${chainId.toRadixString(16)}': const <String, Object?>{
          'atomic': <String, Object?>{'status': 'unsupported'},
        },
    };
    await _service.respondResult(request: request, result: result);
  }

  int? _parseHexChainId(String value) {
    if (!value.toLowerCase().startsWith('0x')) {
      return null;
    }
    return int.tryParse(value.substring(2), radix: 16);
  }

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  /// EIP-3326 chain switching changes the dApp session context but does not
  /// access the private key. The request's own CAIP-2 chain can still point at
  /// the old chain; the target is carried in params. The dApp follows the
  /// session's `chainChanged` event rather than this result, so the session is
  /// switched first and answered after. Every outcome answers the dApp; a
  /// failure is then rethrown for the wallet UI.
  Future<void> switchChain(WalletConnectRequest request) async {
    final int chainId;
    try {
      chainId = _codec.decodeSwitchEthereumChainId(request.params);
    } on WalletConnectCodecException catch (error) {
      await _service.respondError(
        request: request,
        code: DappErrorCode.invalidParams,
        message: error.message,
      );
      rethrow;
    }
    final supported = evmNetworkConfigs.values.any(
      (config) => config.chainId == chainId,
    );
    if (!supported) {
      await _service.respondError(
        request: request,
        code: DappErrorCode.unrecognizedChain,
        message: DappErrorText.unsupportedChain(chainId),
      );
      throw WalletConnectServiceException.coded(
        AppErrorCode.wcUnsupportedChain,
        <String, Object>{'chainId': 'eip155:$chainId'},
      );
    }
    try {
      await _service.switchSessionChain(topic: request.topic, chainId: chainId);
    } catch (error) {
      await _service.respondError(
        request: request,
        code: DappErrorCode.internal,
        message: error.toString(),
      );
      rethrow;
    }
    // EIP-3326 success result is JSON null.
    await _service.respondResult(request: request, result: null);
  }

  /// `personal_sign` / `eth_sign`: decode → verify the account → sign the
  /// message (EIP-191) → respond with the 65-byte signature hex. Chain-agnostic,
  /// so there is no network/nonce/broadcast here.
  Future<void> _handleMessageSign({
    required WalletConnectRequest request,
    required WalletTransactionSigner signer,
  }) async {
    final message = _codec.decodeMessageRequest(request.method, request.params);
    if (message.address.toLowerCase() != signer.address.toLowerCase()) {
      await _service.respondError(
        request: request,
        code: DappErrorCode.unauthorized,
        message: DappErrorText.otherAccount(message.address),
      );
      return;
    }

    final signatureHex = await signer.signPersonalMessage(
      transactionService: _txService,
      message: message.message,
    );
    await _service.respondResult(request: request, result: signatureHex);
  }

  /// `eth_signTypedData_v4` / `_v3`: decode → verify the account → build the
  /// EIP-712 digest → sign it raw → respond with the 65-byte signature. Chain
  /// scoping is carried by the typed data's own `domain`, so no network lookup.
  Future<void> _handleTypedDataSign({
    required WalletConnectRequest request,
    required WalletTransactionSigner signer,
  }) async {
    final typed = _codec.decodeTypedDataRequest(request.params);
    if (typed.address.toLowerCase() != signer.address.toLowerCase()) {
      await _service.respondError(
        request: request,
        code: DappErrorCode.unauthorized,
        message: DappErrorText.otherAccount(typed.address),
      );
      return;
    }

    final digest = const Eip712Encoder().encode(typed.typedData);
    final signatureHex = await signer.signDigest(
      transactionService: _txService,
      digest: digest,
    );
    await _service.respondResult(request: request, result: signatureHex);
  }
}
