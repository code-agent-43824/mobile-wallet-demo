import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/walletconnect/reown_wallet_connect_service.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_service.dart';
import 'package:reown_walletkit/reown_walletkit.dart';

void main() {
  test('filters unsupported optional chains and methods from approval', () {
    const address = '0x1111111111111111111111111111111111111111';
    final result = const WalletConnectNamespacePolicy().build(
      requiredNamespaces: const <String, RequiredNamespace>{
        'eip155': RequiredNamespace(
          chains: <String>['eip155:1'],
          methods: <String>['eth_sendTransaction'],
          events: <String>['accountsChanged'],
        ),
      },
      optionalNamespaces: const <String, RequiredNamespace>{
        'eip155': RequiredNamespace(
          chains: <String>['eip155:11155111', 'eip155:137'],
          methods: <String>['wallet_getCapabilities', 'wallet_sendCalls'],
          events: <String>['chainChanged'],
        ),
      },
      accounts: const <String>[
        'eip155:1:$address',
        'eip155:11155111:$address',
        'eip155:137:$address',
      ],
    );

    final namespace = result['eip155']!;
    expect(
      namespace.chains,
      containsAll(<String>['eip155:1', 'eip155:11155111']),
    );
    expect(namespace.chains, isNot(contains('eip155:137')));
    expect(
      namespace.methods,
      containsAll(<String>['eth_sendTransaction', 'wallet_getCapabilities']),
    );
    expect(namespace.methods, isNot(contains('wallet_sendCalls')));
    expect(namespace.accounts, hasLength(2));
    expect(namespace.accounts, isNot(contains('eip155:137:$address')));
  });

  test('rejects an unsupported required method instead of advertising it', () {
    expect(
      () => const WalletConnectNamespacePolicy().build(
        requiredNamespaces: const <String, RequiredNamespace>{
          'eip155': RequiredNamespace(
            chains: <String>['eip155:1'],
            methods: <String>['wallet_sendCalls'],
            events: <String>[],
          ),
        },
        optionalNamespaces: const <String, RequiredNamespace>{},
        accounts: const <String>[
          'eip155:1:0x1111111111111111111111111111111111111111',
        ],
      ),
      throwsA(
        isA<WalletConnectServiceException>().having(
          (error) => error.message,
          'message',
          contains('wallet_sendCalls'),
        ),
      ),
    );
  });
}
