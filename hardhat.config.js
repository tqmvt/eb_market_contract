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
      accounts: process.env.SIGNER !== undefined ? [process.env.SIGNER] : [],
      membership: '0x8d9232Ebc4f06B7b8005CCff0ca401675ceb25F5',
      market : '0x7a3CdB2364f92369a602CAE81167d0679087e6a3',
      staker : '0x7a3CdB2364f92369a602CAE81167d0679087e6a3'
    },
    cronos_testnet : {
      url : "https://cronos-testnet-3.crypto.org:8545",
      chainId : 338,
      accounts:  process.env.SIGNER !== undefined ? [process.env.SIGNER] : [],
      membership: '0x3F1590A5984C89e6d5831bFB76788F3517Cdf034',
      market : '0x15876C450638158F48392F01dE2CEa51eccc7840',
      staker : '0x15876C450638158F48392F01dE2CEa51eccc7840'
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
