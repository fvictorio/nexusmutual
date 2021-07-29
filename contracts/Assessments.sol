// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract Assessments {

  /* ========== DATA STRUCTURES ========== */

  enum PollStatus { PENDING, ACCEPTED, DENIED }

  enum EventType { CLAIM, INCIDENT }

  enum Asset { ETH, DAI }

  enum UintParams {
    REWARD_PERC,
    FLAT_ETH_FEE_PERC,
    INCIDENT_TOKEN_WEIGHT_PERC,
    VOTING_PERIOD_DAYS_MIN,
    VOTING_PERIOD_DAYS_MAX,
    PAYOUT_COOLDOWN_DAYS
  }

  struct Deposit {
    uint104 amount;
    uint104 voteRewardCursor;
  }

  struct Vote {
    bool verdict; // true for accepted and false for denied
    uint104 eventId; // can be either a claimId or an IncidentId
    uint32 timestamp; // date and time when the vote was cast
    uint104 tokenWeight; // how many tokens were staked when the vote was cast
    EventType eventType; //
  }

  struct Poll {
    uint112 accepted;
    uint112 denied;
    uint32 voteStart;
  }

  struct ClaimDetails {
    uint104 amount;
    uint24 coverId;
    Asset asset; // in ETH or DAI
    uint80 nxmPriceSnapshot; // NXM price in ETH or DAI
    uint16 coverPeriod; // days
    // a snapshot of FLAT_ETH_FEE_PERC at submission if it ever changes before redeeming
    uint16 flatEthFeePerc;
    bool withdrawalLocked;
  }

  struct IncidentDetails {
    uint104 activeCoverAmount; // ETH or DAI
    uint24 productId;
    Asset asset;
    uint80 nxmPriceSnapshot; // NXM price in ETH or DAI
  }

  struct Incident {
    Poll poll;
    IncidentDetails details;
  }

  struct Claim {
    Poll poll;
    ClaimDetails details;
  }

  struct FraudResolution {
    uint112 accepted;
    uint112 denied;
    bool exists;
    /*uint24 unused,*/
  }

  uint public constant PRECISION = 10 ** 18;
  uint16 public constant PERC_BASIS_POINTS = 10000; // 2 decimals

  /* ========== STATE VARIABLES ========== */

  ERC20 public nxm;
  address public DAI_ADDRESS;
  uint16 public REWARD_PERC;
  uint16 public FLAT_ETH_FEE_PERC;
  uint8 public INCIDENT_TOKEN_WEIGHT_PERC;
  uint8 public VOTING_PERIOD_DAYS_MIN;
  uint8 public VOTING_PERIOD_DAYS_MAX;
  uint8 public PAYOUT_COOLDOWN_DAYS;

  mapping(address => Deposit) public depositOf;
  mapping(address => Vote[]) public votesOf;

  mapping(uint104 => FraudResolution) public fraudResolutionOfClaim;
  mapping(uint104 => FraudResolution) public fraudResolutionOfIncident;
	bytes32[] fraudMerkleRoots;

  Claim[] public claims;
  Incident[] public incidents;

  /* ========== CONSTRUCTOR ========== */

  constructor (address _nxm) {

    nxm = ERC20(_nxm);

    // The minimum cover premium is 2.6%
    // 20% of the cover premium is:
    // 2.6% * 20% = 0.52%
    REWARD_PERC = 52;

    INCIDENT_TOKEN_WEIGHT_PERC = 30; // 30%
    VOTING_PERIOD_DAYS_MIN = 3; // days
    VOTING_PERIOD_DAYS_MAX = 30; // days
    PAYOUT_COOLDOWN_DAYS = 1; //days
    FLAT_ETH_FEE_PERC = 500; // 5% i.e. 0.05 ETH submission flat fee
    DAI_ADDRESS = 0x0000000000000000000000000000000000000000;

  }

  function abs(int x) private pure returns (int) {
      return x >= 0 ? x : -x;
  }

  function max(uint a, uint b) private pure returns (uint) {
      return a >= b ? a : b;
  }

  function min(uint a, uint b) private pure returns (uint) {
      return a <= b ? a : b;
  }

  /* ========== VIEWS ========== */

  /// @dev Returns block timestamp truncated to 32 bits
  function _blockTimestamp() internal view virtual returns (uint32) {
      return uint32(block.timestamp);
  }

  function _getVotingPeriodEnd (uint accepted, uint denied, uint voteStart, uint payoutImpact) internal view returns (uint32) {
    if (accepted == 0 && denied == 0) {
      return uint32(voteStart + VOTING_PERIOD_DAYS_MIN * 1 days);
    }

    uint consensusStrength = uint(abs(int(2 * accepted * PRECISION / (accepted + denied)) - int(PRECISION)));
    uint tokenWeightStrength = min((accepted + denied) * PRECISION / payoutImpact, 10 * PRECISION);

    return uint32(voteStart + VOTING_PERIOD_DAYS_MIN * 1 days +
      (1 * PRECISION - min(consensusStrength,  tokenWeightStrength)) *
      (VOTING_PERIOD_DAYS_MAX * 1 days - VOTING_PERIOD_DAYS_MIN * 1 days) / PRECISION);
  }

  function _getEndOfCooldownPeriod (uint32 voteEnd) internal view returns (uint32) {
    return voteEnd + PAYOUT_COOLDOWN_DAYS * 1 days;
  }

	function _getPollState (Poll memory poll) internal pure returns (
    uint112 accepted,
    uint112 denied,
    uint32 voteStart
	) {
		accepted = poll.accepted;
		denied = poll.denied;
		voteStart = poll.voteStart;
	}

	function _getPayoutImpactOfClaim (Claim memory claim) internal view returns (uint) {
		return claim.details.amount;
	}

	function _getPayoutImpactOfIncident (Incident memory incident) internal view returns (uint) {
	 return incident.details.activeCoverAmount * INCIDENT_TOKEN_WEIGHT_PERC / 100;
	}

  function getVotingPeriodEnd (EventType eventType, uint104 id) public view returns (uint32) {
    uint112 accepted;
    uint112 denied;
    uint32 voteStart;
    uint payoutImpact;

    if (eventType == EventType.CLAIM) {
      Claim memory claim = claims[id];
			(accepted, denied, voteStart) = _getPollState(claim.poll);
			payoutImpact = _getPayoutImpactOfClaim(claim);
		} else {
			Incident memory incident = incidents[id];
			(accepted, denied, voteStart) = _getPollState(incident.poll);
			payoutImpact = _getPayoutImpactOfIncident(incident);
		}

    return _getVotingPeriodEnd(accepted, denied, voteStart, payoutImpact);
  }

  function getEndOfCooldownPeriod (EventType eventType, uint104 id) public view returns (uint32) {
    return _getEndOfCooldownPeriod(getVotingPeriodEnd(eventType, id));
  }

  function isInCooldownPeriod (EventType eventType, uint104 id) public view returns (bool) {
    return _blockTimestamp() > getEndOfCooldownPeriod(eventType, id);
  }

  function isVotingClosed (EventType eventType, uint104 id) public view returns (bool) {
    return _blockTimestamp() > getVotingPeriodEnd(eventType, id);
  }

  function getPollStatus(EventType eventType, uint104 id) public view returns (PollStatus) {
    if (!isVotingClosed(eventType, id)) {
      return PollStatus.PENDING;
    }

    FraudResolution memory fraudResolution = eventType == EventType.CLAIM
        ? fraudResolutionOfClaim[id]
        : fraudResolutionOfIncident[id];
    if (fraudResolution.exists) {
      return fraudResolution.accepted > fraudResolution.denied
        ? PollStatus.ACCEPTED
        : PollStatus.DENIED;
    }

    Poll memory poll = eventType == EventType.CLAIM
        ? claims[id].poll
        : incidents[id].poll;
    return poll.accepted > poll.denied ? PollStatus.ACCEPTED : PollStatus.DENIED;
  }

  function canWithdrawPayout (EventType eventType, uint104 id) external view returns (bool) {
    return getPollStatus(eventType, id) == PollStatus.ACCEPTED && isInCooldownPeriod(eventType, id);
  }

  function getSubmissionFee() internal returns (uint) {
    return 1 ether * uint(FLAT_ETH_FEE_PERC) / uint(PERC_BASIS_POINTS);
  }

  function submitClaimForAssessment(uint24 coverId, uint112 claimAmount) external payable {
    require( msg.value == getSubmissionFee(), "Assessment: Submission fee different that the expected value");
    // [todo] Cover premium and total amount need to be obtained from the cover
    // itself. The premium needs to be converted to NXM using a TWAP at claim time.
    uint104 coverAmount = 1000 ether;
    uint16 coverPeriod = 365;
    Asset asset = Asset.ETH; // take this form cover asset
    uint80 nxmPriceSnapshot = uint80(1 ether);

    // a snapshot of FLAT_ETH_FEE_PERC at submission if it ever changes before redeeming
    claims.push(Claim(
      Poll(0,0,_blockTimestamp()),
      ClaimDetails(
        coverAmount,
        coverId,
        asset,
        nxmPriceSnapshot,
        coverPeriod,
        FLAT_ETH_FEE_PERC,
        false
      )
    ));

  }

  function submitIncidentForAssessment(uint24 productId, uint112 priceBefore) external payable {

    uint104 activeCoverAmount = 20000 ether;
    Asset asset = Asset.ETH; // take this form product underlying asset
    uint80 nxmPriceSnapshot = uint80(1 ether);

    incidents.push(Incident(
      Poll(0,0,_blockTimestamp()),
      IncidentDetails (
        activeCoverAmount, // ETH or DAI
        productId,
        asset,
        nxmPriceSnapshot // NXM price in ETH or DAI
      )
    ));

  }

  function stake (uint104 amount) external {
    Deposit storage deposit = depositOf[msg.sender];
    deposit.amount += amount;
    nxm.transferFrom(msg.sender, address(this), amount);
  }

  // Allows withdrawing the deposit and reward. When rewardOnly is true, the reward is withdrawn
  // and the deposit is left intact.
  // [todo] This method must be nonReentrant
  function withdraw (uint112 amount, uint104 untilIndex, bool rewardOnly) external {

    Deposit storage deposit = depositOf[msg.sender];
    Vote[] memory votes = votesOf[msg.sender];
    require(deposit.amount == 0, "Assessment: No withdrawable deposit");
    require(untilIndex <= votes.length, "Assessment: Votes length is smaller that the provided untilIndex");

    uint rewardToWithdraw = 0;
    uint totalReward = 0;
    if (deposit.voteRewardCursor < votes.length) {
      for (uint i = deposit.voteRewardCursor; i < (untilIndex > 0 ? untilIndex : votes.length); i++) {
        Vote memory vote = votes[i];
        require(_blockTimestamp() > vote.timestamp + VOTING_PERIOD_DAYS_MAX + PAYOUT_COOLDOWN_DAYS);
        if (vote.eventType == EventType.CLAIM) {
          Claim memory claim = claims[vote.eventId];
          totalReward = claim.details.amount * REWARD_PERC * claim.details.coverPeriod / 365 / PERC_BASIS_POINTS;
          rewardToWithdraw += totalReward * vote.tokenWeight / (claim.poll.accepted + claim.poll.denied);
        } else {
          Incident memory incident = incidents[vote.eventId];
          totalReward = incident.details.activeCoverAmount * REWARD_PERC / PERC_BASIS_POINTS;
          rewardToWithdraw += totalReward * vote.tokenWeight / (incident.poll.accepted + incident.poll.denied);
        }
      }

      deposit.voteRewardCursor = uint104(untilIndex > 0 ? untilIndex : votes.length) - 1;
      //nxm.mint(msg.sender, rewardToWithdraw);
    }

    if (!rewardOnly) {
      require(_blockTimestamp() > votes[votes.length - 1].timestamp + VOTING_PERIOD_DAYS_MAX + PAYOUT_COOLDOWN_DAYS);
      nxm.transferFrom(address(this), msg.sender, deposit.amount);
      deposit.amount = 0;
    }

  }

  function triggerClaimPayout (uint104 claimId) external {
    Claim storage claim = claims[claimId];
    require(getPollStatus(EventType.CLAIM, claimId) == PollStatus.ACCEPTED, "Assessment: The claim must be accepted");
    require(isInCooldownPeriod(EventType.CLAIM, claimId), "Assessment: The claim is in cooldown period");
    require(!claim.details.withdrawalLocked, "Assessment: Payout was already redeemed");
    claim.details.withdrawalLocked = true;
    nxm.transferFrom(msg.sender, address(this), claim.details.amount);
  }

   // [todo] Reset voteStart on accept vote, require first verdict to be true
  function castVote (EventType eventType, uint104 id, bool verdict) external {
    Deposit memory deposit = depositOf[msg.sender];
    require(deposit.amount > 0, "Assessment: A stake is required to cast votes");

    Poll storage poll = eventType == EventType.CLAIM
      ? claims[id].poll
      : incidents[id].poll;
    require(poll.accepted > 0 || verdict == true, "Assessment: At least one accept vote is required to vote deny");

    if (verdict == true) {
      if (poll.accepted == 0) {
        poll.voteStart = _blockTimestamp();
      }
      poll.accepted += deposit.amount;
    } else {
      poll.denied += deposit.amount;
    }
    Vote[] storage votes = votesOf[msg.sender];
    votes.push(Vote(
      verdict,
      id,
      _blockTimestamp(),
      deposit.amount,
      eventType
    ));
  }

    function redeem(address account, uint256 tokenId, bytes32[] calldata proof)
    external
    {
        require(_verify(_leaf(account, tokenId), proof), "Invalid merkle proof");
        _safeMint(account, tokenId);
    }

  // [todo] This should only be called by governance
  function burnFraud (
		address fraudulentAssessor,
		uint voteBatchSize,
		bytes32 root,
		bytes32[] calldata proof
	) public {
		require(_verify(_leaf(account, tokenId), proof), "Invalid merkle proof");
		uint32 blockTimestamp = _blockTimestamp();
		Vote[] memory votes = votesOf[fraudulentAssessor];
		Deposit storage deposit = depositOf[fraudulentAssessor];
		uint processUntil;
		if (voteBatchSize == 0 || deposit.voteRewardCursor + voteBatchSize >= votes.length) {
			processUntil = votes.length;
		} else {
			processUntil = deposit.voteRewardCursor + voteBatchSize;
		}
		for (uint j = deposit.voteRewardCursor; j < processUntil; j++) {
			Vote memory vote = votes[j];

			FraudResolution storage fraudResolution = vote.eventType == EventType.CLAIM
				? fraudResolutionOfClaim[vote.eventId]
				: fraudResolutionOfIncident[vote.eventId];
			if (fraudResolution.exists) {
				if (vote.verdict == true) {
					fraudResolution.accepted -= vote.tokenWeight;
				} else {
					fraudResolution.denied -= vote.tokenWeight;
				}
			} else {
				uint112 accepted;
				uint112 denied;
				uint32 voteStart;
				uint payoutImpact;
				if (vote.eventType == EventType.CLAIM) {
					Claim memory claim = claims[vote.eventId];
					if (claim.details.withdrawalLocked) {
						// Once the payout is withdrawn the poll result is final
						continue;
					}
					(accepted, denied, voteStart) = _getPollState(claim.poll);
					payoutImpact = _getPayoutImpactOfClaim(claim);
				} else {
					Incident memory incident = incidents[vote.eventId];
					(accepted, denied, voteStart) = _getPollState(incident.poll);
					payoutImpact = _getPayoutImpactOfIncident(incident);
				}
				uint32 voteEnd = _getVotingPeriodEnd(accepted, denied, voteStart, payoutImpact);
				if (_getEndOfCooldownPeriod(voteEnd) > blockTimestamp) {
					// Once the payout is withdrawn the poll result is final
					continue;
				}
				if (vote.verdict == true) {
					accepted -= vote.tokenWeight;
				} else {
					denied -= vote.tokenWeight;
				}
				if (vote.eventType == EventType.CLAIM) {
					fraudResolutionOfClaim[vote.eventId] = FraudResolution( accepted, denied, true);
				} else {
					fraudResolutionOfIncident[vote.eventId] = FraudResolution( accepted, denied, true);
				}
			}
		}
		// Deposit becomes 0 and accrued rewards are no longer withdrawable
		//nxm.burnFrom(assessor, uint(deposit.amount));
		deposit.amount = uint104(0);
		deposit.voteRewardCursor = uint104(votes.length);
  }

  // [todo] Make sure this operation is done with only one write since all params fit in one slot
  function updateUintParameters (UintParams[] calldata paramNames, uint[] calldata values) external {
		for (uint i = 0; i < paramNames.length; i++) {
			if (paramNames[i] == UintParams.REWARD_PERC) {
				REWARD_PERC = uint16(values[i]);
				continue;
			}
			if (paramNames[i] == UintParams.FLAT_ETH_FEE_PERC) {
				FLAT_ETH_FEE_PERC = uint16(values[i]);
				continue;
			}
			if (paramNames[i] == UintParams.INCIDENT_TOKEN_WEIGHT_PERC) {
				INCIDENT_TOKEN_WEIGHT_PERC = uint8(values[i]);
				continue;
			}
			if (paramNames[i] == UintParams.VOTING_PERIOD_DAYS_MIN) {
				VOTING_PERIOD_DAYS_MIN = uint8(values[i]);
				continue;
			}
			if (paramNames[i] == UintParams.VOTING_PERIOD_DAYS_MAX) {
				VOTING_PERIOD_DAYS_MAX = uint8(values[i]);
				continue;
			}
			if (paramNames[i] == UintParams.PAYOUT_COOLDOWN_DAYS) {
				PAYOUT_COOLDOWN_DAYS = uint8(values[i]);
				continue;
			}
		}
  }

  /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);

}
