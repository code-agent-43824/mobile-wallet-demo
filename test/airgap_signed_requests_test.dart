import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/airgap/airgap_signed_requests.dart';
import 'package:mobile_wallet_demo/src/airgap/eip4527.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';

EthSignRequest _request(String requestId, List<int> signData) => EthSignRequest(
  requestId: requestId,
  signData: Uint8List.fromList(signData),
  dataType: EthSignDataType.typedTransaction,
  chainId: 11155111,
  derivationPath: CryptoKeypath.parse("M/44'/60'/0'/0/0"),
);

void main() {
  final signedAt = DateTime.utc(2026, 11, 3, 12, 5);

  test('a request is recognised by its id or by its exact bytes', () async {
    final log = AirGapSignedRequestLog(store: InMemorySecureKeyValueStore());
    await log.record(_request('id-1', <int>[1, 2, 3]), signedAt);

    expect(await log.signedAt(_request('id-1', <int>[9])), signedAt);
    // The same transaction under a fresh id is the same request again.
    expect(await log.signedAt(_request('id-2', <int>[1, 2, 3])), signedAt);
    expect(await log.signedAt(_request('id-3', <int>[4])), isNull);
  });

  test('the log survives a new instance over the same store', () async {
    final store = InMemorySecureKeyValueStore();
    await AirGapSignedRequestLog(
      store: store,
    ).record(_request('id-1', <int>[1]), signedAt);

    expect(
      await AirGapSignedRequestLog(
        store: store,
      ).signedAt(_request('id-1', <int>[1])),
      signedAt,
    );
  });

  test('only the latest entries are kept', () async {
    final log = AirGapSignedRequestLog(store: InMemorySecureKeyValueStore());
    for (var i = 0; i <= AirGapSignedRequestLog.capacity; i++) {
      await log.record(_request('id-$i', <int>[i % 256, i ~/ 256]), signedAt);
    }

    expect(await log.signedAt(_request('id-0', <int>[0, 0])), isNull);
    expect(await log.signedAt(_request('id-1', <int>[1, 0])), signedAt);
  });
}
