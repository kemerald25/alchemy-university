import assert from "node:assert/strict";
import { describe, it, beforeEach } from "node:test";
import { network } from "hardhat";
import { parseEther, formatEther } from "viem";

describe("MultiSigTreasury", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  
  let treasury: any;
  let deployer: any;
  let member1: any;
  let member2: any;
  let nonMember: any;
  let recipient: any;
  let deploymentBlockNumber: bigint;

  beforeEach(async () => {
    [deployer, member1, member2, nonMember, recipient] = await viem.getWalletClients();
    
    treasury = await viem.deployContract("MultiSigTreasury", [
      [member1.account.address, member2.account.address],
      2n
    ]);
    
    deploymentBlockNumber = await publicClient.getBlockNumber();
    
    // Fund the treasury
    await deployer.sendTransaction({
      to: treasury.address,
      value: parseEther("10")
    });
  });

  it("Should initialize with correct member count and threshold", async function () {
    const memberCount = await treasury.read.memberCount();
    const threshold = await treasury.read.approvalThreshold();
    
    assert.equal(memberCount, 3n, "Should have 3 members");
    assert.equal(threshold, 2n, "Threshold should be 2");
  });

  it("Should verify all members are registered", async function () {
    const isDeployerMember = await treasury.read.isMember([deployer.account.address]);
    const isMember1 = await treasury.read.isMember([member1.account.address]);
    const isMember2 = await treasury.read.isMember([member2.account.address]);
    const isNonMember = await treasury.read.isMember([nonMember.account.address]);
    
    assert.equal(isDeployerMember, true);
    assert.equal(isMember1, true);
    assert.equal(isMember2, true);
    assert.equal(isNonMember, false);
  });

  it("Should emit ProposalCreated event when creating a proposal", async function () {
    const anyValue = (val: any) => true;
    
    await viem.assertions.emitWithArgs(
      treasury.write.createProposal([
        recipient.account.address,
        parseEther("1"),
        "Payment for services"
      ]),
      treasury,
      "ProposalCreated",
      [0n, anyValue, anyValue, parseEther("1"), "Payment for services"]
    );
  });

  it("Should create a proposal with correct details", async function () {
    const tx = await treasury.write.createProposal([
      recipient.account.address,
      parseEther("1"),
      "Test payment"
    ]);
    
    const proposal = await treasury.read.getProposal([0n]);
    
    assert.equal(proposal.proposer.toLowerCase(), deployer.account.address.toLowerCase());
    assert.equal(proposal.target.toLowerCase(), recipient.account.address.toLowerCase());
    assert.equal(proposal.amount, parseEther("1"));
    assert.equal(proposal.description, "Test payment");
    assert.equal(proposal.approvalCount, 0n);
    assert.equal(proposal.executed, false);
  });

  it("Should revert when non-member tries to create proposal", async function () {
    await assert.rejects(
      async () => {
        await treasury.write.createProposal(
          [recipient.account.address, parseEther("1"), "Test"],
          { account: nonMember.account }
        );
      },
      /Not a member/
    );
  });

  it("Should emit VoteCast event when voting", async function () {
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("1"),
      "Test payment"
    ]);
    
    const anyValue = (val: any) => true;
    
    await viem.assertions.emitWithArgs(
      treasury.write.vote([0n, true], { account: member1.account }),
      treasury,
      "VoteCast",
      [0n, anyValue, true]
    );
  });

  it("Should count votes correctly", async function () {
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("1"),
      "Test payment"
    ]);
    
    await treasury.write.vote([0n, true], { account: member1.account });
    
    const proposal = await treasury.read.getProposal([0n]);
    assert.equal(proposal.approvalCount, 1n);
  });

  it("Should emit VoteChanged event when changing vote", async function () {
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("1"),
      "Test payment"
    ]);
    
    await treasury.write.vote([0n, true], { account: member1.account });
    
    const anyValue = (val: any) => true;
    
    await viem.assertions.emitWithArgs(
      treasury.write.vote([0n, false], { account: member1.account }),
      treasury,
      "VoteChanged",
      [0n, anyValue, true, false]
    );
  });

  it("Should update vote counts when changing vote", async function () {
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("1"),
      "Test payment"
    ]);
    
    await treasury.write.vote([0n, true], { account: member1.account });
    await treasury.write.vote([0n, false], { account: member1.account });
    
    const proposal = await treasury.read.getProposal([0n]);
    assert.equal(proposal.approvalCount, 0n);
    assert.equal(proposal.rejectionCount, 1n);
  });

  it("Should prevent proposer from voting on their own proposal", async function () {
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("1"),
      "Test payment"
    ]);
    
    await assert.rejects(
      async () => {
        await treasury.write.vote([0n, true]);
      },
      /Proposer cannot vote on own proposal/
    );
  });

  it("Should auto-execute proposal when threshold is reached", async function () {
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("1"),
      "Test payment"
    ]);
    
    const initialBalance = await publicClient.getBalance({ 
      address: recipient.account.address 
    });
    
    await treasury.write.vote([0n, true], { account: member1.account });
    await treasury.write.vote([0n, true], { account: member2.account });
    
    const proposal = await treasury.read.getProposal([0n]);
    assert.equal(proposal.executed, true);
    
    const finalBalance = await publicClient.getBalance({ 
      address: recipient.account.address 
    });
    
    assert.equal(finalBalance - initialBalance, parseEther("1"));
  });

  it("Should emit ProposalExecuted and FundsWithdrawn events", async function () {
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("1"),
      "Test payment"
    ]);
    
    await treasury.write.vote([0n, true], { account: member1.account });
    
    // Use anyValue predicate for dynamic values like executor address
    const anyValue = (val: any) => true;
    
    await viem.assertions.emitWithArgs(
      treasury.write.vote([0n, true], { account: member2.account }),
      treasury,
      "ProposalExecuted",
      [0n, anyValue, true]
    );
  });

  it("Should track multiple proposals correctly", async function () {
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("1"),
      "Proposal 1"
    ]);
    
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("2"),
      "Proposal 2"
    ]);
    
    const count = await treasury.read.proposalCount();
    assert.equal(count, 2n);
    
    const activeCount = await treasury.read.getActiveProposalCount();
    assert.equal(activeCount, 2n);
  });

  it("Should emit ProposalCancelled event when cancelling", async function () {
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("1"),
      "Test payment"
    ]);
    
    const anyValue = (val: any) => true;
    
    await viem.assertions.emitWithArgs(
      treasury.write.cancelProposal([0n]),
      treasury,
      "ProposalCancelled",
      [0n, anyValue]
    );
  });

  it("Should prevent non-proposer from cancelling", async function () {
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("1"),
      "Test payment"
    ]);
    
    await assert.rejects(
      async () => {
        await treasury.write.cancelProposal([0n], { account: member1.account });
      },
      /Only proposer can cancel/
    );
  });

  it("Should emit FundsDeposited event when receiving ETH", async function () {
    const anyValue = (val: any) => true;
    
    await viem.assertions.emitWithArgs(
      deployer.sendTransaction({
        to: treasury.address,
        value: parseEther("5")
      }),
      treasury,
      "FundsDeposited",
      [anyValue, parseEther("5")]
    );
  });

  it("Should return correct treasury balance", async function () {
    const balance = await treasury.read.getTreasuryBalance();
    assert.equal(balance, parseEther("10"));
  });

  it("Should return list of all members", async function () {
    const members = await treasury.read.getMembers();
    assert.equal(members.length, 3);
    assert.equal(members[0].toLowerCase(), deployer.account.address.toLowerCase());
  });

  it("Should track vote status correctly", async function () {
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("1"),
      "Test payment"
    ]);
    
    await treasury.write.vote([0n, true], { account: member1.account });
    
    const [hasVoted, vote] = await treasury.read.getVote([0n, member1.account.address]);
    assert.equal(hasVoted, true);
    assert.equal(vote, true);
  });

  it("Should aggregate proposal events correctly", async function () {
    // Create multiple proposals
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("1"),
      "Proposal 1"
    ]);
    
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("2"),
      "Proposal 2"
    ]);
    
    await treasury.write.createProposal([
      recipient.account.address,
      parseEther("3"),
      "Proposal 3"
    ]);
    
    const events = await publicClient.getContractEvents({
      address: treasury.address,
      abi: treasury.abi,
      eventName: "ProposalCreated",
      fromBlock: deploymentBlockNumber,
      strict: true,
    });
    
    assert.equal(events.length, 3);
    
    let totalAmount = 0n;
    for (const event of events) {
      // Type assertion for event args
      const eventArgs = (event as any).args;
      if (eventArgs && eventArgs.amount) {
        totalAmount += eventArgs.amount;
      }
    }
    
    assert.equal(totalAmount, parseEther("6"));
  });

  it("Should revert when creating proposal with zero amount", async function () {
    await assert.rejects(
      async () => {
        await treasury.write.createProposal([
          recipient.account.address,
          0n,
          "Invalid"
        ]);
      },
      /Amount must be positive/
    );
  });

  it("Should revert when creating proposal exceeding balance", async function () {
    await assert.rejects(
      async () => {
        await treasury.write.createProposal([
          recipient.account.address,
          parseEther("100"),
          "Too much"
        ]);
      },
      /Insufficient treasury balance/
    );
  });

  it("Should create add member proposal", async function () {
    const newMember = "0x0000000000000000000000000000000000000099";
    const anyValue = (val: any) => true;
    
    await viem.assertions.emitWithArgs(
      treasury.write.proposeAddMember([newMember]),
      treasury,
      "ProposalCreated",
      [anyValue, anyValue, anyValue, anyValue, anyValue]
    );
    
    const proposal = await treasury.read.getProposal([0n]);
    assert.equal(proposal.target.toLowerCase(), treasury.address.toLowerCase());
    assert.equal(proposal.amount, 0n);
  });

  it("Should create remove member proposal", async function () {
    const anyValue = (val: any) => true;
    
    await viem.assertions.emitWithArgs(
      treasury.write.proposeRemoveMember([member1.account.address]),
      treasury,
      "ProposalCreated",
      [anyValue, anyValue, anyValue, anyValue, anyValue]
    );
  });

  it("Should create threshold change proposal", async function () {
    const anyValue = (val: any) => true;
    
    await viem.assertions.emitWithArgs(
      treasury.write.proposeThresholdChange([3n]),
      treasury,
      "ProposalCreated",
      [anyValue, anyValue, anyValue, anyValue, anyValue]
    );
  });

  it("Should revert threshold change when exceeding member count", async function () {
    await assert.rejects(
      async () => {
        await treasury.write.proposeThresholdChange([10n]);
      },
      /Threshold exceeds member count/
    );
  });
});