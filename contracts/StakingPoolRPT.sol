// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract StakingPoolRPT is ERC20 {

  // RPT = reward per token

  struct Bucket {
    uint rewardReduction;
    uint rptCumulativeSnapshot;
    uint balanceToUnstake;
    uint nxmUnstaked;
    uint capacityIncrease;
  }

  struct Staker {
    uint earned;
    uint rptCumulativePaid;
  }

  mapping(uint => Bucket) public buckets;
  mapping(address => Staker) public stakers;

  // total nxm reward amount to be distributed (without already distributed amount)
  uint public pendingRewards;

  // reward to be distributed in the current bucket
  uint public currentReward;

  // currently active cover amount
  uint public capacityUsed;

  // currently active or in grace period
  uint public capacityReserved;

  // currently unstaked nxm
  uint public unstakedAmount;

  uint public rptCumulative;
  uint public rptLastUpdateTime;
  uint public lastCrossedBucket;

  ERC20 public immutable nxm;
  uint public immutable REWARDS_PRECISION;
  uint public constant BUCKET_SIZE = 7 days;

  constructor (
    address _nxm,
    string memory _name,
    string memory _symbol
  ) ERC20(_name, _symbol) {

    nxm = ERC20(_nxm);
    REWARDS_PRECISION = 10 ** ERC20(_nxm).decimals();

    rptLastUpdateTime = block.timestamp;
    lastCrossedBucket = _bucketIndex(block.timestamp);
  }

  function bucketIndex(uint timestamp) external pure returns (uint) {
    return _bucketIndex(timestamp);
  }

  function _bucketIndex(uint timestamp) internal pure returns (uint) {
    return timestamp / BUCKET_SIZE;
  }

  function updateRewards() internal {

    uint currentBucket = lastCrossedBucket;
    uint targetBucket = _bucketIndex(block.timestamp);

    // cheaper to have them on stack
    uint _rptCumulative = rptCumulative;
    uint _rptLastUpdateTime = rptLastUpdateTime;
    uint _currentBucketReward = currentReward;
    uint _pendingRewards = pendingRewards;
    uint _unstakedAmount = unstakedAmount;

    while (currentBucket != targetBucket) {

      ++currentBucket;

      // calc rates since last update
      uint bucketCrossTime = currentBucket * BUCKET_SIZE;
      uint supply = totalSupply();

      // TODO: rewards streamed while there are no stakers may get stuck forever, unsure if this can happen though

      if (supply == 0) {

        _currentBucketReward -= buckets[currentBucket].rewardReduction;
        _rptLastUpdateTime = bucketCrossTime;

        if (_rptCumulative != 0) {
          buckets[currentBucket].rptCumulativeSnapshot = _rptCumulative;
        }

        continue;
      }

      {
        // rewards since last update
        uint rptPerSecond = REWARDS_PRECISION * _currentBucketReward / supply / BUCKET_SIZE;
        uint elapsed = bucketCrossTime - _rptLastUpdateTime;
        uint rptSinceLastUpdate = rptPerSecond * elapsed;

        _rptLastUpdateTime = bucketCrossTime;
        _rptCumulative += rptSinceLastUpdate;
        buckets[currentBucket].rptCumulativeSnapshot = _rptCumulative;
      }

      uint balanceToUnstake = buckets[currentBucket].balanceToUnstake;

      if (balanceToUnstake != 0) {

        // calc unstaked amount and burn unstaked balance
        uint nxmBalance = nxm.balanceOf(address(this));
        uint stakedNXM = nxmBalance - _pendingRewards - _unstakedAmount;
        uint nxmToUnstake = balanceToUnstake * stakedNXM / supply;

        _burn(address(this), balanceToUnstake);
        _unstakedAmount += nxmToUnstake;
        buckets[currentBucket].nxmUnstaked = nxmToUnstake;
      }

      _currentBucketReward -= buckets[currentBucket].rewardReduction;
    }

    uint supply = totalSupply();

    // calc rewards since bucket cross time till now
    if (supply != 0) {
      uint rptPerSecond = REWARDS_PRECISION * _currentBucketReward / supply / BUCKET_SIZE;
      uint elapsed = block.timestamp - _rptLastUpdateTime;
      uint rptSinceLastUpdate = rptPerSecond * elapsed;
      _rptLastUpdateTime = block.timestamp;
      _rptCumulative += rptSinceLastUpdate;
    }

    lastCrossedBucket = currentBucket;
    rptCumulative = _rptCumulative;
    rptLastUpdateTime = _rptLastUpdateTime;
    currentReward = _currentBucketReward;
    unstakedAmount = _unstakedAmount;
    pendingRewards = _pendingRewards;
  }

  error MinPeriodNotMet(uint requestedPeriod);

  function buyCover(uint coveredAmount, uint premium, uint period) external {

    updateRewards();

    require(period >= 30 days);

    // TODO: current bucket rewards must be partial
    uint currentBucket = _bucketIndex(block.timestamp);
    uint numBuckets = period / BUCKET_SIZE + 1;
    uint amountPerBucket = premium / numBuckets;

    nxm.transferFrom(msg.sender, address(this), premium);

    pendingRewards += premium;
    currentReward += amountPerBucket;
    buckets[currentBucket + numBuckets].rewardReduction = amountPerBucket;
  }

  function deposit(uint amount) external {

    updateRewards();

    uint nxmBalance = nxm.balanceOf(address(this));
    uint stakedNXM = nxmBalance - pendingRewards - unstakedAmount;
    nxm.transferFrom(msg.sender, address(this), amount);

    Staker storage staker = stakers[msg.sender];
    uint balance = balanceOf(msg.sender);
    uint _rptCumulative = rptCumulative;

    if (balance != 0) {
      uint rptUnpaid = _rptCumulative - staker.rptCumulativePaid;
      uint newEarnings = rptUnpaid * balance;
      staker.earned += newEarnings;
    }

    // snapshot rptCumulative at deposit time
    staker.rptCumulativePaid = _rptCumulative;

    uint supply = totalSupply();
    uint mintAmount = supply == 0 ? amount : (amount / stakedNXM * supply);
    _mint(msg.sender, mintAmount);
  }

}
