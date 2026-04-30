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
          'https://ethereum-rpc.publicnode.com',
          'https://eth.llamarpc.com',
          'https://1rpc.io/eth',
          'https://gateway.tenderly.co/public/mainnet',
        ],
        explorerApiBaseUrl: 'https://eth.blockscout.com/api/v2',
      ),
      EvmNetwork.ethereumSepolia: EvmNetworkConfig(
        network: EvmNetwork.ethereumSepolia,
        chainId: 11155111,
        name: 'Ethereum Sepolia',
        nativeSymbol: 'SepoliaETH',
        rpcUrls: <String>[
          'https://ethereum-sepolia-rpc.publicnode.com',
          'https://sepolia.gateway.tenderly.co',
          'https://sepolia.drpc.org',
          'https://1rpc.io/sepolia',
        ],
        explorerApiBaseUrl: 'https://eth-sepolia.blockscout.com/api/v2',
      ),
    };
