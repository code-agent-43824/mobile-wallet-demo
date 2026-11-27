import 'package:ton_dart/ton_dart.dart';

enum TonNetwork {
  testnet(TonChainId.testnet, 'testnet.toncenter.com', 'testnet.tonapi.io'),
  mainnet(TonChainId.mainnet, 'toncenter.com', 'tonapi.io');

  const TonNetwork(this.chainId, this.tonCenterHost, this.tonApiHost);

  final TonChainId chainId;
  final String tonCenterHost;
  final String tonApiHost;

  bool get isTestnet => this == testnet;

  bool accepts(TonAddress address) =>
      !address.isFriendly || address.isTestOnly == isTestnet;

  String friendly(TonAddress address) =>
      address.toFriendly(testOnly: isTestnet).address;
}
