import 'dart:convert';

import 'package:web3dart/web3dart.dart' show bytesToHex, keccak256;

import '../key_storage/secure_key_value_store.dart';
import 'eip4527.dart';

/// The AirGap requests this wallet has signed, so loading one again can be
/// called out before it is signed twice.
///
/// MetaMask consumes a request id once it takes the signature, but nothing
/// stops the same request from being shown to the wallet again. Signing it
/// twice gives nothing new to an attacker — the transaction keeps its nonce,
/// so the chain accepts it at most once — so this is a notice, not a block.
/// A request counts as seen when its id or its exact bytes match.
class AirGapSignedRequestLog {
  AirGapSignedRequestLog({required SecureKeyValueStore store}) : _store = store;

  static const String storageKey = 'airgap_signed_requests_v1';

  /// Older entries are dropped beyond this many.
  static const int capacity = 200;

  final SecureKeyValueStore _store;

  /// When [request] was signed before, or null when it was not.
  Future<DateTime?> signedAt(EthSignRequest request) async {
    final digest = _digest(request);
    for (final entry in (await _entries()).reversed) {
      if (entry.id == request.requestId || entry.digest == digest) {
        return entry.signedAtUtc;
      }
    }
    return null;
  }

  /// Remembers that [request] was signed at [signedAtUtc].
  Future<void> record(EthSignRequest request, DateTime signedAtUtc) async {
    final entries = await _entries()
      ..add((
        id: request.requestId,
        digest: _digest(request),
        signedAtUtc: signedAtUtc.toUtc(),
      ));
    final kept = entries.length > capacity
        ? entries.sublist(entries.length - capacity)
        : entries;
    await _store.write(
      storageKey,
      jsonEncode(<Object>[
        for (final entry in kept)
          <String, String>{
            'id': entry.id,
            'digest': entry.digest,
            'at': entry.signedAtUtc.toIso8601String(),
          },
      ]),
    );
  }

  Future<List<({String id, String digest, DateTime signedAtUtc})>>
  _entries() async {
    final raw = await _store.read(storageKey);
    if (raw == null) {
      return <({String id, String digest, DateTime signedAtUtc})>[];
    }
    return <({String id, String digest, DateTime signedAtUtc})>[
      for (final item in jsonDecode(raw) as List<Object?>)
        if (item case {
          'id': final String id,
          'digest': final String digest,
          'at': final String at,
        })
          (id: id, digest: digest, signedAtUtc: DateTime.parse(at)),
    ];
  }

  String _digest(EthSignRequest request) =>
      bytesToHex(keccak256(request.signData));
}
