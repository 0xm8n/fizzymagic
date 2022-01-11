require('@nomiclabs/hardhat-waffle');
require('@nomiclabs/hardhat-etherscan');
require('@nomiclabs/hardhat-solhint');
require('@nomiclabs/hardhat-ethers');
require('@nomiclabs/hardhat-waffle');
require('solidity-coverage');

// import { HardhatUserConfig } from "hardhat/config";
const accounts = {
  mnemonic: process.env.MNEMONIC || "test test test test test test test test test test test junk",
};

module.exports = {
  solidity: {
    version: "0.8.6",
    settings: {
      evmVersion: "constantinople",
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  defaultNetwork: "hardhat",
  abiExporter: {
    path: "./abi",
    clear: false,
    flat: true,
  },
  paths: {
    artifacts: "artifacts",
    cache: "cache",
    deploy: "deploy",
    deployments: "deployments",
    imports: "imports",
    sources: process.env.CONTRACTS_PATH || "contracts",
    tests: "test",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_TOKEN,
  },
  gasReporter: {
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    currency: "USD",
    enabled: process.env.REPORT_GAS === "true",
  },
  networks: {
    bsc: {
      url: "https://bsc-dataseed.binance.org",
      accounts,
      chainId: 56,
      live: true,
      saveDeployments: true,
    },
    bsc_testnet: {
      url: "https://data-seed-prebsc-2-s3.binance.org:8545",
      accounts,
      chainId: 97,
      live: true,
      saveDeployments: true,
      tags: ["staging"],
    }
  },
  mocha: {
    timeout: 40000,
    bail: true,
  }
};
