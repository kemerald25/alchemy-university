// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MultiSigTreasury} from "../contracts/MultiSigTreasury.sol";
import {Test} from "forge-std/Test.sol";

contract MultiSigTreasuryTest is Test {
    MultiSigTreasury treasury;
    
    address deployer = address(this);
    address member1 = address(0x1);
    address member2 = address(0x2);
    address member3 = address(0x3);
    address nonMember = address(0x4);
    address recipient = address(0x5);
    
    function setUp() public {
        address[] memory members = new address[](2);
        members[0] = member1;
        members[1] = member2;
        
        treasury = new MultiSigTreasury(members, 2);
        
        // Fund the treasury
        vm.deal(address(treasury), 10 ether);
    }
    
    function test_InitialState() public view {
        require(treasury.memberCount() == 3, "Should have 3 members");
        require(treasury.approvalThreshold() == 2, "Threshold should be 2");
        require(treasury.isMember(deployer), "Deployer should be member");
        require(treasury.isMember(member1), "Member1 should be member");
        require(treasury.isMember(member2), "Member2 should be member");
        require(treasury.getTreasuryBalance() == 10 ether, "Balance should be 10 ETH");
    }
    
    function test_CreateProposal() public {
        uint256 proposalId = treasury.createProposal(
            payable(recipient),
            1 ether,
            "Payment for services"
        );
        
        require(proposalId == 0, "First proposal should have ID 0");
        
        MultiSigTreasury.Proposal memory proposal = treasury.getProposal(proposalId);
        require(proposal.proposer == deployer, "Proposer should be deployer");
        require(proposal.target == recipient, "Target should match");
        require(proposal.amount == 1 ether, "Amount should match");
        require(proposal.approvalCount == 0, "Should have 0 approvals");
        require(!proposal.executed, "Should not be executed");
    }
    
    function test_RevertNonMemberCreateProposal() public {
        vm.prank(nonMember);
        vm.expectRevert("Not a member");
        treasury.createProposal(payable(recipient), 1 ether, "Test");
    }
    
    function test_VoteOnProposal() public {
        uint256 proposalId = treasury.createProposal(
            payable(recipient),
            1 ether,
            "Test payment"
        );
        
        vm.prank(member1);
        treasury.vote(proposalId, true);
        
        MultiSigTreasury.Proposal memory proposal = treasury.getProposal(proposalId);
        require(proposal.approvalCount == 1, "Should have 1 approval");
        
        (bool hasVoted, bool voteValue) = treasury.getVote(proposalId, member1);
        require(hasVoted, "Member1 should have voted");
        require(voteValue, "Vote should be approval");
    }
    
    function test_RevertProposerVoteOnOwnProposal() public {
        uint256 proposalId = treasury.createProposal(
            payable(recipient),
            1 ether,
            "Test payment"
        );
        
        vm.expectRevert("Proposer cannot vote on own proposal");
        treasury.vote(proposalId, true);
    }
    
    function test_ChangeVote() public {
        uint256 proposalId = treasury.createProposal(
            payable(recipient),
            1 ether,
            "Test payment"
        );
        
        vm.prank(member1);
        treasury.vote(proposalId, true);
        
        vm.prank(member1);
        treasury.vote(proposalId, false);
        
        MultiSigTreasury.Proposal memory proposal = treasury.getProposal(proposalId);
        require(proposal.approvalCount == 0, "Should have 0 approvals");
        require(proposal.rejectionCount == 1, "Should have 1 rejection");
    }
    
    function test_AutoExecuteProposal() public {
        uint256 proposalId = treasury.createProposal(
            payable(recipient),
            1 ether,
            "Test payment"
        );
        
        uint256 initialBalance = recipient.balance;
        
        vm.prank(member1);
        treasury.vote(proposalId, true);
        
        vm.prank(member2);
        treasury.vote(proposalId, true);
        
        MultiSigTreasury.Proposal memory proposal = treasury.getProposal(proposalId);
        require(proposal.executed, "Should be executed");
        require(recipient.balance == initialBalance + 1 ether, "Recipient should receive funds");
    }
    
    function test_ManualExecuteProposal() public {
        uint256 proposalId = treasury.createProposal(
            payable(recipient),
            1 ether,
            "Test payment"
        );
        
        vm.prank(member1);
        treasury.vote(proposalId, true);
        
        vm.prank(member2);
        treasury.vote(proposalId, true);
        
        // Proposal already executed via auto-execute
        MultiSigTreasury.Proposal memory proposal = treasury.getProposal(proposalId);
        require(proposal.executed, "Should already be executed");
    }
    
    function test_RevertExecuteWithoutThreshold() public {
        uint256 proposalId = treasury.createProposal(
            payable(recipient),
            1 ether,
            "Test payment"
        );
        
        vm.prank(member1);
        treasury.vote(proposalId, true);
        
        vm.expectRevert("Insufficient approvals");
        treasury.executeProposal(proposalId);
    }
    
    function test_CancelProposal() public {
        uint256 proposalId = treasury.createProposal(
            payable(recipient),
            1 ether,
            "Test payment"
        );
        
        treasury.cancelProposal(proposalId);
        
        MultiSigTreasury.Proposal memory proposal = treasury.getProposal(proposalId);
        require(proposal.cancelled, "Should be cancelled");
    }
    
    function test_RevertNonProposerCancel() public {
        uint256 proposalId = treasury.createProposal(
            payable(recipient),
            1 ether,
            "Test payment"
        );
        
        vm.prank(member1);
        vm.expectRevert("Only proposer can cancel");
        treasury.cancelProposal(proposalId);
    }
    
    function test_ReceiveEther() public {
        uint256 initialBalance = treasury.getTreasuryBalance();
        
        (bool success,) = address(treasury).call{value: 5 ether}("");
        require(success, "Transfer should succeed");
        require(treasury.getTreasuryBalance() == initialBalance + 5 ether, "Balance should increase");
    }
    
    function test_GetMembers() public view {
        address[] memory memberList = treasury.getMembers();
        require(memberList.length == 3, "Should have 3 members");
    }
    
    function test_GetActiveProposalCount() public {
        treasury.createProposal(payable(recipient), 1 ether, "Proposal 1");
        treasury.createProposal(payable(recipient), 2 ether, "Proposal 2");
        
        require(treasury.getActiveProposalCount() == 2, "Should have 2 active proposals");
    }
    
    function testFuzz_CreateProposalWithVariousAmounts(uint96 amount) public {
        vm.assume(amount > 0 && amount <= 10 ether);
        
        uint256 proposalId = treasury.createProposal(
            payable(recipient),
            amount,
            "Fuzz test payment"
        );
        
        MultiSigTreasury.Proposal memory proposal = treasury.getProposal(proposalId);
        require(proposal.amount == amount, "Amount should match");
    }
    
    function test_RevertInvalidProposalAmount() public {
        vm.expectRevert("Amount must be positive");
        treasury.createProposal(payable(recipient), 0, "Invalid amount");
    }
    
    function test_RevertInsufficientBalance() public {
        vm.expectRevert("Insufficient treasury balance");
        treasury.createProposal(payable(recipient), 100 ether, "Too much");
    }
    
    function test_ProposeAddMember() public {
        uint256 proposalId = treasury.proposeAddMember(member3);
        
        MultiSigTreasury.Proposal memory proposal = treasury.getProposal(proposalId);
        require(proposal.target == address(treasury), "Target should be treasury");
        require(proposal.amount == 0, "Amount should be 0");
    }
    
    function test_ProposeRemoveMember() public {
        uint256 proposalId = treasury.proposeRemoveMember(member1);
        
        MultiSigTreasury.Proposal memory proposal = treasury.getProposal(proposalId);
        require(proposal.target == address(treasury), "Target should be treasury");
    }
    
    function test_ProposeThresholdChange() public {
        uint256 proposalId = treasury.proposeThresholdChange(3);
        
        MultiSigTreasury.Proposal memory proposal = treasury.getProposal(proposalId);
        require(proposal.target == address(treasury), "Target should be treasury");
    }
    
    function test_RevertThresholdTooHigh() public {
        vm.expectRevert("Threshold exceeds member count");
        treasury.proposeThresholdChange(10);
    }
}