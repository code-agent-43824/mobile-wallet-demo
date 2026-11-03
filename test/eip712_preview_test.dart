import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/walletconnect/eip712_preview.dart';

const _owner = '0x1111111111111111111111111111111111111111';
const _spender = '0x2222222222222222222222222222222222222222';
const _token = '0x3333333333333333333333333333333333333333';
const _uint256Max =
    '115792089237316195423570985008687907853269984665640564039457584007913129639935';

Map<String, dynamic> _domainType(List<String> names) => <String, dynamic>{
  'EIP712Domain': <Map<String, String>>[
    for (final name in names)
      <String, String>{
        'name': name,
        'type': switch (name) {
          'chainId' => 'uint256',
          'verifyingContract' => 'address',
          _ => 'string',
        },
      },
  ],
};

void main() {
  test('an EIP-2612 permit of the largest amount reads as unlimited', () {
    final preview = Eip712Preview.parse(<String, dynamic>{
      'types': <String, dynamic>{
        ..._domainType(<String>[
          'name',
          'version',
          'chainId',
          'verifyingContract',
        ]),
        'Permit': <Map<String, String>>[
          <String, String>{'name': 'owner', 'type': 'address'},
          <String, String>{'name': 'spender', 'type': 'address'},
          <String, String>{'name': 'value', 'type': 'uint256'},
          <String, String>{'name': 'nonce', 'type': 'uint256'},
          <String, String>{'name': 'deadline', 'type': 'uint256'},
        ],
      },
      'primaryType': 'Permit',
      'domain': <String, dynamic>{
        'name': 'USD Coin',
        'version': '2',
        'chainId': 11155111,
        'verifyingContract': _token,
      },
      'message': <String, dynamic>{
        'owner': _owner,
        'spender': _spender,
        'value': _uint256Max,
        'nonce': 0,
        'deadline': '1767225600',
      },
    });

    expect(preview.primaryType, 'Permit');
    expect(preview.appName, 'USD Coin');
    expect(preview.appVersion, '2');
    expect(preview.chainId, 11155111);
    expect(preview.grantsSpending, isTrue);
    expect(preview.spender, _spender);
    // EIP-2612: the token is the domain's own contract.
    expect(preview.allowances.single.token, _token);
    expect(preview.allowances.single.unlimited, isTrue);
    expect(preview.deadlines.single.path, 'deadline');
    expect(
      preview.fields.map((field) => '${field.path}=${field.value}'),
      <String>[
        'owner=$_owner',
        'spender=$_spender',
        'value=$_uint256Max',
        'nonce=0',
        'deadline=1767225600 (2026-01-01 00:00 UTC)',
      ],
    );
    expect(preview.isForChain(11155111), isTrue);
    expect(preview.isForChain(1), isFalse);
  });

  test('a Permit2 batch names each token; uint160 max is unlimited', () {
    final uint160Max = ((BigInt.one << 160) - BigInt.one).toString();
    final preview = Eip712Preview.parse(<String, dynamic>{
      'types': <String, dynamic>{
        ..._domainType(<String>['name', 'chainId', 'verifyingContract']),
        'PermitBatch': <Map<String, String>>[
          <String, String>{'name': 'details', 'type': 'PermitDetails[]'},
          <String, String>{'name': 'spender', 'type': 'address'},
          <String, String>{'name': 'sigDeadline', 'type': 'uint256'},
        ],
        'PermitDetails': <Map<String, String>>[
          <String, String>{'name': 'token', 'type': 'address'},
          <String, String>{'name': 'amount', 'type': 'uint160'},
          <String, String>{'name': 'expiration', 'type': 'uint48'},
          <String, String>{'name': 'nonce', 'type': 'uint48'},
        ],
      },
      'primaryType': 'PermitBatch',
      'domain': <String, dynamic>{
        'name': 'Permit2',
        'chainId': '0x1',
        'verifyingContract': '0x000000000022d473030f116ddee9f6b43ac78ba3',
      },
      'message': <String, dynamic>{
        'details': <Map<String, dynamic>>[
          <String, dynamic>{
            'token': _token,
            'amount': uint160Max,
            'expiration': 1767225600,
            'nonce': 0,
          },
          <String, dynamic>{
            'token': _owner,
            'amount': '0x64',
            'expiration': 1767225600,
            'nonce': 1,
          },
        ],
        'spender': _spender,
        'sigDeadline': 1767225600,
      },
    });

    expect(preview.chainId, 1);
    expect(preview.spender, _spender);
    expect(preview.allowances.map((allowance) => allowance.token), <String>[
      _token,
      _owner,
    ]);
    expect(preview.allowances.first.unlimited, isTrue);
    expect(preview.allowances.last.amount, BigInt.from(100));
    expect(preview.allowances.last.unlimited, isFalse);
    expect(preview.deadlines.map((deadline) => deadline.path), <String>[
      'details[0].expiration',
      'details[1].expiration',
      'sigDeadline',
    ]);
  });

  test('a DAI-style permit grants everything with allowed = true', () {
    final preview = Eip712Preview.parse(<String, dynamic>{
      'types': <String, dynamic>{
        ..._domainType(<String>['name', 'verifyingContract']),
        'Permit': <Map<String, String>>[
          <String, String>{'name': 'holder', 'type': 'address'},
          <String, String>{'name': 'spender', 'type': 'address'},
          <String, String>{'name': 'nonce', 'type': 'uint256'},
          <String, String>{'name': 'expiry', 'type': 'uint256'},
          <String, String>{'name': 'allowed', 'type': 'bool'},
        ],
      },
      'primaryType': 'Permit',
      'domain': <String, dynamic>{'name': 'Dai', 'verifyingContract': _token},
      'message': <String, dynamic>{
        'holder': _owner,
        'spender': _spender,
        'nonce': 0,
        'expiry': 0,
        'allowed': true,
      },
    });

    expect(preview.chainId, isNull);
    expect(preview.isForChain(1), isTrue);
    expect(preview.allowances.single.unlimited, isTrue);
    expect(preview.allowances.single.amount, isNull);
  });

  test('a message without a spender grants nothing and shows every field', () {
    final preview = Eip712Preview.parse(<String, dynamic>{
      'types': <String, dynamic>{
        ..._domainType(<String>['name']),
        'Mail': <Map<String, String>>[
          <String, String>{'name': 'from', 'type': 'Person'},
          <String, String>{'name': 'contents', 'type': 'string'},
          <String, String>{'name': 'amount', 'type': 'uint256'},
        ],
        'Person': <Map<String, String>>[
          <String, String>{'name': 'name', 'type': 'string'},
          <String, String>{'name': 'wallet', 'type': 'address'},
        ],
      },
      'primaryType': 'Mail',
      'domain': <String, dynamic>{'name': 'Ether Mail'},
      'message': <String, dynamic>{
        'from': <String, dynamic>{'name': 'Cow', 'wallet': _owner},
        // A right-to-left override would reverse what follows it on screen.
        'contents': 'Hello \u202Ebob',
        'amount': 5,
      },
    });

    expect(preview.grantsSpending, isFalse);
    expect(preview.allowances, isEmpty);
    expect(
      preview.fields.map((field) => '${field.path}=${field.value}'),
      <String>[
        'from.name=Cow',
        'from.wallet=$_owner',
        'contents=Hello \\u{202E}bob',
        'amount=5',
      ],
    );
  });

  test('anything but a typed-data object is refused', () {
    expect(
      () =>
          Eip712Preview.parse(<String, dynamic>{'types': <String, dynamic>{}}),
      throwsFormatException,
    );
    expect(
      () => Eip712Preview.parse(<String, dynamic>{
        'types': _domainType(<String>['name']),
        'primaryType': 'Missing',
        'domain': <String, dynamic>{},
        'message': <String, dynamic>{},
      }),
      throwsFormatException,
    );
  });

  test('a deadline past year 9999 reads as no date', () {
    expect(
      Eip712Preview.formatUnixSeconds(BigInt.from(0)),
      '1970-01-01 00:00 UTC',
    );
    expect(
      Eip712Preview.formatUnixSeconds((BigInt.one << 48) - BigInt.one),
      isNull,
    );
  });
}
