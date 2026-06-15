import '../auth/wallet_operation_auth.dart';
import '../blockchain/network_config.dart';
import '../transactions/transaction_service.dart';
import 'wallet_connect_service.dart';
import 'wallet_connect_v2.dart';

// Fallbacks used only when an incoming request omits these fields (most dApps
// supply them). Approximate — there is no live snapshot here.
const int _fallbackGasLimit = 90000;
final BigInt _fallbackMaxFeePerGasWei = BigInt.from(30000000000);
final BigInt _fallbackMaxPriorityFeePerGasWei = BigInt.from(2000000000);

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
    WalletConnectV2RequestCodec codec = const WalletConnectV2RequestCodec(),
  }) : _service = service,
       _txService = transactionService,
       _broadcaster = broadcaster,
       _nonceProvider = nonceProvider,
       _codec = codec;

  final WalletConnectService _service;
  final TransactionService _txService;
  final TransactionBroadcaster _broadcaster;
  final NonceProvider _nonceProvider;
  final WalletConnectV2RequestCodec _codec;

  Future<void> handleRequest({
    required WalletConnectRequest request,
    required WalletTransactionSigner signer,
  }) async {
    try {
      if (_codec.isMessageSignMethod(request.method)) {
        await _handleMessageSign(request: request, signer: signer);
        return;
      }

      if (!_codec.isTransactionMethod(request.method)) {
        await _service.respondError(
          request: request,
          message: 'Метод ${request.method} не поддерживается этим кошельком.',
        );
        return;
      }

      final network = _networkForChainId(request.chainId);
      if (network == null) {
        await _service.respondError(
          request: request,
          message: 'Сеть ${request.chainId} не поддерживается.',
        );
        return;
      }

      final tx = _codec.decodeTransactionRequest(request.params);
      if (tx.fromAddress.toLowerCase() != signer.address.toLowerCase()) {
        await _service.respondError(
          request: request,
          message: 'Запрос адресован другому аккаунту (${tx.fromAddress}).',
        );
        return;
      }

      final networkConfig = evmNetworkConfigs[network]!;
      var nonce = tx.nonce;
      if (nonce == null) {
        final loaded = await _nonceProvider.loadNextNonce(
          networkConfig: networkConfig,
          address: signer.address,
        );
        nonce = loaded.nonce;
      }

      final prepared = _txService.prepareInboundTransaction(
        network: network,
        fromAddress: signer.address,
        toAddress: tx.toAddress,
        valueWei: tx.valueWei,
        data: tx.data,
        gasLimit: tx.gasLimit ?? _fallbackGasLimit,
        maxFeePerGasWei: tx.maxFeePerGasWei ?? _fallbackMaxFeePerGasWei,
        maxPriorityFeePerGasWei:
            tx.maxPriorityFeePerGasWei ?? _fallbackMaxPriorityFeePerGasWei,
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
      await _service.respondError(request: request, message: error.toString());
    }
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
        message: 'Запрос адресован другому аккаунту (${message.address}).',
      );
      return;
    }

    final signatureHex = await signer.signPersonalMessage(
      transactionService: _txService,
      message: message.message,
    );
    await _service.respondResult(request: request, result: signatureHex);
  }

  /// Maps a CAIP-2 chain id (e.g. `eip155:1`) to a supported [EvmNetwork], or
  /// null when the chain is not configured.
  EvmNetwork? _networkForChainId(String chainId) {
    final parts = chainId.split(':');
    final raw = parts.length == 2 ? parts.last : chainId;
    final id = int.tryParse(raw);
    if (id == null) {
      return null;
    }
    for (final entry in evmNetworkConfigs.entries) {
      if (entry.value.chainId == id) {
        return entry.key;
      }
    }
    return null;
  }
}
