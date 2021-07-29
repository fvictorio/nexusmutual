const { ethers, run } = require('hardhat');
const { MerkleTree } = require('merkletreejs');

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
    const SUBMISSION_FEE = ethers.utils.parseEther('0.05');
    const CLAIMS_PER_ATTACKER = 100;
    // const attackerAddresses = Array(1000).fill(0).map((_, i) => '0xa' + ((i + 1).toString().padStart(40 - 1, 0)));
    let gasSpentByAttacker = ethers.constants.Zero;
    let submissionFeesSpentByAttacker = ethers.constants.Zero;
    let coverPremiumsPaidByAttacker = ethers.constants.Zero;
    let potentialGainsOfAttacker = ethers.constants.Zero;
    console.log(`Simulating rush attack with ${attackers.length} addresses wtih ${CLAIMS_PER_ATTACKER} claims each at 1 gwei per gas unit.`);
    for (const attacker of attackers) {
      {
        // We don't take the cost of aquiring NXM into consideration
        const tx = await nxm.connect(owner).mint(attacker.address, '1'); // mint 1 wei
        await tx.wait();
      }
      {
        const tx = await nxm.connect(attacker).approve(assessment.address, '1'); // approve 1 wei
        const receipt = await tx.wait();
        gasSpentByAttacker = gasSpentByAttacker.add(receipt.gasUsed);
      }
      {
        const tx = await assessment.connect(attacker).stake('1'); // stake 1 wei
        const receipt = await tx.wait();
        gasSpentByAttacker = gasSpentByAttacker.add(receipt.gasUsed);
      }
      // Cover id is irrelevant for now
      const COVER_AMOUNT = ethers.utils.parseEther('0.0004'); // ETH ~ 1DAI

      const submitClaimForAssessmentTxs = Array(CLAIMS_PER_ATTACKER).fill(0).map(coverId => {
        return assessment.connect(attacker)
          .submitClaimForAssessment(coverId, COVER_AMOUNT, { value: SUBMISSION_FEE });
      });
      const submitClaimForAssessmentTxsSent = await Promise.all(submitClaimForAssessmentTxs);
      const submitClaimForAssessmentTxReceipts = await Promise.all(
        submitClaimForAssessmentTxsSent.map(tx => tx.wait()),
      );

      submitClaimForAssessmentTxReceipts.forEach((receipt) => {
        coverPremiumsPaidByAttacker = coverPremiumsPaidByAttacker.add(COVER_AMOUNT.mul(26).div(12).div(1000));
        gasSpentByAttacker = gasSpentByAttacker.add(receipt.gasUsed);
        submissionFeesSpentByAttacker = submissionFeesSpentByAttacker.add(SUBMISSION_FEE);
        potentialGainsOfAttacker = potentialGainsOfAttacker.add(COVER_AMOUNT);
      });

      const castVoteTxs = Array(CLAIMS_PER_ATTACKER).fill(0).map((_, i) => {
        return assessment.connect(attacker).castVote(0, i, true);
      });
      const castVoteTxsSent = await Promise.all(castVoteTxs);
      const castVoteTxReceipts = await Promise.all(castVoteTxsSent.map(tx => tx.wait()));

      castVoteTxReceipts.forEach((receipt) => {
        gasSpentByAttacker = gasSpentByAttacker.add(receipt.gasUsed);
      });

    }
    console.log({
      gasSpentByAttacker: ethers.utils.formatUnits(gasSpentByAttacker, 9) + ' ETH',
      submissionFeesSpentByAttacker: ethers.utils.formatEther(submissionFeesSpentByAttacker) + ' ETH',
      coverPremiumsPaidByAttacker: ethers.utils.formatEther(coverPremiumsPaidByAttacker) + ' ETH',
      potentialGainsOfAttacker: ethers.utils.formatEther(potentialGainsOfAttacker) + ' ETH',
    });

    const addressBatchSize = 2;
    let gasUsedByAB = ethers.constants.Zero;
    const governanceGasCosts = ethers.utils.parseUnits((160000 + 263251 * 3 + 105000).toString(),
      0,
    );
    for (let i = 0; i < attackers.length / addressBatchSize; i++) {
      const addressessToBurn = attackers
        .map(x => x.address)
        .filter((_, j) => j < i * addressBatchSize + addressBatchSize && j >= i * addressBatchSize);
      for (let j = 0; j < Math.ceil(CLAIMS_PER_ATTACKER / 200); j++) {
        const tx = await assessment.connect(owner).burnFraud(addressessToBurn, 200);
        const receipt = await tx.wait();
        gasUsedByAB = gasUsedByAB.add(receipt.gasUsed).add(governanceGasCosts);
      }
    }

    console.log('The advisory board must open ' + attackers.length * Math.ceil(CLAIMS_PER_ATTACKER / 200) + ' proposals');
    console.log('Each proposal action burns ' + addressBatchSize + ' addresses and processes ' + 200 + ' votes for each address.');
    console.log({
      gasUsedByAB: ethers.utils.formatUnits(gasUsedByAB, 9) + ' ETH',
    });

    // const res = await assessment.claims(0);
    // console.log('Claim 0 poll before burn');
    // console.log({ accepted: res.poll.accepted.toString(), denied: res.poll.denied.toString() });
    // console.log('Claim 0 poll after burn');
    // const res2 = await assessment.fraudResolutionOfClaim(0);
    // console.log({ accepted: res2.accepted.toString(), denied: res2.denied.toString() });
  });

});
