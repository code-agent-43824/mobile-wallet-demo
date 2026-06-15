import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/web3dart.dart' show keccak256;

class Eip712Exception implements Exception {
  const Eip712Exception(this.message);

  final String message;

  @override
  String toString() => 'Eip712Exception: $message';
}

/// Pure-Dart EIP-712 (`eth_signTypedData_v4`) typed-data hashing. Produces the
/// 32-byte digest `keccak256(0x1901 ‖ domainSeparator ‖ hashStruct(message))`
/// that gets signed. Supports nested structs and arrays (v4 semantics).
/// Validated against the canonical EIP-712 "Mail" vector in tests.
class Eip712Encoder {
  const Eip712Encoder();

  /// The 32-byte digest to sign for [typedData] — a decoded
  /// `{types, primaryType, domain, message}` object.
  Uint8List encode(Map<String, dynamic> typedData) {
    final types = _types(typedData['types']);
    final primaryType = typedData['primaryType'];
    if (primaryType is! String) {
      throw const Eip712Exception('EIP-712: primaryType отсутствует.');
    }
    final domain = _asMap(typedData['domain'], 'domain');
    final message = _asMap(typedData['message'], 'message');

    final domainSeparator = _hashStruct('EIP712Domain', domain, types);
    final messageHash = _hashStruct(primaryType, message, types);

    return keccak256(
      Uint8List.fromList(<int>[0x19, 0x01, ...domainSeparator, ...messageHash]),
    );
  }

  Uint8List _hashStruct(
    String type,
    Map<String, dynamic> data,
    Map<String, List<_Field>> types,
  ) {
    return keccak256(_encodeData(type, data, types));
  }

  Uint8List _encodeData(
    String type,
    Map<String, dynamic> data,
    Map<String, List<_Field>> types,
  ) {
    final fields = types[type];
    if (fields == null) {
      throw Eip712Exception('EIP-712: тип "$type" не объявлен.');
    }
    final typeHash = keccak256(
      Uint8List.fromList(utf8.encode(_encodeType(type, types))),
    );
    final out = <int>[...typeHash];
    for (final field in fields) {
      out.addAll(_encodeValue(field.type, data[field.name], types));
    }
    return Uint8List.fromList(out);
  }

  /// `Mail(Person from,Person to,string contents)Person(string name,address wallet)`
  /// — primary type first, then referenced types sorted by name.
  String _encodeType(String primaryType, Map<String, List<_Field>> types) {
    final deps = _dependencies(primaryType, types)..remove(primaryType);
    final ordered = <String>[primaryType, ...(deps.toList()..sort())];
    final buffer = StringBuffer();
    for (final type in ordered) {
      final fields = types[type];
      if (fields == null) {
        throw Eip712Exception('EIP-712: тип "$type" не объявлен.');
      }
      buffer
        ..write(type)
        ..write('(')
        ..write(fields.map((f) => '${f.type} ${f.name}').join(','))
        ..write(')');
    }
    return buffer.toString();
  }

  Uint8List _encodeValue(
    String type,
    dynamic value,
    Map<String, List<_Field>> types,
  ) {
    final arrayMatch = RegExp(r'^(.*)\[(\d*)\]$').firstMatch(type);
    if (arrayMatch != null) {
      final baseType = arrayMatch.group(1)!;
      if (value is! List) {
        throw Eip712Exception('EIP-712: ожидался массив для "$type".');
      }
      final concat = <int>[];
      for (final item in value) {
        concat.addAll(_encodeValue(baseType, item, types));
      }
      return keccak256(Uint8List.fromList(concat));
    }
    if (types.containsKey(type)) {
      return _hashStruct(type, _asMap(value, type), types);
    }
    if (type == 'string') {
      return keccak256(Uint8List.fromList(utf8.encode(value as String)));
    }
    if (type == 'bytes') {
      return keccak256(_bytes(value));
    }
    if (RegExp(r'^bytes([1-9]|[12]\d|3[0-2])$').hasMatch(type)) {
      final b = _bytes(value);
      final out = Uint8List(32);
      out.setRange(0, b.length, b);
      return out;
    }
    if (type == 'address') {
      final b = _bytes(value);
      final out = Uint8List(32);
      out.setRange(32 - b.length, 32, b);
      return out;
    }
    if (type == 'bool') {
      final out = Uint8List(32);
      out[31] = (value == true || value == 'true') ? 1 : 0;
      return out;
    }
    if (RegExp(r'^uint(\d+)?$').hasMatch(type) ||
        RegExp(r'^int(\d+)?$').hasMatch(type)) {
      return _encodeInt(_bigInt(value));
    }
    throw Eip712Exception('EIP-712: неподдерживаемый тип "$type".');
  }

  Uint8List _encodeInt(BigInt value) {
    final out = Uint8List(32);
    // two's complement for negative int<M> values
    var v = value < BigInt.zero ? (BigInt.one << 256) + value : value;
    for (var i = 31; i >= 0; i--) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v = v >> 8;
    }
    return out;
  }

  Map<String, List<_Field>> _types(dynamic raw) {
    if (raw is! Map) {
      throw const Eip712Exception('EIP-712: types отсутствует.');
    }
    final result = <String, List<_Field>>{};
    raw.forEach((key, value) {
      if (value is! List) {
        throw Eip712Exception('EIP-712: поля типа "$key" некорректны.');
      }
      result[key as String] = value.map((f) {
        final m = (f as Map).cast<String, dynamic>();
        return _Field(m['name'] as String, m['type'] as String);
      }).toList();
    });
    return result;
  }

  Set<String> _dependencies(
    String type,
    Map<String, List<_Field>> types, [
    Set<String>? found,
  ]) {
    final acc = found ?? <String>{};
    final base = type.replaceAll(RegExp(r'\[\d*\]'), '');
    if (acc.contains(base) || !types.containsKey(base)) {
      return acc;
    }
    acc.add(base);
    for (final field in types[base]!) {
      _dependencies(field.type, types, acc);
    }
    return acc;
  }

  Map<String, dynamic> _asMap(dynamic v, String what) {
    if (v is! Map) {
      throw Eip712Exception('EIP-712: "$what" должен быть объектом.');
    }
    return v.cast<String, dynamic>();
  }

  Uint8List _bytes(dynamic v) {
    if (v is Uint8List) {
      return v;
    }
    if (v is List<int>) {
      return Uint8List.fromList(v);
    }
    if (v is String) {
      final h = v.startsWith('0x') ? v.substring(2) : v;
      if (h.isEmpty) {
        return Uint8List(0);
      }
      final out = Uint8List(h.length ~/ 2);
      for (var i = 0; i < out.length; i++) {
        out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return out;
    }
    throw Eip712Exception(
      'EIP-712: ожидались байты, получено ${v.runtimeType}.',
    );
  }

  BigInt _bigInt(dynamic v) {
    if (v is BigInt) {
      return v;
    }
    if (v is int) {
      return BigInt.from(v);
    }
    if (v is String) {
      final s = v.trim();
      if (s.startsWith('0x') || s.startsWith('0X')) {
        return BigInt.parse(s.substring(2), radix: 16);
      }
      return BigInt.parse(s);
    }
    throw Eip712Exception(
      'EIP-712: ожидалось число, получено ${v.runtimeType}.',
    );
  }
}

class _Field {
  const _Field(this.name, this.type);

  final String name;
  final String type;
}
