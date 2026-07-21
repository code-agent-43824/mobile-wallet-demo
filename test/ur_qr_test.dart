import 'dart:typed_data';

import 'package:bc_ur/bc_ur.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/qr/ur_qr.dart';

void main() {
  test('small UR stays a single frame and uppercase scan is accepted', () {
    final ur = BCUR(
      type: 'eth-signature',
      payload: Uint8List.fromList(<int>[1, 2, 3]),
    ).toString();
    final frames = const UrQrEncoder().encode(ur);
    final assembler = UrQrAssembler(expectedType: 'eth-signature');

    expect(frames, <String>[ur]);
    expect(assembler.add(frames.single.toUpperCase()), isTrue);
    expect(assembler.result, ur);
  });

  test('multipart fountain frames assemble to the original canonical UR', () {
    final ur = BCUR(
      type: 'eth-sign-request',
      payload: Uint8List.fromList(List<int>.generate(420, (i) => i & 0xff)),
    ).toString();
    final frames = const UrQrEncoder(maxFragmentLength: 60).encode(ur);
    final assembler = UrQrAssembler(expectedType: 'eth-sign-request');

    expect(frames.length, greaterThan(1));
    for (final frame in frames.reversed) {
      assembler.add(frame.toUpperCase());
    }

    expect(assembler.isComplete, isTrue);
    expect(assembler.progress, 1);
    expect(assembler.result, ur);
  });

  test('assembler rejects another UR type', () {
    final ur = BCUR(
      type: 'crypto-hdkey',
      payload: Uint8List.fromList(<int>[1]),
    ).toString();
    final assembler = UrQrAssembler(expectedType: 'eth-sign-request');

    expect(() => assembler.add(ur), throwsA(isA<UrQrException>()));
  });
}
