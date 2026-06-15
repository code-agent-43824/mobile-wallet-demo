import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';
import 'package:mobile_wallet_demo/src/walletconnect/eip712.dart';

/// The canonical EIP-712 "Ether Mail" example from the EIP-712 spec. The
/// expected digest/signature below were generated with the reference
/// implementation (Python `eth-account`) for the private key keccak256("cow").
final Map<String, dynamic> _mail = <String, dynamic>{
  'types': <String, dynamic>{
    'EIP712Domain': <dynamic>[
      <String, String>{'name': 'name', 'type': 'string'},
      <String, String>{'name': 'version', 'type': 'string'},
      <String, String>{'name': 'chainId', 'type': 'uint256'},
      <String, String>{'name': 'verifyingContract', 'type': 'address'},
    ],
    'Person': <dynamic>[
      <String, String>{'name': 'name', 'type': 'string'},
      <String, String>{'name': 'wallet', 'type': 'address'},
    ],
    'Mail': <dynamic>[
      <String, String>{'name': 'from', 'type': 'Person'},
      <String, String>{'name': 'to', 'type': 'Person'},
      <String, String>{'name': 'contents', 'type': 'string'},
    ],
  },
  'primaryType': 'Mail',
  'domain': <String, dynamic>{
    'name': 'Ether Mail',
    'version': '1',
    'chainId': 1,
    'verifyingContract': '0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC',
  },
  'message': <String, dynamic>{
    'from': <String, dynamic>{
      'name': 'Cow',
      'wallet': '0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826',
    },
    'to': <String, dynamic>{
      'name': 'Bob',
      'wallet': '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB',
    },
    'contents': 'Hello, Bob!',
  },
};

const String _cowPrivateKey =
    'c85ef7d79691fe79573b1a7064c19c1a9819ebdbd1faaab1a8ec92344438aaf4';
const String _cowAddress = '0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826';

String _hex(List<int> bytes) =>
    '0x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

void main() {
  test('encodes the canonical EIP-712 Mail digest', () {
    final digest = const Eip712Encoder().encode(_mail);
    expect(
      _hex(digest),
      '0xbe609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2',
    );
  });

  test('signs the Mail digest to the canonical signature', () {
    final digest = const Eip712Encoder().encode(_mail);
    final signature = const LocalTransactionService().signDigest(
      walletMaterial: const WalletMaterial(
        address: _cowAddress,
        mnemonic: 'unused',
        privateKeyHex: _cowPrivateKey,
      ),
      digest: digest,
    );
    expect(
      signature,
      '0x4355c47d63924e8a72e509b65029052eb6c299d53a04e167c5775fd466751c9d'
      '07299936d304c153f6443dfa05f40ff007d72911b6f72307f996231605b915621c',
    );
  });

  test('rejects malformed typed data', () {
    expect(
      () => const Eip712Encoder().encode(<String, dynamic>{'primaryType': 'X'}),
      throwsA(isA<Eip712Exception>()),
    );
  });
}
