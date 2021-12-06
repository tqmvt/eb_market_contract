require("@nomiclabs/hardhat-ethers");
require('@openzeppelin/hardhat-upgrades');


/**
 * @type import('hardhat/config').HardhatUserConfig
 */
const key = process.env.SIGNER
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
  defaultNetwork: "cronos_testnet",
  networks : {
    hardhat :{

    },
    cronos : {
      url : "https://evm-cronos.crypto.org",
      chainId: 25,
      acounts: [key],
    },
    cronos_testnet : {
      url : "https://cronos-testnet-3.crypto.org:8545",
      chainId : 338,
      accounts: [key]
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
  }
};
