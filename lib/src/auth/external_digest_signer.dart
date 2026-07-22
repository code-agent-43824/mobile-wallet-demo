import 'dart:convert';
import 'dart:typed_data';

import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';
// web3dart exports RLP publicly but keeps its namespace internal.
// ignore: implementation_imports
import 'package:web3dart/src/utils/rlp.dart' as rlp;

import '../key_storage/custody_backend.dart';
import '../transactions/transaction_service.dart';
import 'wallet_operation_auth.dart';

class ExternalSignatureFailure implements Exception {
  const ExternalSignatureFailure(this.message);

  final String message;

  @override
  String toString() => 'ExternalSignatureFailure: $message';
}

class RecoverableEvmSignature {
  const RecoverableEvmSignature({
    required this.r,
    required this.s,
    required this.recoveryId,
  });

  final BigInt r;
  final BigInt s;
  final int recoveryId;

  Uint8List toEthSignatureBytes() {
    final out = Uint8List(65);
    _writeUint256(out, 0, r);
    _writeUint256(out, 32, s);
    out[64] = recoveryId + 27;
    return out;
  }

  static void _writeUint256(Uint8List out, int offset, BigInt value) {
    var remaining = value;
    for (var i = 31; i >= 0; i--) {
      out[offset + i] = (remaining & BigInt.from(0xff)).toInt();
      remaining >>= 8;
    }
  }
}

/// Converts device-style raw ECDSA output into canonical recoverable Ethereum
/// signatures, using the expected public address instead of trusting a device
/// supplied recovery id.
class EvmSignatureAssembler {
  const EvmSignatureAssembler();

  static final BigInt _curveOrder = BigInt.parse(
    'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
    radix: 16,
  );
  static final BigInt _halfCurveOrder = _curveOrder >> 1;

  RecoverableEvmSignature recover({
    required Uint8List digest,
    required RawEcdsaSignature rawSignature,
    required String expectedAddress,
  }) {
    if (digest.length != 32) {
      throw ExternalSignatureFailure(
        'Expected a 32-byte digest, got ${digest.length}.',
      );
    }
    final r = bytesToUnsignedInt(rawSignature.r);
    var s = bytesToUnsignedInt(rawSignature.s);
    if (r <= BigInt.zero || r >= _curveOrder) {
      throw const ExternalSignatureFailure('ECDSA r is outside secp256k1.');
    }
    if (s <= BigInt.zero || s >= _curveOrder) {
      throw const ExternalSignatureFailure('ECDSA s is outside secp256k1.');
    }
    if (s > _halfCurveOrder) {
      s = _curveOrder - s;
    }

    final normalizedExpected = expectedAddress.toLowerCase();
    for (var recoveryId = 0; recoveryId <= 1; recoveryId++) {
      try {
        final recovered = ecRecover(
          digest,
          MsgSignature(r, s, recoveryId + 27),
        );
        final publicKey = _leftPad(recovered, 64);
        final address = bytesToHex(
          publicKeyToAddress(publicKey),
          include0x: true,
        ).toLowerCase();
        if (address == normalizedExpected) {
          return RecoverableEvmSignature(r: r, s: s, recoveryId: recoveryId);
        }
      } catch (_) {
        // Try the other y-parity. A malformed signature is rejected below.
      }
    }
    throw ExternalSignatureFailure(
      'Device signature does not recover to $expectedAddress.',
    );
  }

  Uint8List _leftPad(Uint8List value, int length) {
    if (value.length > length) {
      throw const ExternalSignatureFailure(
        'Recovered secp256k1 public key is too long.',
      );
    }
    if (value.length == length) {
      return value;
    }
    return Uint8List(length)..setRange(length - value.length, length, value);
  }
}

/// Transaction/message signer backed only by `signDigest`; it never receives
/// mnemonic or private-key material. This is the consumer used by the future
/// Rutoken Kotlin/Swift adapter and by its deterministic fake tests.
class ExternalDigestWalletTransactionSigner implements WalletTransactionSigner {
  const ExternalDigestWalletTransactionSigner({
    required CustodySigningSession session,
    EvmSignatureAssembler assembler = const EvmSignatureAssembler(),
  }) : _session = session,
       _assembler = assembler;

  final CustodySigningSession _session;
  final EvmSignatureAssembler _assembler;

  @override
  String get backendId => _session.account.backendId;

  @override
  String get address => _session.account.address;

  @override
  Future<SignedTransfer> signPreparedTransfer({
    required TransactionService transactionService,
    required PreparedTransfer preparedTransfer,
    required int nonce,
  }) async {
    if (nonce < 0) {
      throw const TransactionFailure('Nonce должен быть неотрицательным.');
    }
    if (address.toLowerCase() !=
        preparedTransfer.preview.fromAddress.toLowerCase()) {
      throw const TransactionFailure(
        'Аппаратный аккаунт не соответствует адресу отправителя.',
      );
    }
    final transaction = preparedTransfer.transaction.copyWith(
      from: EthereumAddress.fromHex(address),
      nonce: nonce,
    );
    final chainId = preparedTransfer.networkConfig.chainId;
    final digest = keccak256(
      transaction.getUnsignedSerialized(chainId: chainId),
    );
    final signature = await _signDigest(digest);
    final raw = _assembleTransaction(
      transaction: transaction,
      chainId: chainId,
      signature: signature,
    );
    return transactionService.assembleSignedTransfer(
      preparedTransfer: preparedTransfer,
      rawSignedTransaction: raw,
      signingNote: 'Транзакция подписана внешним custody backend.',
    );
  }

  @override
  Future<String> signPersonalMessage({
    required TransactionService transactionService,
    required Uint8List message,
  }) async {
    final prefix = utf8.encode(
      '\u0019Ethereum Signed Message:\n${message.length}',
    );
    final digest = keccak256(Uint8List.fromList(<int>[...prefix, ...message]));
    final signature = await _signDigest(digest);
    return bytesToHex(signature.toEthSignatureBytes(), include0x: true);
  }

  @override
  Future<String> signDigest({
    required TransactionService transactionService,
    required Uint8List digest,
  }) async {
    final signature = await _signDigest(digest);
    return bytesToHex(signature.toEthSignatureBytes(), include0x: true);
  }

  Future<RecoverableEvmSignature> _signDigest(Uint8List digest) async {
    final raw = await _session.signDigest(digest);
    return _assembler.recover(
      digest: digest,
      rawSignature: raw,
      expectedAddress: address,
    );
  }

  Uint8List _assembleTransaction({
    required Transaction transaction,
    required int chainId,
    required RecoverableEvmSignature signature,
  }) {
    if (transaction.isEIP1559) {
      if (transaction.isCeloTx) {
        throw const ExternalSignatureFailure(
          'Celo typed transactions are outside Wallet Demo scope.',
        );
      }
      final body = <dynamic>[
        BigInt.from(chainId),
        transaction.nonce,
        transaction.maxPriorityFeePerGas!.getInWei,
        transaction.maxFeePerGas!.getInWei,
        transaction.maxGas,
        transaction.to?.value ?? '',
        transaction.value?.getInWei ?? BigInt.zero,
        transaction.data ?? Uint8List(0),
        <dynamic>[],
        signature.recoveryId,
        signature.r,
        signature.s,
      ];
      return Uint8List.fromList(<int>[0x02, ...rlp.encode(body)]);
    }

    final v = signature.recoveryId + chainId * 2 + 35;
    final body = <dynamic>[
      transaction.nonce,
      transaction.gasPrice?.getInWei,
      transaction.maxGas,
      transaction.to?.value ?? '',
      transaction.value?.getInWei ?? BigInt.zero,
      transaction.data ?? Uint8List(0),
      v,
      signature.r,
      signature.s,
    ];
    return Uint8List.fromList(rlp.encode(body));
  }
}

extension WalletOperationAuthorizerCustody on WalletOperationAuthorizer {
  /// Authorizes a non-exporting custody session. Unlike the legacy demo path,
  /// no [WalletMaterial] crosses this boundary.
  AuthorizedWalletOperation authorizeCustodySession({
    required CustodySigningSession session,
    WalletAuthMethod authMethod = WalletAuthMethod.externalDevice,
  }) {
    return AuthorizedWalletOperation(
      backendId: session.account.backendId,
      address: session.account.address,
      authMethod: authMethod,
      signer: ExternalDigestWalletTransactionSigner(session: session),
    );
  }
}
