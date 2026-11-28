import 'ton_network.dart';

const gramDecimals = 9;

String formatTonAmount(BigInt amount, int? decimals) {
  if (decimals == null || decimals == 0) return amount.toString();
  final scale = BigInt.from(10).pow(decimals);
  final fraction = (amount.abs() % scale)
      .toString()
      .padLeft(decimals, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  final whole = (amount.abs() ~/ scale).toString();
  final sign = amount.isNegative ? '-' : '';
  return fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction';
}

class TonJetton {
  TonJetton({
    required this.network,
    required this.master,
    Object? symbol,
    Object? name,
    Object? decimals,
  }) : symbol = _label(symbol, 24) ?? 'Jetton',
       name = _label(name, 64),
       decimals = _precision(decimals);

  final TonNetwork network;
  final String master;
  final String symbol;
  final String? name;
  final int? decimals;

  static int? _precision(Object? value) {
    final precision = int.tryParse(value.toString());
    return precision != null && precision >= 0 && precision <= 255
        ? precision
        : null;
  }

  static String? _label(Object? value, int limit) {
    if (value is! String) return null;
    // Exclude control and bidi formatting characters in third-party labels.
    final clean = value
        .replaceAll(
          RegExp(r'[\x00-\x1f\x7f-\x9f\u200e\u200f\u202a-\u202e\u2066-\u2069]'),
          '',
        )
        .trim();
    return clean.isEmpty ? null : String.fromCharCodes(clean.runes.take(limit));
  }
}

class TonJettonHolding {
  const TonJettonHolding(this.jetton, this.amount);

  final TonJetton jetton;
  final BigInt amount;
}

class TonActivity {
  const TonActivity({
    required this.amount,
    required this.counterparty,
    required this.time,
    required this.incoming,
    this.jetton,
  });

  final BigInt amount;
  final String counterparty;
  final DateTime time;
  final bool incoming;
  final TonJetton? jetton;
}

class TonJettonSnapshot {
  const TonJettonSnapshot({
    required this.balances,
    required this.activity,
    required this.fetchedAt,
    this.fromCache = false,
  });

  final List<TonJettonHolding> balances;
  final List<TonActivity> activity;
  final DateTime fetchedAt;
  final bool fromCache;

  TonJettonSnapshot asCached() => TonJettonSnapshot(
    balances: balances,
    activity: activity,
    fetchedAt: fetchedAt,
    fromCache: true,
  );
}
