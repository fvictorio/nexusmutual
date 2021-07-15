const { expectEvent, time } = require('@openzeppelin/test-helpers');
const { hex } = require('../../lib').helpers;

const submitProposal = async (gv, category, actionData, members) => {
  const proposalId = await gv.getProposalLength();
  await gv.createProposal('', '', '', '0');
  await gv.categorizeProposal(proposalId, category, 0);
  await gv.submitProposalWithSolution(proposalId, '', actionData);

  for (const member of members) {
    await gv.submitVote(proposalId, 1, { from: member });
  }

  await time.increase(time.duration.days(7));

  const closeTx = await gv.closeProposal(proposalId);
  //  expectEvent(closeTx, 'ActionSuccess', { proposalId });

  const proposal = await gv.proposal(proposalId);

  console.log({
    proposal2: proposal[2].toString(),
  });
  assert.equal(proposal[2].toNumber(), 3, 'proposal status != accepted');

  //   await gv.triggerAction(proposalId);

  return proposalId;
};

const submitMemberVoteProposal = async (gv, pc, categoryId, actionData, members) => {

  const proposalId = await gv.getProposalLength();
  console.log(`Creating proposal ${proposalId}`);

  const from = members[0];
  await gv.createProposal('', '', '', 0, { from });
  await gv.categorizeProposal(proposalId, categoryId, 0, { from });
  await gv.submitProposalWithSolution(proposalId, '', actionData, { from });

  for (const member of members) {
    await gv.submitVote(proposalId, 1, { from: member });
  }

  const { 5: closingTime } = await pc.category(categoryId);
  await time.increase(closingTime.addn(1).toString());
  await gv.closeProposal(proposalId, { from: members[0] });

  const { val: speedBumpHours } = await gv.getUintParameters(hex('ACWT'));
  await time.increase(speedBumpHours.muln(3600).addn(1).toString());
  const triggerTx = await gv.triggerAction(proposalId);

  expectEvent(triggerTx, 'ActionSuccess', { proposalId });

  const proposal = await gv.proposal(proposalId);
  assert.equal(proposal[2].toNumber(), 3, 'proposal status != accepted');
};

module.exports = {
  submitProposal,
  submitMemberVoteProposal,
};
