// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StakingPool is ERC20 {

  struct PoolBucket {
    uint96 unstakeRequested;
    uint96 unstaked;
    uint64 rewardPerSecondCut;
  }

  struct ProductBucket {
    uint96 capacityExpiring;
  }

  struct Product {
    uint16 weight;
    uint96 usedCapacity;
    uint16 lastBucket;
    mapping(uint => ProductBucket) buckets;
  }

  struct Staker {

  }

  /* slot 0 */
  // bucket index => pool bucket
  mapping(uint => PoolBucket) public poolBuckets;

  /* slot 1 */
  // note: will likely have to pack this
  // product id => product info
  mapping(uint => Product) public products;

  /* slot 2 */
  // array with product ids to be able to iterate them
  uint[] public poolProductsIds;

  /* slot 3 */
  uint96 public currentStake;
  uint64 public currentRewardPerSecond;
  uint32 public lastRewardTime;
  uint16 public lastPoolBucket;
  uint16 public lastUnstakeBucket;
  uint16 public reservedStakeRatio;
  uint16 public _unused_01;

  /* slot 4 */
  uint96 public totalUnstakeRequested;

  /* immutables */
  ERC20 public immutable nxm;

  /* constants */
  uint public constant TOKEN_PRECISION = 1e18;
  uint public constant BUCKET_SIZE = 7 days;
  uint public constant RATIO_PRECISION = 10_000;

  constructor (
    address _nxm,
    string memory _name,
    string memory _symbol
  ) ERC20(_name, _symbol) {
    lastPoolBucket = uint16(block.timestamp / BUCKET_SIZE);
    lastUnstakeBucket = uint16(block.timestamp / BUCKET_SIZE);
    nxm = ERC20(_nxm);
  }

  /* View functions */

  function getAmountUnderManagement() internal view returns (uint) {

    // all vars are in the same slot, uses 1 SLOAD
    uint staked = currentStake;
    uint rewardPerSecond = currentRewardPerSecond;
    uint rewardTime = lastRewardTime;
    uint poolBucket = lastPoolBucket;

    // get bucket for current time
    uint currentBucket = block.timestamp / BUCKET_SIZE;

    while (poolBucket < currentBucket) {

      ++poolBucket;
      uint bucketStartTime = poolBucket * BUCKET_SIZE;
      staked += (bucketStartTime - rewardTime) * rewardPerSecond;

      rewardTime = bucketStartTime;
      rewardPerSecond -= poolBuckets[poolBucket].rewardPerSecondCut;
    }

    staked += (block.timestamp - rewardTime) * rewardPerSecond;
    return staked;
  }

  /* State-changing functions */

  function processPoolBuckets() internal returns (uint staked) {

    // same slot - a single SLOAD
    staked = currentStake;
    uint rewardPerSecond = currentRewardPerSecond;
    uint rewardTime = lastRewardTime;
    uint poolBucket = lastPoolBucket;

    // get bucket for current time
    uint currentBucket = block.timestamp / BUCKET_SIZE;

    while (poolBucket < currentBucket) {

      ++poolBucket;
      uint bucketStartTime = poolBucket * BUCKET_SIZE;
      staked += (bucketStartTime - rewardTime) * rewardPerSecond;

      rewardTime = bucketStartTime;
      rewardPerSecond -= poolBuckets[poolBucket].rewardPerSecondCut;
    }

    staked += (block.timestamp - rewardTime) * rewardPerSecond;

    // same slot - a single SSTORE
    currentStake = uint96(staked);
    currentRewardPerSecond = uint64(rewardPerSecond);
    lastRewardTime = uint32(rewardTime);
    lastPoolBucket = uint16(poolBucket);
  }

  /* callable by cover contract */

  function buyCover(
    uint productId,
    uint coveredAmount,
    uint rewardAmount,
    uint period,
    uint capacityFactor
  ) external {

    uint _currentStake = processPoolBuckets();
    uint currentBucket = block.timestamp / BUCKET_SIZE;

    Product storage product = products[productId];
    uint weight = product.weight;
    uint usedCapacity = product.usedCapacity;
    uint productBucket = product.lastBucket;

    // process expirations
    while (productBucket < currentBucket) {
      ++productBucket;
      usedCapacity -= product.buckets[productBucket].capacityExpiring;
    }

    uint _currentRewardPerSecond = currentRewardPerSecond;
    uint _reservedStakeRatio = reservedStakeRatio;

    {
      // capacity checks
      // TODO: decide how to calculate reserved capacity
      uint usableRatio = RATIO_PRECISION - _reservedStakeRatio;
      uint usableStake = _currentStake * usableRatio / RATIO_PRECISION * weight / RATIO_PRECISION;
      uint totalCapacity = usableStake * capacityFactor / RATIO_PRECISION;

      require(totalCapacity > usedCapacity, "StakingPool: No available capacity");
      require(totalCapacity - usedCapacity >= coveredAmount, "StakingPool: No available capacity");
    }

    {
      // calculate expiration bucket, reward period, reward amount
      uint expirationBucket = (block.timestamp + period * 1 days) / BUCKET_SIZE + 1;
      uint rewardPeriod = expirationBucket * BUCKET_SIZE - block.timestamp;
      uint addedRewardPerSecond = rewardAmount / rewardPeriod;

      // update state
      currentRewardPerSecond = uint64(_currentRewardPerSecond + addedRewardPerSecond);
      poolBuckets[expirationBucket].rewardPerSecondCut += uint64(addedRewardPerSecond);
      product.buckets[expirationBucket].capacityExpiring += uint96(coveredAmount);

      product.lastBucket = uint16(productBucket);
      product.usedCapacity = uint96(usedCapacity + coveredAmount);
    }
  }

  function burn() external {

    //

  }

  /* callable by stakers */

  function deposit(uint amount) external {

    uint staked = processPoolBuckets();
    uint supply = totalSupply();
    uint mintAmount = supply == 0 ? amount : (amount * supply / staked);

    // TODO: use operator transfer and transfer to TC
    nxm.transferFrom(msg.sender, address(this), amount);
    _mint(msg.sender, mintAmount);
  }

  function requestUnstake() external {

    //

  }

  function withdraw() external {

    //

  }

  /* callable by pool owner */

  function addProduct() external {

    //

  }

  function removeProduct() external {

    //

  }

  function setWeights() external {

    //

  }

}
