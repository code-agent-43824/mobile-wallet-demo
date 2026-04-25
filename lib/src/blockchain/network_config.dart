enum EvmNetwork { ethereumMainnet, ethereumSepolia }

class EvmNetworkConfig {
  const EvmNetworkConfig({
    required this.network,
    required this.chainId,
    required this.name,
    required this.nativeSymbol,
    required this.rpcUrls,
    required this.explorerApiBaseUrl,
  });

  final EvmNetwork network;
  final int chainId;
  final String name;
  final String nativeSymbol;
  final List<String> rpcUrls;
  final String explorerApiBaseUrl;
}

const Map<EvmNetwork, EvmNetworkConfig> evmNetworkConfigs =
    <EvmNetwork, EvmNetworkConfig>{
      EvmNetwork.ethereumMainnet: EvmNetworkConfig(
        network: EvmNetwork.ethereumMainnet,
        chainId: 1,
        name: 'Ethereum Mainnet',
        nativeSymbol: 'ETH',
        rpcUrls: <String>[
          'https://cloudflare-eth.com',
          'https://rpc.ankr.com/eth',
        ],
        explorerApiBaseUrl: 'https://eth.blockscout.com/api/v2',
      ),
      EvmNetwork.ethereumSepolia: EvmNetworkConfig(
        network: EvmNetwork.ethereumSepolia,
        chainId: 11155111,
        name: 'Ethereum Sepolia',
        nativeSymbol: 'SepoliaETH',
        rpcUrls: <String>[
          'https://rpc.sepolia.org',
          'https://ethereum-sepolia-rpc.publicnode.com',
        ],
        explorerApiBaseUrl: 'https://eth-sepolia.blockscout.com/api/v2',
      ),
    };
