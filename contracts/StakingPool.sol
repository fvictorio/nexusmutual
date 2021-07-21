// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract StakingPool is ERC20 {

  // RPT = reward per token

  struct Bucket {
    uint rewardsToReduce;
    uint rptCumulativeSnapshot;
    uint sharesToUnstake;
    uint nxmUnstaked;
  }

  struct Staker {
    uint earned;
    uint rptCumulativePaid;
  }

  mapping(uint => Bucket) public buckets;
  mapping(address => Staker) public stakers;

  // total nxm reward amount to be distributed (without already distributed amount)
  uint public rewardAmount;

  // reward to be distributed in the current bucket
  uint public currentBucketReward;

  // currently unstaked nxm
  uint public unstakedAmount;

  uint public rptCumulative;
  uint public rptUpdateTime;
  uint public lastCrossedBucket;

  ERC20 public immutable nxm;
  uint public immutable REWARDS_PRECISION;
  uint public constant BUCKET_SIZE = 7 days;

  constructor (
    address _nxm,
    string memory name_,
    string memory symbol_
  ) ERC20(name_, symbol_) {

    nxm = ERC20(_nxm);
    REWARDS_PRECISION = 10 ** ERC20(_nxm).decimals();

    rptUpdateTime = block.timestamp;
    lastCrossedBucket = bucketIndex(block.timestamp);
    console.log("current bucket: %s", lastCrossedBucket);
  }

  function bucketIndex(uint timestamp) public pure returns (uint) {
    return timestamp / BUCKET_SIZE;
  }

  function crossBuckets() internal returns (uint currentBucket) {

    currentBucket = lastCrossedBucket;
    uint targetBucket = bucketIndex(block.timestamp);

    while (currentBucket != targetBucket) {

      ++currentBucket;

      // calc rates since last update
      uint bucketCrossTime = currentBucket * BUCKET_SIZE;
      uint elapsed = bucketCrossTime - rptUpdateTime;
      // TODO: treat division by zero case
      uint rptPerSecond = REWARDS_PRECISION * currentBucketReward / BUCKET_SIZE / totalSupply();
      uint rptSinceLastUpdate = rptPerSecond * elapsed;

      // update storage and store snapshot
      uint newRptCumulative = rptCumulative + rptSinceLastUpdate;
      buckets[currentBucket].rptCumulativeSnapshot = newRptCumulative;
      rptCumulative = newRptCumulative;
      rptUpdateTime = bucketCrossTime;

      // calc unstaked amount and burn unstaked shares
      uint sharesToUnstake = buckets[currentBucket].sharesToUnstake;
      uint nxmBalance = nxm.balanceOf(address(this));
      uint stakedNXM = nxmBalance - rewardAmount - unstakedAmount;
      // TODO: treat division by zero case
      uint nxmToUnstake = stakedNXM * sharesToUnstake / totalSupply();

      buckets[currentBucket].nxmUnstaked = nxmToUnstake;
      unstakedAmount = unstakedAmount + nxmToUnstake;

      currentBucketReward = currentBucketReward - buckets[currentBucket].rewardsToReduce;
      _burn(address(this), sharesToUnstake);
    }
  }

  function buyCover(uint amount, uint period) external {

    crossBuckets();

    uint numBuckets = period / BUCKET_SIZE + 1;

  }

  function deposit(uint amount) external {

    crossBuckets();

    uint nxmBalance = nxm.balanceOf(address(this));
    uint shares = balanceOf(msg.sender);
    uint supply = totalSupply();

    uint currentRptCumulative = rptCumulative;

    if (supply != 0) {
      uint currentRptPerSecond = currentBucketReward / BUCKET_SIZE / supply;
      uint elapsed = block.timestamp - rptUpdateTime;
      uint rptSinceLastUpdate = currentRptPerSecond * elapsed;
      currentRptCumulative = currentRptCumulative + rptSinceLastUpdate;
    }

    rptCumulative = currentRptCumulative;
    rptUpdateTime = block.timestamp;

    nxm.transferFrom(msg.sender, address(this), amount);

    Staker storage staker = stakers[msg.sender];
    uint stakerLastRptCumulative = staker.rptCumulativePaid;
    uint stakerEarned = staker.earned;

    if (stakerLastRptCumulative != 0) {
      uint rptDiff = currentRptCumulative - stakerLastRptCumulative;
      uint newEarnings = rptDiff * shares;
      staker.earned = stakerEarned + newEarnings;
      staker.rptCumulativePaid = currentRptCumulative;
    }

    uint newShares = supply == 0 ? amount : (amount / nxmBalance * supply);
    _mint(msg.sender, newShares);
  }

}
