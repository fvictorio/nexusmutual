const { ethers, run } = require('hardhat');
const { MerkleTree } = require('merkletreejs');
const {
  parseEther,
  parseUnits,
  formatEther,
  formatUnits,
  arrayify,
  hexZeroPad,
  hexValue,
} = ethers.utils;
// [warning]: Don't use keccak256 from ethers because it returns a different type than what
// merkletreejs expects.
const keccak256 = require('keccak256');
const formatPage = (page) => page.map(item => {

  const {
    id,
    productId,
    coverId,
    amount,
    coverStart,
    coverEnd,
    voteStart,
    voteEnd,
    claimStatus,
    payoutStatus,
    assetSymbol,
  } = item;
  return {
    id: formatUnits(id, 0),
    productId: formatUnits(productId, 0),
    coverId: formatUnits(coverId, 0),
    amount: formatUnits(amount) + ' ' + assetSymbol,
    coverStart: formatUnits(coverStart, 0),
    coverEnd: formatUnits(coverEnd, 0),
    voteStart: formatUnits(voteStart, 0),
    voteEnd: formatUnits(voteEnd, 0),
    claimStatus,
    payoutStatus,
  };
});
describe('Assessment', function () {

  let nxm, assessment;

  before(async () => {

    await run('compile');

    const NXM = await ethers.getContractFactory('ERC20PresetMinterPauser');
    nxm = await NXM.deploy('NXM', 'NXM');
    await nxm.deployed();

    const Assessment = await ethers.getContractFactory('Assessments');
    assessment = await Assessment.deploy(nxm.address);
    await assessment.deployed();
  });

  it('should survive a rush attack', async function () {
    const [owner, ...attackers] = await ethers.getSigners();
    const COVER_AMOUNT = parseEther('0.04'); // ETH ~ 100DAI
    const SUBMISSION_FEE = parseEther('0.05');
    const GAS_PRICE = '100';
    const CLAIMS_PER_ATTACKER = 1;
    const CLAIMANT_ATTACKERS = 10;
    const CLAIM_COUNT = CLAIMANT_ATTACKERS * CLAIMS_PER_ATTACKER;
    const VOTE_COUNT = CLAIM_COUNT * attackers.length;

    let gasSpentByAttacker = ethers.constants.Zero;
    let submissionFeesSpentByAttacker = ethers.constants.Zero;
    let coverPremiumsPaidByAttacker = ethers.constants.Zero;
    let potentialGainsOfAttacker = ethers.constants.Zero;
    console.log(`Simulating rush attack with ${attackers.length} addresses. Gas: ${GAS_PRICE} gwei.`);
    console.log(`${CLAIMANT_ATTACKERS} addresses open ${CLAIMS_PER_ATTACKER} claims each.`);
    console.log(`All ${attackers.length} attacker addresses vote on every claim.`);
    console.log(`That means ${CLAIM_COUNT} claims and grand total of ${VOTE_COUNT} votes.`);

    /* ========== MINT =========== */
    const mintTxs = attackers.map((attacker) => {
      return nxm.connect(owner).mint(attacker.address, '1');
    });
    const mintTxsSent = await Promise.all(mintTxs);
    await Promise.all(mintTxsSent.map(tx => tx.wait()));

    /* ========= APPROVE ========= */
    const approveTxs = attackers.map((attacker) => {
      return nxm.connect(attacker).approve(assessment.address, '1');
    });
    const approveTxsSent = await Promise.all(approveTxs);
    const approveTxReceipts = await Promise.all(approveTxsSent.map(tx => tx.wait()));

    approveTxReceipts.forEach((receipt) => {
      gasSpentByAttacker = gasSpentByAttacker.add(receipt.gasUsed);
    });

    /* ========== STAKE ========== */
    const depositStakeTxs = attackers.map((attacker) => {
      return assessment.connect(attacker).depositStake('1');
    });
    const depositStakeTxsSent = await Promise.all(depositStakeTxs);
    const depositStakeTxReceipts = await Promise.all(depositStakeTxsSent.map(tx => tx.wait()));

    depositStakeTxReceipts.forEach((receipt) => {
      gasSpentByAttacker = gasSpentByAttacker.add(receipt.gasUsed);
    });

    /* ========== CLAIM ========== */

    const claimantAttackers = attackers.slice(0, CLAIMANT_ATTACKERS);

    const submitClaimForAssessmentTxs = claimantAttackers.map((attacker) => {
      // Cover id is irrelevant for now
      const coverId = 0;
      return Array(CLAIMS_PER_ATTACKER).fill(0).map(() => {
        return assessment.connect(attacker).submitClaimForAssessment(
          coverId, COVER_AMOUNT, false, '', { value: SUBMISSION_FEE },
        );
      });
    }).reduce((acc, x) => { return [...acc, ...x]; }, []);
    const submitClaimForAssessmentTxsSent = await Promise.all(submitClaimForAssessmentTxs);
    const submitClaimForAssessmentTxReceipts = await Promise.all(submitClaimForAssessmentTxsSent.map(tx => tx.wait()));

    submitClaimForAssessmentTxReceipts.forEach((receipt) => {
      coverPremiumsPaidByAttacker = coverPremiumsPaidByAttacker.add(COVER_AMOUNT.mul(26).div(12).div(1000));
      gasSpentByAttacker = gasSpentByAttacker.add(receipt.gasUsed);
      submissionFeesSpentByAttacker = submissionFeesSpentByAttacker.add(SUBMISSION_FEE);
      potentialGainsOfAttacker = potentialGainsOfAttacker.add(COVER_AMOUNT);
    });

    /* ========== VOTE ========== */
    const castVoteTxs = Array(VOTE_COUNT).fill(0).map((_, i) => {
      const index = Math.floor(i / attackers.length / CLAIMS_PER_ATTACKER);
      const attacker = attackers[index];
      return assessment.connect(attacker).castVote(0, i % claimantAttackers.length * CLAIMS_PER_ATTACKER, true);
    });
    const castVoteTxsSent = await Promise.all(castVoteTxs);
    const castVoteTxReceipts = await Promise.all(castVoteTxsSent.map(tx => tx.wait()));

    castVoteTxReceipts.forEach((receipt) => {
      gasSpentByAttacker = gasSpentByAttacker.add(receipt.gasUsed);
    });

    console.log({
      gasSpentByAttacker: formatUnits(gasSpentByAttacker.mul(GAS_PRICE), 9) + ' ETH',
      submissionFeesSpentByAttacker: formatEther(submissionFeesSpentByAttacker) + ' ETH',
      coverPremiumsPaidByAttacker: formatEther(coverPremiumsPaidByAttacker) + ' ETH',
      potentialGainsOfAttacker: formatEther(potentialGainsOfAttacker) + ' ETH',
    });
    {
      const page1 = await assessment.getClaimsToDisplay(0, 4);
      const page2 = await assessment.getClaimsToDisplay(5, 9);
      console.log({ page1: formatPage(page1), page2: formatPage(page2) });
    }

    /* ========== BURN ========== */
    let gasSpentByAB = ethers.constants.Zero;
    const governanceGasCosts = parseUnits((160000 + 263251 * 3 + 105000).toString(),
      0,
    );
    const getLeafInput = (
      account,
      lastFraudulentVoteIndex,
      burnAmount,
      fraudCount,
    ) => [
      ...arrayify(account),
      ...arrayify(hexZeroPad(hexValue(lastFraudulentVoteIndex), 32)),
      ...arrayify(hexZeroPad(hexValue(burnAmount), 13)),
      ...arrayify(hexZeroPad(hexValue(fraudCount), 2)),
    ];

    const burnAddresses = attackers.map(x => x.address);
    const lastFraudulentVoteIndexes = Array(attackers.length).fill(CLAIM_COUNT);
    const burnAmounts = Array(attackers.length).fill(parseUnits('1', 0)); // 1 wei
    const fraudCounts = Array(attackers.length).fill(ethers.constants.Zero); // Assume no previous frauds

    const leaves = burnAddresses.map((address, i) => getLeafInput(
      address,
      lastFraudulentVoteIndexes[i],
      burnAmounts[i],
      fraudCounts[i],
    ));

    const merkleTree = new MerkleTree(
      leaves,
      keccak256,
      { hashLeaves: true, sortPairs: true });
    const root = merkleTree.getHexRoot();
    await assessment.connect(owner).submitFraud(root);

    const batchSize = 200;
    const callsPerAddress = Math.ceil(CLAIMANT_ATTACKERS * CLAIMS_PER_ATTACKER / batchSize);
    console.log('Burning in batches of ' + batchSize + ' votes for each address.');
    console.log('To revert the fraudulent votes, burnFraud is called ' +
      attackers.length * callsPerAddress +
      ' times.');
    for (let i = 0; i < attackers.length; i++) {
      for (let j = 0; j < callsPerAddress; j++) {
        const proof = merkleTree.getHexProof(
          keccak256(getLeafInput(attackers[i].address, CLAIM_COUNT, 1, 0)),
        );
        const tx = await assessment.connect(owner)
          .burnFraud(0, proof, attackers[i].address, CLAIM_COUNT, 1, 0, batchSize);
        const receipt = await tx.wait();
        gasSpentByAB = gasSpentByAB.add(receipt.gasUsed);
      }
    }

    const page1 = await assessment.getClaimsToDisplay(0, 4);
    const page2 = await assessment.getClaimsToDisplay(5, 9);
    console.log({ page1: formatPage(page1), page2: formatPage(page2) });

    console.log({
      gasSpentByAB: formatUnits(gasSpentByAB.add(governanceGasCosts.toString()).mul(GAS_PRICE), 9) + ' ETH',
    });

  });

});
