import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' show bytesToHex;

import '../errors/app_error.dart';
import 'eip4527.dart';

/// Human-verifiable fields decoded from the unsigned transaction carried by an
/// EIP-4527 request. The exact original bytes are still what gets signed.
class Eip4527TransactionPreview {
  const Eip4527TransactionPreview({
    required this.chainId,
    required this.transactionType,
    required this.nonce,
    required this.gasLimit,
    required this.maxFeePerGasWei,
    required this.toAddress,
    required this.valueWei,
    required this.dataLength,
    required this.selector,
  });

  final int chainId;
  final int transactionType;
  final BigInt nonce;
  final BigInt gasLimit;
  final BigInt maxFeePerGasWei;
  final String? toAddress;
  final BigInt valueWei;
  final int dataLength;
  final String? selector;

  String get networkLabel => switch (chainId) {
    1 => 'Ethereum Mainnet',
    11155111 => 'Sepolia',
    _ => 'chainId $chainId',
  };

  String get transactionTypeLabel => switch (transactionType) {
    0 => 'Legacy',
    1 => 'EIP-2930',
    2 => 'EIP-1559',
    _ => 'Type $transactionType',
  };

  String get valueEth => _formatEth(valueWei);
  String get maximumFeeEth => _formatEth(gasLimit * maxFeePerGasWei);

  static String _formatEth(BigInt wei) {
    const decimals = 18;
    final digits = wei.toString().padLeft(decimals + 1, '0');
    final whole = digits.substring(0, digits.length - decimals);
    final fraction = digits
        .substring(digits.length - decimals)
        .replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? whole : '$whole.$fraction';
  }
}

/// Minimal strict RLP decoder for transaction preview only. It supports the
/// payloads MetaMask can send through EIP-4527 for this release: legacy and
/// EIP-1559 transactions. Signing never reserializes these fields.
class Eip4527TransactionPreviewDecoder {
  const Eip4527TransactionPreviewDecoder();

  Eip4527TransactionPreview decode(EthSignRequest request) {
    if (request.signData.isEmpty) {
      throw const Eip4527Exception.coded(
        AppErrorCode.airgapMalformedTransaction,
        <String, Object>{'detail': 'empty transaction data'},
      );
    }
    return switch (request.dataType) {
      EthSignDataType.transaction => _decodeLegacy(request),
      EthSignDataType.typedTransaction => _decodeTyped(request),
      _ => throw const Eip4527Exception.coded(
        AppErrorCode.airgapUnsupportedTransaction,
        <String, Object>{'detail': 'only transactions are supported'},
      ),
    };
  }

  Eip4527TransactionPreview _decodeLegacy(EthSignRequest request) {
    final list = _decodeTopList(request.signData);
    if (list.length < 9) {
      throw const Eip4527Exception.coded(
        AppErrorCode.airgapMalformedTransaction,
        <String, Object>{
          'detail': 'legacy transaction without an EIP-155 chainId',
        },
      );
    }
    // Keystone/MetaMask vectors may carry an unsigned 9-field transaction
    // with v/r/s = 0 and keep chainId only in the EIP-4527 envelope. Other
    // producers use the EIP-155 signing preimage [chainId, 0, 0]. Accept both.
    final encodedV = _smallInt(list[6], 'chainId/v');
    final embeddedChainId = encodedV == 0 ? request.chainId : encodedV;
    _assertChain(request.chainId, embeddedChainId);
    return _preview(
      chainId: embeddedChainId,
      transactionType: 0,
      fields: list,
      nonceIndex: 0,
      feeIndex: 1,
      gasIndex: 2,
      toIndex: 3,
      valueIndex: 4,
      dataIndex: 5,
    );
  }

  Eip4527TransactionPreview _decodeTyped(EthSignRequest request) {
    final transactionType = request.signData.first;
    if (transactionType != 2) {
      throw Eip4527Exception.coded(
        AppErrorCode.airgapUnsupportedTransaction,
        <String, Object>{
          'detail':
              'transaction type $transactionType; only EIP-1559 is supported',
        },
      );
    }
    final list = _decodeTopList(request.signData.sublist(1));
    if (list.length < 9) {
      throw const Eip4527Exception.coded(
        AppErrorCode.airgapMalformedTransaction,
        <String, Object>{'detail': 'incomplete EIP-1559 transaction'},
      );
    }
    final embeddedChainId = _smallInt(list[0], 'chainId');
    _assertChain(request.chainId, embeddedChainId);
    return _preview(
      chainId: embeddedChainId,
      transactionType: transactionType,
      fields: list,
      nonceIndex: 1,
      feeIndex: 3,
      gasIndex: 4,
      toIndex: 5,
      valueIndex: 6,
      dataIndex: 7,
    );
  }

  Eip4527TransactionPreview _preview({
    required int chainId,
    required int transactionType,
    required List<Object> fields,
    required int nonceIndex,
    required int feeIndex,
    required int gasIndex,
    required int toIndex,
    required int valueIndex,
    required int dataIndex,
  }) {
    final to = _bytes(fields[toIndex], 'to');
    if (to.isNotEmpty && to.length != 20) {
      throw Eip4527Exception.coded(
        AppErrorCode.airgapMalformedTransaction,
        <String, Object>{
          'detail': 'recipient is ${to.length} bytes, expected 20',
        },
      );
    }
    final data = _bytes(fields[dataIndex], 'data');
    return Eip4527TransactionPreview(
      chainId: chainId,
      transactionType: transactionType,
      nonce: _bigInt(fields[nonceIndex], 'nonce'),
      gasLimit: _bigInt(fields[gasIndex], 'gasLimit'),
      maxFeePerGasWei: _bigInt(fields[feeIndex], 'maxFeePerGas'),
      toAddress: to.isEmpty ? null : bytesToHex(to, include0x: true),
      valueWei: _bigInt(fields[valueIndex], 'value'),
      dataLength: data.length,
      selector: data.length < 4
          ? null
          : bytesToHex(data.sublist(0, 4), include0x: true),
    );
  }

  void _assertChain(int outer, int embedded) {
    if (outer != embedded) {
      throw Eip4527Exception.coded(
        AppErrorCode.airgapChainMismatch,
        <String, Object>{'requested': outer, 'embedded': embedded},
      );
    }
  }

  List<Object> _decodeTopList(Uint8List bytes) {
    final decoded = _RlpReader(bytes).read();
    if (decoded is! List<Object>) {
      throw const Eip4527Exception.coded(
        AppErrorCode.airgapMalformedTransaction,
        <String, Object>{'detail': 'expected an RLP list'},
      );
    }
    return decoded;
  }

  Uint8List _bytes(Object value, String field) {
    if (value is! Uint8List) {
      throw Eip4527Exception.coded(
        AppErrorCode.airgapMalformedTransaction,
        <String, Object>{'detail': 'field $field is not an RLP byte string'},
      );
    }
    return value;
  }

  BigInt _bigInt(Object value, String field) {
    final bytes = _bytes(value, field);
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  int _smallInt(Object value, String field) {
    final number = _bigInt(value, field);
    if (number > BigInt.from(0x7fffffff)) {
      throw Eip4527Exception.coded(
        AppErrorCode.airgapMalformedTransaction,
        <String, Object>{'detail': 'field $field is too large'},
      );
    }
    return number.toInt();
  }
}

class _RlpReader {
  _RlpReader(this.bytes);

  final Uint8List bytes;
  int _offset = 0;

  Object read() {
    final value = _readValue();
    if (_offset != bytes.length) {
      throw const Eip4527Exception.coded(
        AppErrorCode.airgapMalformedTransaction,
        <String, Object>{'detail': 'trailing bytes after the transaction'},
      );
    }
    return value;
  }

  Object _readValue() {
    if (_offset >= bytes.length) {
      throw const Eip4527Exception.coded(
        AppErrorCode.airgapMalformedTransaction,
        <String, Object>{'detail': 'truncated RLP payload'},
      );
    }
    final prefix = bytes[_offset++];
    if (prefix <= 0x7f) {
      return Uint8List.fromList(<int>[prefix]);
    }
    if (prefix <= 0xb7) {
      return _take(prefix - 0x80);
    }
    if (prefix <= 0xbf) {
      return _take(_readLength(prefix - 0xb7));
    }
    if (prefix <= 0xf7) {
      return _readList(prefix - 0xc0);
    }
    return _readList(_readLength(prefix - 0xf7));
  }

  int _readLength(int byteCount) {
    if (byteCount < 1 || byteCount > 4 || _offset + byteCount > bytes.length) {
      throw const Eip4527Exception.coded(
        AppErrorCode.airgapMalformedTransaction,
        <String, Object>{'detail': 'invalid RLP length'},
      );
    }
    var result = 0;
    for (var index = 0; index < byteCount; index++) {
      result = (result << 8) | bytes[_offset++];
    }
    return result;
  }

  Uint8List _take(int length) {
    if (length < 0 || _offset + length > bytes.length) {
      throw const Eip4527Exception.coded(
        AppErrorCode.airgapMalformedTransaction,
        <String, Object>{'detail': 'truncated RLP string'},
      );
    }
    final result = Uint8List.fromList(bytes.sublist(_offset, _offset + length));
    _offset += length;
    return result;
  }

  List<Object> _readList(int length) {
    if (length < 0 || _offset + length > bytes.length) {
      throw const Eip4527Exception.coded(
        AppErrorCode.airgapMalformedTransaction,
        <String, Object>{'detail': 'truncated RLP list'},
      );
    }
    final end = _offset + length;
    final result = <Object>[];
    while (_offset < end) {
      result.add(_readValue());
    }
    if (_offset != end) {
      throw const Eip4527Exception.coded(
        AppErrorCode.airgapMalformedTransaction,
        <String, Object>{'detail': 'invalid RLP list boundary'},
      );
    }
    return result;
  }
}
