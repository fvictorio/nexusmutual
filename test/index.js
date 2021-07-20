const { ethers, run } = require('hardhat');

describe('StakingPool', function () {

  let pool, lpToken;

  before(async () => {

    await run('compile');

    const LpToken = await ethers.getContractFactory('ERC20');
    lpToken = await LpToken.deploy('NXM', 'NXM');
    await lpToken.deployed();

    const StakingPool = await ethers.getContractFactory('StakingPool');
    pool = await StakingPool.deploy(lpToken.address, 'SPT', 'StakingPool Token');
    await pool.deployed();
  });

  it('should compile', function () {
    //
  });

});
