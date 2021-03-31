require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-truffle5");
require("hardhat-gas-reporter");

const keys = require('./dev-keys.json');

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      forking: {
        url: "https://eth-mainnet.alchemyapi.io/v2/" + keys.alchemyKeyMainnet,
        blockNumber: 12109225, // <-- edit here
      }
    }
  },
  etherscan: {
    apiKey: keys.etherscanAPI
  },
  solidity: {
    compilers: [
      {version: "0.7.6",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }},
    ]
  },
  mocha: {
    timeout: 2000000
  },
  gasReporter: {
    enabled: (process.env.REPORT_GAS) ? true : false,
    currency: 'USD'
  }
};
