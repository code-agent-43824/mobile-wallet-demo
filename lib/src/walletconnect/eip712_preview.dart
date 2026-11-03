import '../hidden_text.dart';

/// One leaf of an EIP-712 message, as a person reads it: its path through the
/// message (`details.amount`, `permitted[0].token`) and its value.
class Eip712Field {
  const Eip712Field(this.path, this.value);

  final String path;
  final String value;
}

/// A token allowance an EIP-712 message would grant once signed.
class Eip712Allowance {
  const Eip712Allowance({
    required this.token,
    required this.amount,
    required this.unlimited,
  });

  /// The token contract, when the message or its domain names it.
  final String? token;

  /// In the token's smallest units; null when a flag grants it (DAI's
  /// `allowed`).
  final BigInt? amount;

  /// The largest value of the amount's type, or a granting flag: the spender
  /// may take every token, now and later.
  final bool unlimited;
}

/// What an EIP-712 request asks to sign, for one preview shared by
/// WalletConnect and AirGap.
///
/// Typed data is where signature phishing lives: a `Permit` or `Permit2`
/// signature costs no gas and shows nothing on chain, yet lets someone else
/// move the signer's tokens. So the preview reads every field of the message,
/// and calls out a message that names a `spender`: who it is, how much, and
/// until when. The recognition is generic (field names and their declared
/// types), not a list of known contracts.
class Eip712Preview {
  Eip712Preview._({
    required this.primaryType,
    required this.appName,
    required this.appVersion,
    required this.chainId,
    required this.verifyingContract,
    required this.fields,
    required this.spender,
    required this.allowances,
    required this.deadlines,
  });

  /// Reads a decoded `{types, primaryType, domain, message}` object. Throws
  /// [FormatException] when it is not one; the encoder that hashes it for
  /// signing is stricter still.
  factory Eip712Preview.parse(Map<String, dynamic> typedData) {
    final types = _types(typedData['types']);
    final primaryType = typedData['primaryType'];
    final domain = typedData['domain'];
    final message = typedData['message'];
    if (primaryType is! String || !types.containsKey(primaryType)) {
      throw const FormatException('primaryType is not one of the types');
    }
    if (domain is! Map || message is! Map) {
      throw const FormatException('domain and message must be objects');
    }
    final domainFields = domain.cast<String, dynamic>();
    final verifyingContract = domainFields['verifyingContract'];
    final reader = _Reader(
      types,
      verifyingContract is String ? verifyingContract : null,
    )..walk(primaryType, message, '');
    final name = domainFields['name'];
    final version = domainFields['version'];
    return Eip712Preview._(
      primaryType: primaryType,
      appName: name is String ? revealHiddenText(name) : null,
      appVersion: version is String ? revealHiddenText(version) : null,
      chainId: _chainId(domainFields['chainId']),
      verifyingContract: verifyingContract is String ? verifyingContract : null,
      fields: reader.fields,
      spender: reader.spender,
      allowances: reader.spender == null
          ? const <Eip712Allowance>[]
          : reader.allowances,
      deadlines: reader.deadlines,
    );
  }

  final String primaryType;

  /// The domain's `name` and `version`: the app or contract that asks.
  final String? appName;
  final String? appVersion;

  /// The domain's `chainId`, or null when the domain names none.
  final int? chainId;
  final String? verifyingContract;

  /// Every leaf of the message, in the order the types declare them.
  final List<Eip712Field> fields;

  /// The first `spender` address in the message; null when it grants none.
  final String? spender;

  /// The allowances granted to [spender]; empty when there is no spender.
  final List<Eip712Allowance> allowances;

  /// Time limits in the message (`deadline`, `sigDeadline`, `expiration`,
  /// `expiry`) with their paths, as Unix seconds.
  final List<({String path, BigInt seconds})> deadlines;

  /// Whether the signature would let [spender] move the signer's tokens.
  bool get grantsSpending => spender != null;

  /// Whether a request on [requestChainId] may sign this: a domain that names
  /// another chain makes a signature usable there instead.
  bool isForChain(int requestChainId) =>
      chainId == null || chainId == requestChainId;

  /// [seconds] since the Unix epoch as `YYYY-MM-DD HH:MM UTC`, or null when it
  /// is past year 9999 (a "never expires" sentinel).
  static String? formatUnixSeconds(BigInt seconds) {
    if (seconds > BigInt.from(253402300799)) {
      return null;
    }
    final time = DateTime.fromMillisecondsSinceEpoch(
      seconds.toInt() * 1000,
      isUtc: true,
    );
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year.toString().padLeft(4, '0')}-${two(time.month)}-'
        '${two(time.day)} ${two(time.hour)}:${two(time.minute)} UTC';
  }

  static Map<String, List<({String name, String type})>> _types(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('types must be an object');
    }
    return <String, List<({String name, String type})>>{
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is List)
          entry.key as String: <({String name, String type})>[
            for (final field in entry.value as List)
              if (field case {
                'name': final String name,
                'type': final String type,
              })
                (name: name, type: type),
          ],
    };
  }

  static int? _chainId(Object? raw) => switch (raw) {
    final int value => value,
    final String value when value.startsWith('0x') => int.tryParse(
      value.substring(2),
      radix: 16,
    ),
    final String value => int.tryParse(value),
    _ => null,
  };
}

class _Reader {
  _Reader(this.types, this.verifyingContract);

  final Map<String, List<({String name, String type})>> types;
  final String? verifyingContract;
  final List<Eip712Field> fields = <Eip712Field>[];
  final List<Eip712Allowance> allowances = <Eip712Allowance>[];
  final List<({String path, BigInt seconds})> deadlines =
      <({String path, BigInt seconds})>[];
  String? spender;

  static const Set<String> _amountNames = <String>{'value', 'amount'};
  static const Set<String> _deadlineNames = <String>{
    'deadline',
    'sigDeadline',
    'expiration',
    'expiry',
  };

  void walk(String type, Object? value, String path) {
    final bracket = type.lastIndexOf('[');
    if (bracket > 0 && type.endsWith(']')) {
      final items = value is List ? value : const <Object?>[];
      for (var index = 0; index < items.length; index++) {
        walk(type.substring(0, bracket), items[index], '$path[$index]');
      }
      return;
    }
    final struct = types[type];
    if (struct != null) {
      final map = value is Map
          ? value.cast<String, dynamic>()
          : const <String, dynamic>{};
      for (final field in struct) {
        walk(
          field.type,
          map[field.name],
          path.isEmpty ? field.name : '$path.${field.name}',
        );
      }
      _noteAllowance(struct, map);
      return;
    }
    _leaf(type, value, path);
  }

  void _leaf(String type, Object? value, String path) {
    final name = path.split('.').last;
    if (type.startsWith('uint') || type.startsWith('int')) {
      final number = _number(value);
      if (number == null) {
        fields.add(Eip712Field(path, '$value'));
        return;
      }
      final date = _deadlineNames.contains(name)
          ? Eip712Preview.formatUnixSeconds(number)
          : null;
      if (_deadlineNames.contains(name)) {
        deadlines.add((path: path, seconds: number));
      }
      fields.add(
        Eip712Field(path, date == null ? '$number' : '$number ($date)'),
      );
      return;
    }
    if (type == 'address' && name == 'spender' && value is String) {
      spender ??= value;
    }
    fields.add(
      Eip712Field(path, value is String ? revealHiddenText(value) : '$value'),
    );
  }

  /// A struct holding an amount (`value`/`amount`) or DAI's `allowed` flag
  /// is an allowance; its token is a sibling `token` field or, for EIP-2612,
  /// the domain's contract.
  void _noteAllowance(
    List<({String name, String type})> struct,
    Map<String, dynamic> map,
  ) {
    final token = map['token'] is String
        ? map['token'] as String
        : verifyingContract;
    for (final field in struct) {
      if (_amountNames.contains(field.name) && field.type.startsWith('uint')) {
        final amount = _number(map[field.name]);
        if (amount == null) continue;
        final bits = int.tryParse(field.type.substring(4)) ?? 256;
        allowances.add(
          Eip712Allowance(
            token: token,
            amount: amount,
            unlimited: amount == (BigInt.one << bits) - BigInt.one,
          ),
        );
      } else if (field.name == 'allowed' && field.type == 'bool') {
        final granted = map['allowed'] == true;
        allowances.add(
          Eip712Allowance(
            token: token,
            amount: granted ? null : BigInt.zero,
            unlimited: granted,
          ),
        );
      }
    }
  }

  static BigInt? _number(Object? value) => switch (value) {
    final int number => BigInt.from(number),
    final BigInt number => number,
    final String text when text.startsWith('0x') => BigInt.tryParse(
      text.substring(2),
      radix: 16,
    ),
    final String text => BigInt.tryParse(text),
    _ => null,
  };
}
