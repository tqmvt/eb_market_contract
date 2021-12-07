require("@nomiclabs/hardhat-ethers");
require('@openzeppelin/hardhat-upgrades');
require("@nomiclabs/hardhat-waffle");
require("solidity-coverage");
require("hardhat-gas-reporter");
require("@nomiclabs/hardhat-etherscan");
require('hardhat-abi-exporter');

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
// const key = process.env.SIGNER
module.exports = {
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  // defaultNetwork: "cronos_testnet",
  networks : {
    hardhat :{

    },
    cronos : {
      url : "https://evm-cronos.crypto.org",
      chainId: 25,
      acounts: process.env.SIGNER !== undefined ? [process.env.SIGNER] : [],
    },
    cronos_testnet : {
      url : "https://cronos-testnet-3.crypto.org:8545",
      chainId : 338,
      accounts:  process.env.SIGNER !== undefined ? [process.env.SIGNER] : [],
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 20000
  },
  // abiExporter: {
  //   path: './artifacts/abi',
  //   clear: true,
  //   flat: true,
  //   spacing: 2,
  //   pretty: true,
  // }
};
