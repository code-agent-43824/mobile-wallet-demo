import 'dart:typed_data';

import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' hide TransactionReceipt;

import '../airgap/airgap_signing.dart';
import '../key_storage/key_storage_backend.dart';
import '../transactions/transaction_service.dart';
import '../walletconnect/wallet_connect_v2.dart';
import 'remote_signing_session.dart';

enum RemoteSignerKind { walletConnectV2, airGap }

class RemoteSignerDescriptor {
  const RemoteSignerDescriptor({
    required this.kind,
    required this.id,
    required this.label,
    required this.description,
  });

  final RemoteSignerKind kind;
  final String id;
  final String label;
  final String description;
}

/// Catalog of selectable remote signers and a factory for demo connectors. The
/// demo connectors sign the real prepared transaction with the on-device key as
/// a stand-in for the remote party (a real WalletConnect wallet / AirGap device
/// would replace the injected signer with a protocol round-trip).
class RemoteSignerCatalog {
  const RemoteSignerCatalog();

  List<RemoteSignerDescriptor> get descriptors {
    return const <RemoteSignerDescriptor>[
      RemoteSignerDescriptor(
        kind: RemoteSignerKind.walletConnectV2,
        id: 'walletconnect_v2',
        label: 'WalletConnect v2',
        description:
            'Подписать через подключённый WalletConnect-кошелёк (demo: подпись локальным ключом).',
      ),
      RemoteSignerDescriptor(
        kind: RemoteSignerKind.airGap,
        id: 'airgap',
        label: 'AirGap (offline)',
        description:
            'Подписать офлайн через AirGap-устройство по QR (demo: подпись локальным ключом).',
      ),
    ];
  }

  RemoteSigningSessionController createDemoConnector({
    required RemoteSignerKind kind,
    required WalletMaterial walletMaterial,
    required TransactionService transactionService,
  }) {
    switch (kind) {
      case RemoteSignerKind.walletConnectV2:
        return DemoWalletConnectV2Connector(
          signer: _LocalRemoteSessionSigner(
            walletMaterial: walletMaterial,
            transactionService: transactionService,
          ),
        );
      case RemoteSignerKind.airGap:
        return DemoAirGapOfflineConnector(
          device: _LocalAirGapDevice(walletMaterial: walletMaterial),
        );
    }
  }
}

/// Demo WalletConnect/remote signer: signs the prepared tx with the local key.
class _LocalRemoteSessionSigner implements RemoteSessionSigner {
  _LocalRemoteSessionSigner({
    required this.walletMaterial,
    required this.transactionService,
  });

  final WalletMaterial walletMaterial;
  final TransactionService transactionService;

  @override
  Future<Uint8List> sign({
    required PreparedTransfer preparedTransfer,
    required int nonce,
    required String fromAddress,
  }) async {
    final signed = transactionService.signPreparedTransfer(
      preparedTransfer: preparedTransfer,
      walletMaterial: walletMaterial,
      nonce: nonce,
    );
    return signed.rawTransactionBytes;
  }
}

/// Demo AirGap device: rebuilds the transaction from the request payload and
/// signs it locally (mirrors LocalTransactionService EIP-1559 signing), so the
/// offline round-trip produces a real, broadcastable signature in the demo.
class _LocalAirGapDevice implements AirGapResponseProvider {
  _LocalAirGapDevice({
    required this.walletMaterial,
    this.codec = const AirGapPayloadCodec(),
  });

  final WalletMaterial walletMaterial;
  final AirGapPayloadCodec codec;

  @override
  Future<String> provideSignature({
    required AirGapSigningRequest request,
    required String exportPayload,
  }) async {
    final signed = _signRequest(request);
    return codec.encodeResponse(
      AirGapSignedResponse(
        requestId: request.requestId,
        rawSignedTransactionHex: bytesToHex(signed, include0x: true),
      ),
    );
  }

  Uint8List _signRequest(AirGapSigningRequest request) {
    final base = Transaction(
      to: EthereumAddress.fromHex(request.toAddress),
      maxGas: request.gasLimit,
      value: EtherAmount.inWei(_hexToBigInt(request.valueWeiHex)),
      data: Uint8List.fromList(hexToBytes(_strip0x(request.dataHex))),
      maxFeePerGas: EtherAmount.inWei(_hexToBigInt(request.maxFeePerGasWeiHex)),
      maxPriorityFeePerGas: EtherAmount.inWei(
        _hexToBigInt(request.maxPriorityFeePerGasWeiHex),
      ),
    );
    final unsigned = base.copyWith(
      from: EthereumAddress.fromHex(request.fromAddress),
      nonce: request.nonce,
    );
    final credentials = EthPrivateKey.fromHex(walletMaterial.privateKeyHex);
    final chainId = int.parse(request.chainId.split(':').last);
    var signed = signTransactionRaw(unsigned, credentials, chainId: chainId);
    if (unsigned.isEIP1559) {
      signed = prependTransactionType(0x02, signed);
    }
    return signed;
  }

  BigInt _hexToBigInt(String hex) {
    final normalized = _strip0x(hex);
    if (normalized.isEmpty) {
      return BigInt.zero;
    }
    return BigInt.parse(normalized, radix: 16);
  }

  String _strip0x(String hex) {
    return hex.startsWith('0x') ? hex.substring(2) : hex;
  }
}
