// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract StakingPool is ERC20 {

  // RPT = reward per token

  struct Bucket {
    uint unstakeAmount;
    uint unrewardAmount;
    uint rptCumulativeSnapshot;
  }

  struct Staker {
    uint earned;
    uint rptCumulativePaid;
  }

  mapping(uint => Bucket) public buckets;
  mapping(address => Staker) public stakers;

  uint public stakedAmount;
  uint public unstakedAmount;
  uint public rewardPerBucket;
  uint public rptCumulative;
  uint public rptUpdateTime;
  uint public lastCrossedBucket;

  ERC20 public immutable lpToken;
  uint public immutable REWARDS_PRECISION;
  uint public constant BUCKET_SIZE = 7 days;

  constructor (
    address _lpToken,
    string memory name_,
    string memory symbol_
  ) ERC20(name_, symbol_) {

    lpToken = ERC20(_lpToken);
    REWARDS_PRECISION = 10 ** ERC20(_lpToken).decimals();

    rptUpdateTime = block.timestamp;
    lastCrossedBucket = bucketIndex(block.timestamp);
    console.log("current bucket: %s", lastCrossedBucket);
  }

  function bucketIndex(uint timestamp) public pure returns (uint) {
    return timestamp / BUCKET_SIZE;
  }

  function crossBuckets() internal returns (uint targetBucket) {

    uint currentBucket = lastCrossedBucket;
    targetBucket = bucketIndex(block.timestamp);

    while (currentBucket != targetBucket) {

      ++currentBucket;

      // calc rates since last update
      uint bucketCrossTime = currentBucket * BUCKET_SIZE;
      uint elapsed = bucketCrossTime - rptUpdateTime;
      uint rptPerSecond = REWARDS_PRECISION * rewardPerBucket / BUCKET_SIZE / totalSupply();
      uint rptSinceLastUpdate = rptPerSecond * elapsed;

      // update storage and store snapshot
      uint newRptCumulative = rptCumulative + rptSinceLastUpdate;
      buckets[currentBucket].rptCumulativeSnapshot = newRptCumulative;
      rptCumulative = newRptCumulative;
      rptUpdateTime = bucketCrossTime;

      // calc unstaked amount and burn unstaked shares
      uint burnAmount = buckets[currentBucket].unstakeAmount;
      rewardPerBucket = rewardPerBucket - buckets[currentBucket].unrewardAmount;
      _burn(address(this), burnAmount);
    }
  }

  function buyCover(uint amount, uint period) external {

    uint numBuckets = period / BUCKET_SIZE + 1;

  }

  function deposit(uint amount) external {

    uint balance = lpToken.balanceOf(address(this));
    uint shares = balanceOf(msg.sender);
    uint supply = totalSupply();

    uint elapsed = block.timestamp - rptUpdateTime;
    uint currentRptPerSecond = rewardPerBucket / BUCKET_SIZE / supply;
    uint rptSinceLastUpdate = currentRptPerSecond * elapsed;
    uint currentRptCumulative = rptCumulative + rptSinceLastUpdate;

    rptCumulative = currentRptCumulative;
    rptUpdateTime = block.timestamp;

    lpToken.transferFrom(msg.sender, address(this), amount);

    Staker storage staker = stakers[msg.sender];
    uint stakerLastRptCumulative = staker.rptCumulativePaid;
    uint stakerEarned = staker.earned;

    if (stakerLastRptCumulative != 0) {
      uint rptDiff = currentRptCumulative - stakerLastRptCumulative;
      uint newEarnings = rptDiff * shares;
      staker.earned = stakerEarned + newEarnings;
      staker.rptCumulativePaid = currentRptCumulative;
    }

    uint newShares = supply == 0 ? amount : (amount / balance * supply);
    _mint(msg.sender, newShares);
  }

}
