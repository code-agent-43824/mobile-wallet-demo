import 'dart:convert';
import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/auth/wallet_operation_auth.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/custody_backend.dart';
import 'package:mobile_wallet_demo/src/key_storage/rutoken_method_channel_adapter.dart';
import 'package:mobile_wallet_demo/src/key_storage/rutoken_provisioning.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/transactions/hardened_transaction_service.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_tracker.dart';
import 'package:mobile_wallet_demo/src/wallet_flow_screen.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_service.dart';
import 'package:web3dart/web3dart.dart'
    show EthPrivateKey, bytesToHex, publicKeyToAddress, sign;

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _expectedMasterPrivateKey =
    'cbedc75b0d6412c85c79bc13875112ef912fd1e756631b5a00330866f22ff184';
const _expectedMasterChainCode =
    'a3fa8c983223306de0f0f65e74ebb1e98aba751633bf91d5fb56529aa5c132c1';

void main() {
  test(
    'imports the BIP39 vector, persists only public metadata, and closes',
    () async {
      final store = _RecordingStore();
      final adapter = _ProvisioningAdapter();
      final service = RutokenProvisioningService(
        adapter: adapter,
        store: store,
      );

      final result = await service.provision(
        mnemonic: _mnemonic,
        passphrase: 'TREZOR',
        pin: '12345678',
      );

      expect(bytesToHex(adapter.masterCopy!), _expectedMasterPrivateKey);
      expect(bytesToHex(adapter.chainCodeCopy!), _expectedMasterChainCode);
      expect(adapter.openCount, 1);
      expect(adapter.closeCount, 1);
      expect(adapter.masterReference, everyElement(0));
      expect(adapter.chainCodeReference, everyElement(0));
      expect(result.account.address, hasLength(42));

      final publicAccount = await service.loadPublicAccount();
      expect(publicAccount?.account.address, result.account.address);
      expect(publicAccount?.accountPath, "m/44'/60'/0'");
      expect(publicAccount?.compressedPublicKey, hasLength(33));
      expect(publicAccount?.chainCode, hasLength(32));

      final persisted = store.values.values.join();
      expect(persisted, isNot(contains('abandon')));
      expect(persisted, isNot(contains('TREZOR')));
      expect(persisted, isNot(contains(_expectedMasterPrivateKey)));
      expect(persisted, contains('"state":"active"'));
    },
  );

  test('normalizes equivalent Unicode passphrases with BIP39 NFKD', () async {
    final composed = _ProvisioningAdapter();
    final decomposed = _ProvisioningAdapter();

    await RutokenProvisioningService(
      adapter: composed,
      store: _RecordingStore(),
    ).provision(mnemonic: _mnemonic, passphrase: 'caf\u00e9', pin: '1234');
    await RutokenProvisioningService(
      adapter: decomposed,
      store: _RecordingStore(),
    ).provision(mnemonic: _mnemonic, passphrase: 'cafe\u0301', pin: '1234');

    expect(composed.masterCopy, decomposed.masterCopy);
    expect(composed.chainCodeCopy, decomposed.chainCodeCopy);
  });

  test(
    'rejects invalid mnemonic before NFC and keeps no active metadata',
    () async {
      final adapter = _ProvisioningAdapter();
      final service = RutokenProvisioningService(
        adapter: adapter,
        store: _RecordingStore(),
      );

      await expectLater(
        service.provision(
          mnemonic: 'abandon abandon abandon',
          passphrase: '',
          pin: '1234',
        ),
        throwsA(isA<RutokenNativeException>()),
      );
      expect(adapter.openCount, 0);
      expect(await service.loadPublicAccount(), isNull);
    },
  );

  test(
    'keeps failed provisioning metadata non-active and closes session',
    () async {
      final adapter = _ProvisioningAdapter(failImport: true);
      final service = RutokenProvisioningService(
        adapter: adapter,
        store: _RecordingStore(),
      );

      await expectLater(
        service.provision(mnemonic: _mnemonic, passphrase: '', pin: '1234'),
        throwsA(isA<StateError>()),
      );
      expect(adapter.closeCount, 1);
      expect(await service.loadPublicAccount(), isNull);
    },
  );

  test(
    'keeps verified public metadata if teardown reports after import',
    () async {
      final adapter = _ProvisioningAdapter(failClose: true);
      final service = RutokenProvisioningService(
        adapter: adapter,
        store: _RecordingStore(),
      );

      await expectLater(
        service.provision(mnemonic: _mnemonic, passphrase: '', pin: '1234'),
        throwsA(isA<StateError>()),
      );
      expect(adapter.closeCount, 1);
      expect(await service.loadPublicAccount(), isNotNull);
    },
  );

  test('generates a 24-word recoverable backup with the chosen passphrase', () {
    final service = RutokenProvisioningService(
      adapter: _ProvisioningAdapter(),
      store: _RecordingStore(),
    );

    final backup = service.generateBackup(passphrase: 'offline secret');

    expect(backup.mnemonic.split(' '), hasLength(24));
    expect(backup.passphrase, 'offline secret');
  });

  test(
    'adopts an existing card without importing and keeps xpub optional',
    () async {
      final adapter = _ProvisioningAdapter();
      await RutokenProvisioningService(
        adapter: adapter,
        store: InMemorySecureKeyValueStore(),
      ).provision(mnemonic: _mnemonic, passphrase: '', pin: '1234');
      final importCountBeforeAdoption = adapter.importCount;
      final store = InMemorySecureKeyValueStore();
      final service = RutokenProvisioningService(
        adapter: adapter,
        store: store,
      );

      final account = await service.adoptExisting(pin: '1234');

      expect(adapter.importCount, importCountBeforeAdoption);
      expect(await service.loadAccountDescriptor(), isNotNull);
      expect(await service.loadPublicAccount(), isNull);
      expect(account.address, adapter.account?.address);
      final publicProfile = await store.read('rutoken.public_account.v1');
      expect(publicProfile, contains('"schema":3'));
      expect(publicProfile, isNot(contains('1234')));
    },
  );

  test(
    'migrates a legacy single-profile record and keeps it selected',
    () async {
      for (final schema in <int>[1, 2]) {
        final store = InMemorySecureKeyValueStore();
        await store.write(
          'rutoken.public_account.v1',
          jsonEncode(_legacyRecord(schema: schema)),
        );
        final service = RutokenProvisioningService(
          adapter: _ProvisioningAdapter(),
          store: store,
        );

        expect(await service.loadAccountDescriptor(), isNotNull);
        expect(await service.loadPublicAccount(), isNotNull);
        final profiles = await service.loadProfiles();
        expect(profiles, hasLength(1), reason: 'schema $schema');
        expect(profiles.single.id, _legacyAddress.toLowerCase());
        expect(profiles.single.serial, isNull);
        expect((await service.loadSelectedProfile())?.id, profiles.single.id);
      }
    },
  );

  test(
    'a legacy half-written record migrates unusable, not selected',
    () async {
      final store = InMemorySecureKeyValueStore();
      await store.write(
        'rutoken.public_account.v1',
        jsonEncode(_legacyRecord(schema: 2, state: 'pending')),
      );
      final service = RutokenProvisioningService(
        adapter: _ProvisioningAdapter(),
        store: store,
      );

      expect(await service.loadProfiles(), isEmpty);
      expect(await service.loadSelectedProfile(), isNull);
      expect(await service.loadAccountDescriptor(), isNull);
    },
  );

  test('records the token serial reported when the session opened', () async {
    final store = InMemorySecureKeyValueStore();
    final service = RutokenProvisioningService(
      adapter: _ProvisioningAdapter(serial: 'RT-0001', tokenLabel: 'Blue'),
      store: store,
    );

    await service.provision(mnemonic: _mnemonic, passphrase: '', pin: '1234');

    final profile = await service.loadSelectedProfile();
    expect(profile?.serial, 'RT-0001');
    expect(profile?.label, 'Blue');
  });

  test('adopting a registered card adds a serial it did not have', () async {
    final store = InMemorySecureKeyValueStore();
    await store.write(
      'rutoken.public_account.v1',
      jsonEncode(_legacyRecord(schema: 2)),
    );
    final adapter = _ProvisioningAdapter(serial: 'RT-0002')
      ..account = const WalletAccountDescriptor(
        backendId: 'rutoken_nfc',
        address: _legacyAddress,
        derivationPath: "m/44'/60'/0'/0/0",
      );
    final service = RutokenProvisioningService(adapter: adapter, store: store);

    await service.adoptExisting(pin: '1234');

    final profile = await service.loadSelectedProfile();
    expect(profile?.serial, 'RT-0002');
    expect(
      profile?.publicAccount,
      isNotNull,
      reason: 'recording the serial must not drop the retained xpub',
    );
  });

  test('selecting an unregistered card is refused', () async {
    final service = RutokenProvisioningService(
      adapter: _ProvisioningAdapter(),
      store: InMemorySecureKeyValueStore(),
    );

    await expectLater(
      service.selectProfile('0xdead'),
      throwsA(isA<RutokenNativeException>()),
    );
  });

  test(
    'adopting the same registered card preserves its retained xpub',
    () async {
      final store = InMemorySecureKeyValueStore();
      final adapter = _ProvisioningAdapter();
      final service = RutokenProvisioningService(
        adapter: adapter,
        store: store,
      );
      await service.provision(mnemonic: _mnemonic, passphrase: '', pin: '1234');
      final importCount = adapter.importCount;

      await service.adoptExisting(pin: '1234');

      expect(adapter.importCount, importCount);
      expect(await service.loadPublicAccount(), isNotNull);
    },
  );

  test(
    'offers biometric PIN after adoption and uses it after cold restart',
    () async {
      final adapter = _ProvisioningAdapter();
      await RutokenProvisioningService(
        adapter: adapter,
        store: InMemorySecureKeyValueStore(),
      ).provision(mnemonic: _mnemonic, passphrase: '', pin: '1234');
      final importCountBeforeAdoption = adapter.importCount;
      final store = InMemorySecureKeyValueStore();
      final first = WalletFlowController(
        store: store,
        biometricAuthGateway: const SimulatedBiometricAuthGateway(),
        rutokenNativeAdapter: adapter,
      );
      await first.loadInitialState();

      await first.adoptExistingRutoken(pin: '1234');

      expect(first.errorMessage, isNull);
      expect(first.summary?.address, adapter.account?.address);
      expect(first.hasPendingRutokenBiometricOffer, isTrue);
      expect(adapter.importCount, importCountBeforeAdoption);

      await first.completeRutokenBiometricOffer(true);

      expect(first.hasPendingRutokenBiometricOffer, isFalse);
      expect(first.biometricsEnabled, isTrue);
      expect(first.canUnlockWithBiometrics, isTrue);
      first.dispose();

      final walletConnect = FakeWalletConnectService();
      final restored = WalletFlowController(
        store: store,
        biometricAuthGateway: const SimulatedBiometricAuthGateway(),
        walletConnectService: walletConnect,
        rutokenNativeAdapter: adapter,
      );
      await restored.loadInitialState();

      expect(restored.biometricsEnabled, isTrue);
      expect(restored.canUnlockWithBiometrics, isTrue);
      walletConnect.simulateRequest(
        topic: 'rutoken-biometric',
        method: 'personal_sign',
        chainId: 'eip155:1',
        params: <Object?>['0x48656c6c6f', restored.summary!.address],
      );
      await pumpEventQueue();
      await restored.approvePendingRequest(useBiometrics: true);

      expect(restored.errorMessage, isNull);
      expect(restored.pendingRequest, isNull);
      expect(walletConnect.respondedResults, hasLength(1));
      expect(adapter.openPins.last, '1234');
      expect(restored.lastUnlockAuthMethod, WalletAuthMethod.biometric);

      restored.dispose();
      await walletConnect.dispose();
    },
  );

  test(
    'selects the real backend, restores it without NFC, and signs through it',
    () async {
      final store = InMemorySecureKeyValueStore();
      final adapter = _ProvisioningAdapter();
      final first = WalletFlowController(
        store: store,
        biometricAuthGateway: const SimulatedBiometricAuthGateway(),
        rutokenNativeAdapter: adapter,
        transactionService: const HardenedTransactionServiceImplementation(),
        transactionBroadcaster: _RecordingBroadcaster(),
        nonceProvider: _StaticNonceProvider(),
      );
      await first.loadInitialState();

      await first.provisionImportedRutoken(
        mnemonic: 'test test test test test test test test test test test junk',
        passphrase: '',
        pin: '1234',
      );

      expect(first.errorMessage, isNull);
      expect(first.stage, WalletFlowStage.unlocked);
      expect(first.summary?.backendId, 'rutoken_nfc');
      expect(first.activeBackend, isA<RutokenCustodyBackend>());
      expect(first.material, isNull);
      expect(adapter.openCount, 1);
      expect(adapter.closeCount, 1);
      final expectedAddress = first.summary!.address;
      first.dispose();

      final service = FakeWalletConnectService();
      final restored = WalletFlowController(
        store: store,
        biometricAuthGateway: const SimulatedBiometricAuthGateway(),
        walletConnectService: service,
        rutokenNativeAdapter: adapter,
        transactionService: const HardenedTransactionServiceImplementation(),
        transactionBroadcaster: _RecordingBroadcaster(),
        nonceProvider: _StaticNonceProvider(),
      );
      await restored.loadInitialState();

      expect(restored.stage, WalletFlowStage.unlocked);
      expect(restored.summary?.backendId, 'rutoken_nfc');
      expect(restored.summary?.address, expectedAddress);
      expect(restored.activeBackend, isA<RutokenCustodyBackend>());
      expect(
        adapter.openCount,
        1,
        reason: 'read-only startup must use public metadata without NFC',
      );

      service.simulateRequest(
        topic: 'rutoken-topic',
        method: 'personal_sign',
        chainId: 'eip155:1',
        params: <Object?>['0x48656c6c6f', expectedAddress],
      );
      await pumpEventQueue();
      await restored.approvePendingRequest(pin: '1234');

      expect(restored.errorMessage, isNull);
      expect(restored.pendingRequest, isNull);
      expect(service.respondedErrors, isEmpty);
      expect(service.respondedResults.single.result, isA<String>());
      expect(adapter.openCount, 2);
      expect(adapter.closeCount, 2);
      expect(adapter.signCount, 1);
      expect(restored.material, isNull);

      const transactionService = HardenedTransactionServiceImplementation();
      final snapshot = WalletChainSnapshot(
        network: EvmNetwork.ethereumSepolia,
        address: expectedAddress,
        nativeBalanceWei: BigInt.parse('1000000000000000000'),
        nativeBalanceFormatted: '1',
        baseFeeGwei: 1,
        providerLabel: 'fake-rpc',
        fetchedAtUtc: DateTime.utc(2026, 7, 23),
        tokenBalances: const <TokenBalanceSnapshot>[],
        recentTransactions: const <RecentTransactionSnapshot>[],
      );
      final result = await restored.authorizeAndSubmitTransfer(
        snapshot: snapshot,
        fromAddress: expectedAddress,
        toAddress: '0x1111111111111111111111111111111111111111',
        amountText: '0.01',
        asset: transactionService
            .availableAssets(
              snapshot: snapshot,
              networkConfig: evmNetworkConfigs[snapshot.network]!,
            )
            .first,
        tracker: TransactionTracker(
          rpcTransport: const _ReceiptTransport(),
          pollInterval: Duration.zero,
          maxAttempts: 1,
        ),
        pin: '1234',
      );

      expect(result, isNotNull);
      expect(await result!.trackingFuture, isNotNull);
      expect(adapter.openCount, 3);
      expect(adapter.closeCount, 3);
      expect(adapter.signCount, 2);
      expect(restored.material, isNull);

      restored.dispose();
      await service.dispose();
    },
  );

  test('migrates a v1.47 public profile to the active backend once', () async {
    final store = InMemorySecureKeyValueStore();
    final adapter = _ProvisioningAdapter();
    await RutokenProvisioningService(
      adapter: adapter,
      store: store,
    ).provision(mnemonic: _mnemonic, passphrase: '', pin: '1234');
    expect(await store.read('wallet.rutoken_backend_registered.v1'), isNull);
    final opensAfterProvisioning = adapter.openCount;

    final controller = WalletFlowController(
      store: store,
      biometricAuthGateway: const SimulatedBiometricAuthGateway(),
      rutokenNativeAdapter: adapter,
    );
    await controller.loadInitialState();

    expect(controller.stage, WalletFlowStage.unlocked);
    expect(controller.summary?.backendId, 'rutoken_nfc');
    expect(controller.activeBackend, isA<RutokenCustodyBackend>());
    expect(await store.read('wallet.rutoken_backend_registered.v1'), '1');
    expect(
      adapter.openCount,
      opensAfterProvisioning,
      reason: 'registration migration must not touch NFC',
    );
    controller.dispose();
  });
}

const _legacyAddress = '0x1234567890AbcdEF1234567890aBcdef12345678';

/// A record exactly as v1.47–v1.53 wrote it: one profile inline, no id, no
/// serial. Hand-built rather than round-tripped through the current writer,
/// which no longer produces this shape.
Map<String, dynamic> _legacyRecord({
  required int schema,
  String state = 'active',
}) => <String, dynamic>{
  'schema': schema,
  'state': state,
  'backendId': 'rutoken_nfc',
  'address': _legacyAddress,
  'derivationPath': "m/44'/60'/0'/0/0",
  'accountPath': "m/44'/60'/0'",
  'accountDepth': 3,
  'compressedPublicKey': base64Encode(Uint8List(33)),
  'chainCode': base64Encode(Uint8List(32)),
  'sourceFingerprint': 111,
  'parentFingerprint': 222,
};

class _StaticNonceProvider implements NonceProvider {
  @override
  Future<LoadedNonce> loadNextNonce({
    required EvmNetworkConfig networkConfig,
    required String address,
  }) async {
    return LoadedNonce(
      network: networkConfig.network,
      address: address,
      nonce: 7,
      providerLabel: 'fake-nonce',
      loadedAtUtc: DateTime.utc(2026, 7, 23),
    );
  }
}

class _RecordingBroadcaster implements TransactionBroadcaster {
  @override
  Future<SubmittedTransfer> submit({
    required SignedTransfer signedTransfer,
  }) async {
    return SubmittedTransfer(
      signedTransfer: signedTransfer,
      providerLabel: 'fake-broadcast',
      networkTransactionHash: signedTransfer.transactionHashHex,
      submittedAtUtc: DateTime.utc(2026, 7, 23),
    );
  }
}

class _ReceiptTransport implements JsonRpcTransport {
  const _ReceiptTransport();

  @override
  Future<Map<String, dynamic>> post({
    required Uri uri,
    required Map<String, dynamic> payload,
  }) async {
    return <String, dynamic>{
      'jsonrpc': '2.0',
      'id': 1,
      'result': <String, dynamic>{
        'status': '0x1',
        'blockNumber': '0x1',
        'gasUsed': '0x5208',
      },
    };
  }
}

class _ProvisioningAdapter implements RutokenNativeAdapter {
  _ProvisioningAdapter({
    this.failImport = false,
    this.failClose = false,
    this.serial = 'SERIAL-A',
    this.tokenLabel = 'Card A',
  });

  final bool failImport;
  final bool failClose;
  final String? serial;
  final String? tokenLabel;
  int openCount = 0;
  int closeCount = 0;
  Uint8List? masterCopy;
  Uint8List? chainCodeCopy;
  Uint8List? masterReference;
  Uint8List? chainCodeReference;
  WalletAccountDescriptor? account;
  Uint8List? addressPrivateKey;
  int signCount = 0;
  int importCount = 0;
  final List<String> openPins = <String>[];

  @override
  Future<RutokenNativeSession> openSession({required String pin}) async {
    openCount++;
    openPins.add(pin);
    return RutokenNativeSession(
      id: 'provision-$openCount',
      openedAtUtc: DateTime.utc(2026, 7, 23),
      serial: serial,
      label: tokenLabel,
    );
  }

  @override
  Future<void> cancelPendingOperation() async {}

  @override
  Future<WalletAccountDescriptor> importWallet({
    required RutokenNativeSession session,
    required Uint8List masterPrivateKey,
    required Uint8List chainCode,
  }) async {
    importCount++;
    masterReference = masterPrivateKey;
    chainCodeReference = chainCode;
    masterCopy = Uint8List.fromList(masterPrivateKey);
    chainCodeCopy = Uint8List.fromList(chainCode);
    if (failImport) throw StateError('token is not empty');

    final master = bip32.BIP32.fromPrivateKey(masterPrivateKey, chainCode);
    final addressNode = master.derivePath(
      RutokenProvisioningService.addressPath,
    );
    final point = RutokenEcPoint.decode(addressNode.publicKey);
    addressPrivateKey = Uint8List.fromList(addressNode.privateKey!);
    account = WalletAccountDescriptor(
      backendId: 'rutoken_nfc',
      address: '0x${bytesToHex(publicKeyToAddress(point.uncompressedXY))}',
      derivationPath: RutokenProvisioningService.addressPath,
    );
    return account!;
  }

  @override
  Future<void> closeSession(RutokenNativeSession session) async {
    closeCount++;
    if (failClose) throw StateError('teardown failed');
  }

  @override
  Future<WalletAccountDescriptor?> readAccountDescriptor(
    RutokenNativeSession session,
  ) async => account;

  @override
  Future<RawEcdsaSignature> signDigest({
    required RutokenNativeSession session,
    required String derivationPath,
    required Uint8List digest,
  }) async {
    signCount++;
    final privateKey = addressPrivateKey;
    if (privateKey == null) {
      throw StateError('wallet not provisioned');
    }
    final signature = sign(digest, EthPrivateKey(privateKey).privateKey);
    return RawEcdsaSignature(
      r: _uint256(signature.r),
      s: _uint256(signature.s),
    );
  }
}

Uint8List _uint256(BigInt value) {
  final out = Uint8List(32);
  var remaining = value;
  for (var index = 31; index >= 0; index--) {
    out[index] = (remaining & BigInt.from(0xff)).toInt();
    remaining >>= 8;
  }
  return out;
}

class _RecordingStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
