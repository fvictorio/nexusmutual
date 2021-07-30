require('@nomiclabs/hardhat-ethers');
require('@typechain/hardhat');

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {

  mocha: {
    exit: true,
    bail: false,
    recursive: false,
    timeout: 60 * 60 * 60 * 24,
  },

  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      blockGasLimit: 12e6,
      gas: 12e6,
      accounts: {
        count: 21,
      },
    },

  },

  solidity: '0.8.4',

};
