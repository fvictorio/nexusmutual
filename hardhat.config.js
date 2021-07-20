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
  },

  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      blockGasLimit: 12e6,
      gas: 12e6,
    },
  },

  solidity: '0.8.4',

};
