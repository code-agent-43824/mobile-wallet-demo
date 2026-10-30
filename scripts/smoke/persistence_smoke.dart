// Runs the create and verify smoke phases in separate application processes.
// Both phases use the same build parameters and the platform's real store.
import 'dart:convert';
import 'dart:io';

final RegExp _addressMarker = RegExp(
  r'SMOKE_WALLET_ADDRESS=(0x[0-9a-fA-F]{40})',
);
final RegExp _restoredMarker = RegExp(
  r'SMOKE_WALLET_RESTORED=(0x[0-9a-fA-F]{40})',
);

Future<void> main(List<String> args) async {
  if (args.length != 1 || args.single.isEmpty) {
    stderr.writeln(
      'Usage: dart scripts/smoke/persistence_smoke.dart '
      '<device-id|linux|macos|windows>',
    );
    exitCode = 64;
    return;
  }

  final device = args.single;
  final create = await _runFlutterTest(device, 'create');
  if (create.exitCode != 0) {
    exitCode = create.exitCode;
    return;
  }

  final addresses = _addressMarker.allMatches(create.output).toList();
  if (addresses.length != 1) {
    stderr.writeln(
      'Expected exactly one public wallet address from create '
      'phase, found ${addresses.length}.',
    );
    exitCode = 1;
    return;
  }
  final expectedAddress = addresses.single.group(1)!;
  stdout.writeln('== Restarting the app to verify persisted address ==');
  final verify = await _runFlutterTest(device, 'verify');
  if (verify.exitCode != 0) {
    exitCode = verify.exitCode;
    return;
  }
  final restored = _restoredMarker.allMatches(verify.output).toList();
  if (restored.length != 1 || restored.single.group(1) != expectedAddress) {
    stderr.writeln('Restored wallet address did not match the created wallet.');
    exitCode = 1;
  }
}

Future<({int exitCode, String output})> _runFlutterTest(
  String device,
  String phase,
) async {
  final arguments = <String>[
    'test',
    'integration_test/smoke_test.dart',
    '-d',
    device,
    '--reporter=expanded',
    '--dart-define-from-file=dart_defines.json',
    '--plain-name',
    phase == 'create'
        ? 'a new wallet reaches the dashboard'
        : 'the stored wallet survives a separate app launch',
  ];
  stdout.writeln('== Wallet persistence smoke: $phase on $device ==');
  final process = await Process.start(
    'flutter',
    arguments,
    runInShell: Platform.isWindows,
  );
  final output = StringBuffer();
  await Future.wait([
    process.stdout.transform(utf8.decoder).forEach((text) {
      output.write(text);
      stdout.write(text);
    }),
    process.stderr.transform(utf8.decoder).forEach((text) {
      output.write(text);
      stderr.write(text);
    }),
  ]);
  return (exitCode: await process.exitCode, output: output.toString());
}
