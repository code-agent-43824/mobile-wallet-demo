import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/airgap/eip4527.dart';
import 'package:mobile_wallet_demo/src/airgap/eip4527_inbound.dart';
import 'package:mobile_wallet_demo/src/auth/external_digest_signer.dart';
import 'package:mobile_wallet_demo/src/auth/wallet_operation_auth.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/custody_backend.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';
import 'package:wallet/wallet.dart' show EthereumAddress, EtherAmount;
import 'package:web3dart/web3dart.dart';

const _address = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
const _privateKeyHex =
    'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
const _material = WalletMaterial(
  address: _address,
  mnemonic: 'test test test test test test test test test test test junk',
  privateKeyHex: _privateKeyHex,
);
const _service = LocalTransactionService();

void main() {
  group('Rutoken native custody seam', () {
    test(
      'opens, reads, signs, and closes exactly one native session',
      () async {
        final adapter = _FakeRutokenNativeAdapter();
        final backend = RutokenCustodyBackend(adapter: adapter);

        final publicAccount = await backend.readAccountPublicKey(pin: '1234');
        expect(publicAccount.account.address, _address);
        expect(adapter.openCount, 1);
        expect(adapter.closeCount, 1);

        final session = await backend.openSigningSession(pin: '1234');
        final digest = keccak256(Uint8List.fromList(utf8.encode('rutoken')));
        final signature = await session.signDigest(digest);
        expect(signature.toBytes(), hasLength(64));
        expect(adapter.openCount, 2);
        expect(adapter.closeCount, 1);

        await session.close();
        await session.close();
        expect(adapter.closeCount, 2, reason: 'close must be idempotent');
        expect(() => session.signDigest(digest), throwsA(isA<StateError>()));
      },
    );

    test('closes native session when account discovery fails', () async {
      final adapter = _FakeRutokenNativeAdapter(hasAccount: false);
      final backend = RutokenCustodyBackend(adapter: adapter);

      await expectLater(
        backend.openSigningSession(pin: '1234'),
        throwsA(isA<StateError>()),
      );
      expect(adapter.openCount, 1);
      expect(adapter.closeCount, 1);
    });
  });

  group('device r || s EVM parity', () {
    test('assembles byte-identical EIP-1559 transaction', () async {
      final session = _FakeCustodySigningSession();
      final signer = ExternalDigestWalletTransactionSigner(session: session);
      final prepared = _preparedTransfer();

      final local = _service.signPreparedTransfer(
        preparedTransfer: prepared,
        walletMaterial: _material,
        nonce: 7,
      );
      final external = await signer.signPreparedTransfer(
        transactionService: _service,
        preparedTransfer: prepared,
        nonce: 7,
      );

      expect(external.rawTransactionBytes, local.rawTransactionBytes);
      expect(external.transactionHashHex, local.transactionHashHex);
      expect(session.digests, hasLength(1));
    });

    test('assembles byte-identical legacy EIP-155 transaction', () async {
      final signer = ExternalDigestWalletTransactionSigner(
        session: _FakeCustodySigningSession(),
      );
      final prepared = _preparedLegacyTransfer();

      final local = _service.signPreparedTransfer(
        preparedTransfer: prepared,
        walletMaterial: _material,
        nonce: 8,
      );
      final external = await signer.signPreparedTransfer(
        transactionService: _service,
        preparedTransfer: prepared,
        nonce: 8,
      );

      expect(external.rawTransactionBytes, local.rawTransactionBytes);
      expect(external.transactionHashHex, local.transactionHashHex);
    });

    test('matches personal_sign and raw digest signatures', () async {
      final signer = ExternalDigestWalletTransactionSigner(
        session: _FakeCustodySigningSession(),
      );
      final message = Uint8List.fromList(utf8.encode('hello Rutoken'));
      final digest = keccak256(Uint8List.fromList(utf8.encode('EIP-712')));

      expect(
        await signer.signPersonalMessage(
          transactionService: _service,
          message: message,
        ),
        _service.signPersonalMessage(
          walletMaterial: _material,
          message: message,
        ),
      );
      expect(
        await signer.signDigest(transactionService: _service, digest: digest),
        _service.signDigest(walletMaterial: _material, digest: digest),
      );
    });

    test('matches EIP-4527 typed-transaction signature response', () async {
      final external = ExternalDigestWalletTransactionSigner(
        session: _FakeCustodySigningSession(),
      );
      final local = LocalKeyMaterialTransactionSigner(
        backendId: 'phone_secure_vault',
        walletMaterial: _material,
      );
      final request = EthSignRequest(
        requestId: '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
        signData: Uint8List.fromList(
          hexToBytes(
            '02e80180843b9aca0085069db9ac0082520894'
            '11111111111111111111111111111111111111110180c0',
          ),
        ),
        dataType: EthSignDataType.typedTransaction,
        chainId: 1,
        derivationPath: CryptoKeypath.parse("M/44'/60'/0'/0/0"),
        address: Uint8List.fromList(hexToBytes(_address.substring(2))),
      );
      const coordinator = Eip4527InboundCoordinator();

      final localResponse = await coordinator.signRequest(
        request: request,
        signer: local,
        transactionService: _service,
      );
      final externalResponse = await coordinator.signRequest(
        request: request,
        signer: external,
        transactionService: _service,
      );

      expect(externalResponse.signature, localResponse.signature);
    });

    test('normalizes high-s and recovers the expected address', () {
      final digest = keccak256(Uint8List.fromList(utf8.encode('high-s')));
      final local = sign(
        digest,
        EthPrivateKey.fromHex(_privateKeyHex).privateKey,
      );
      final curveOrder = BigInt.parse(
        'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
        radix: 16,
      );
      final highS = curveOrder - local.s;
      final recovered = const EvmSignatureAssembler().recover(
        digest: digest,
        rawSignature: RawEcdsaSignature(
          r: _uint256(local.r),
          s: _uint256(highS),
        ),
        expectedAddress: _address,
      );

      expect(recovered.s, local.s);
      expect(recovered.recoveryId + 27, local.v);
    });
  });
}

PreparedTransfer _preparedTransfer() {
  const network = EvmNetwork.ethereumMainnet;
  final snapshot = WalletChainSnapshot(
    network: network,
    address: _address,
    nativeBalanceWei: BigInt.parse('1000000000000000000'),
    nativeBalanceFormatted: '1',
    baseFeeGwei: 12,
    providerLabel: 'fake',
    fetchedAtUtc: DateTime.utc(2026, 7, 22),
    tokenBalances: const <TokenBalanceSnapshot>[],
    recentTransactions: const <RecentTransactionSnapshot>[],
  );
  final asset = _service
      .availableAssets(
        snapshot: snapshot,
        networkConfig: evmNetworkConfigs[network]!,
      )
      .single;
  return _service.prepareTransfer(
    snapshot: snapshot,
    fromAddress: _address,
    toAddress: '0x2222222222222222222222222222222222222222',
    amountText: '0.1',
    asset: asset,
  );
}

PreparedTransfer _preparedLegacyTransfer() {
  final network = evmNetworkConfigs[EvmNetwork.ethereumMainnet]!;
  final asset = TransferAssetOption(
    kind: TransferAssetKind.native,
    symbol: 'ETH',
    name: 'Ethereum',
    balanceFormatted: '1',
    balanceRaw: BigInt.parse('1000000000000000000'),
    decimals: 18,
  );
  final preview = TransferPreview(
    network: EvmNetwork.ethereumMainnet,
    fromAddress: _address,
    toAddress: '0x2222222222222222222222222222222222222222',
    asset: asset,
    amountFormatted: '0.1 ETH',
    gasLimit: 21000,
    maxFeePerGasGwei: 12,
    estimatedNetworkFeeNativeFormatted: '0.000252 ETH',
    totalDebitFormatted: '0.100252 ETH',
    previewNote: 'legacy test',
  );
  final gasPrice = BigInt.from(12000000000);
  final amount = BigInt.parse('100000000000000000');
  return PreparedTransfer(
    preview: preview,
    networkConfig: network,
    amountUnits: amount,
    maxFeePerGasWei: gasPrice,
    maxPriorityFeePerGasWei: BigInt.zero,
    estimatedFeeWei: gasPrice * BigInt.from(21000),
    transaction: Transaction(
      to: EthereumAddress.fromHex(preview.toAddress),
      maxGas: 21000,
      gasPrice: EtherAmount.inWei(gasPrice),
      value: EtherAmount.inWei(amount),
      data: Uint8List(0),
    ),
  );
}

class _FakeCustodySigningSession implements CustodySigningSession {
  @override
  final WalletAccountDescriptor account = const WalletAccountDescriptor(
    backendId: 'rutoken_nfc',
    address: _address,
    derivationPath: "m/44'/60'/0'/0/0",
  );

  final List<Uint8List> digests = <Uint8List>[];

  @override
  Future<void> close() async {}

  @override
  Future<RawEcdsaSignature> signDigest(Uint8List digest) async {
    digests.add(Uint8List.fromList(digest));
    final signature = sign(
      digest,
      EthPrivateKey.fromHex(_privateKeyHex).privateKey,
    );
    return RawEcdsaSignature(
      r: _uint256(signature.r),
      s: _uint256(signature.s),
    );
  }
}

class _FakeRutokenNativeAdapter implements RutokenNativeAdapter {
  _FakeRutokenNativeAdapter({this.hasAccount = true});

  final bool hasAccount;
  int openCount = 0;
  int closeCount = 0;

  static const account = WalletAccountDescriptor(
    backendId: 'rutoken_nfc',
    address: _address,
    derivationPath: "m/44'/60'/0'/0/0",
  );

  @override
  Future<RutokenNativeSession> openSession({required String pin}) async {
    if (pin != '1234') {
      throw StateError('PIN rejected');
    }
    openCount++;
    return RutokenNativeSession(
      id: 'session-$openCount',
      openedAtUtc: DateTime.utc(2026, 7, 22),
    );
  }

  @override
  Future<void> closeSession(RutokenNativeSession session) async {
    closeCount++;
  }

  @override
  Future<WalletAccountDescriptor?> readAccountDescriptor(
    RutokenNativeSession session,
  ) async => hasAccount ? account : null;

  @override
  Future<WalletAccountPublicKey> readAccountPublicKey(
    RutokenNativeSession session,
  ) async {
    final public = EthPrivateKey.fromHex(_privateKeyHex).publicKey;
    return WalletAccountPublicKey(
      account: account,
      accountPath: "m/44'/60'/0'",
      accountDepth: 3,
      compressedPublicKey: Uint8List.fromList(public.getEncoded(true)),
      chainCode: Uint8List(32),
      sourceFingerprint: 0,
      parentFingerprint: 0,
    );
  }

  @override
  Future<RutokenProvisioningResult> generateWallet({
    required RutokenNativeSession session,
    int mnemonicWordCount = 24,
    String? passphrase,
  }) async => const RutokenProvisioningResult(account: account);

  @override
  Future<WalletAccountDescriptor> importWallet({
    required RutokenNativeSession session,
    required Uint8List masterPrivateKey,
    required Uint8List chainCode,
  }) async => account;

  @override
  Future<RawEcdsaSignature> signDigest({
    required RutokenNativeSession session,
    required String derivationPath,
    required Uint8List digest,
  }) async {
    final signature = sign(
      digest,
      EthPrivateKey.fromHex(_privateKeyHex).privateKey,
    );
    return RawEcdsaSignature(
      r: _uint256(signature.r),
      s: _uint256(signature.s),
    );
  }
}

Uint8List _uint256(BigInt value) {
  final out = Uint8List(32);
  var remaining = value;
  for (var i = 31; i >= 0; i--) {
    out[i] = (remaining & BigInt.from(0xff)).toInt();
    remaining >>= 8;
  }
  return out;
}
