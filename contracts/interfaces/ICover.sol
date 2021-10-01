// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.0;

interface ICover {

  /* ========== DATA STRUCTURES ========== */

  enum RedeemMethod {
    Claim,
    Incident
  }

  struct StakingPool {
    address poolAddress;
    uint96 coverAmount;
  }

  struct Cover {
    uint24 productId;
    uint8 payoutAsset;
    uint96 amount;
    uint32 start;
    uint32 period;  // seconds
    uint96 price;
  }

  struct Product {
    uint16 productType;
    address productAddress;
    /* supported payout assets bitmap TODO: explain */
    uint payoutAssets;
  }

  struct ProductType {
    string descriptionIpfsHash;
    uint8 redeemMethod;
    uint16 gracePeriodInDays;
    uint16 burnRatio;
  }

  /* ========== VIEWS ========== */

  function covers(uint id) external view returns (uint24, uint8, uint96, uint32, uint32, uint96);

  function products(uint id) external view returns (uint16, address, uint);

  function productTypes(uint id) external view returns (string memory, uint8, uint16, uint16);

  function activeCoverAmountInNXM(uint id) external view returns (uint96);

  /* === MUTATIVE FUNCTIONS ==== */

  function buyCover(
    address owner,
    uint24 productId,
    uint8 payoutAsset,
    uint96 amount,
    uint32 period,
    uint maxPrice,
    StakingPool[] calldata stakingPools
  ) external payable returns (uint /*coverId*/);

  function performPayoutBurn(uint coverId, uint amount) external returns (address /*owner*/);

  /* ========== EVENTS ========== */

}
