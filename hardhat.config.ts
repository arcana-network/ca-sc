require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
require('@nomicfoundation/hardhat-verify')

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.28",
    settings: {
      evmVersion: 'cancun',
      optimizer: {
        enabled: true,
        runs: 100_000,
      },
    },
  },
  networks: {
    ethereum: {
      url: 'https://ethereum-rpc.publicnode.com',
      accounts: [process.env.PRIVATE_KEY]
    },
    polygon_mainnet: {
      url: 'https://polygon-mainnet.g.alchemy.com/v2/PfaswrKq0rjOrfYWHfE9uLQKhiD4JCdq',
      accounts: [process.env.PRIVATE_KEY]
    },
    arb_sepolia: {
      url: 'https://arbitrum-sepolia-rpc.publicnode.com',
      accounts: [process.env.PRIVATE_KEY]
    },
    op_sepolia: {
      url: 'https://optimism-sepolia.api.onfinality.io/public',
      accounts: [process.env.PRIVATE_KEY]
    },
    monad_testnet: {
      url: 'https://testnet-rpc.monad.xyz',
      accounts: [process.env.PRIVATE_KEY]
    },
    holešky: {
      url: 'https://ethereum-holesky-rpc.publicnode.com',
      accounts: [process.env.PRIVATE_KEY]
    },
    arbitrum_one: {
      url: 'https://arbitrum-one-rpc.publicnode.com',
      accounts: [process.env.PRIVATE_KEY]
    },
    optimism_mainnet: {
      url: 'https://optimism-rpc.publicnode.com',
      accounts: [process.env.PRIVATE_KEY]
    },
    base_mainnet: {
      url: 'https://base-rpc.publicnode.com',
      accounts: [process.env.PRIVATE_KEY]
    },
    scroll_mainnet: {
      url: 'https://scroll-rpc.publicnode.com',
      accounts: [process.env.PRIVATE_KEY]
    },
    linea_mainnet: {
      url: 'https://linea-rpc.publicnode.com',
      accounts: [process.env.PRIVATE_KEY]
    },
    sophon_mainnet: {
      url: 'https://rpc.sophon.xyz',
      accounts: [process.env.PRIVATE_KEY]
    },
    avalanche_c_chain: {
      url: 'https://avalanche-c-chain-rpc.publicnode.com',
      accounts: [process.env.PRIVATE_KEY]
    }
  },
  etherscan: {
    apiKey: {
      polygon_mainnet: process.env.POLYGONSCAN_API_KEY,
      arbitrum_one: process.env.ARBISCAN_API_KEY,
      optimism_mainnet: process.env.OPTIMISTIC_ETHERSCAN_API_KEY,
    },
    customChains: [
      {
        network: 'polygon_mainnet',
        chainId: 137,
        urls: {
          apiURL: "https://api.polygonscan.com/api",
          browserURL: "https://polygonscan.com"
        }
      },
      {
        network: "optimism_mainnet",
        chainId: 10,
        urls: {
          apiURL: "https://api-optimistic.etherscan.io/api",
          browserURL: "https://optimistic.etherscan.io"
        }
      },
      {
        network: "arbitrum_one",
        chainId: 42161,
        urls: {
          apiURL: "https://api.arbiscan.io/api",
          browserURL: "https://arbiscan.io"
        }
      }
    ]
  },
  sourcify: {
    enabled: false
  }
};
