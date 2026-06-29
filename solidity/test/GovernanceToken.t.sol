// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/GovernanceToken.sol";

contract MaliciousPhishing {
    GovernanceToken public token;

    constructor(address _token) {
        token = GovernanceToken(_token);
    }

    function attack(address delegateTo) external {
        token.delegateVote(delegateTo);
    }
}

contract GovernanceTokenTest is Test {
    GovernanceToken public token;
    address public owner;
    address public alice;
    address public bob;
    address public carol;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        token = new GovernanceToken(1_000_000 ether);
        token.transfer(alice, 100_000 ether);
        token.transfer(bob, 50_000 ether);
    }

    function test_DelegateVote() public {
        vm.prank(alice);
        token.delegateVote(bob);

        assertEq(token.delegates(alice), bob);
        assertEq(token.delegatedPower(bob), 100_000 ether);
        assertEq(token.getVotingPower(bob), 150_000 ether);
    }

    function test_RevokeDelegate() public {
        vm.prank(alice);
        token.delegateVote(bob);

        vm.prank(alice);
        token.revokeDelegate();
        assertEq(token.delegates(alice), address(0));
        assertEq(token.delegatedPower(bob), 0);
        assertEq(token.getVotingPower(bob), 50_000 ether);
    }

    function test_PhishingAttack_Prevented() public {
        MaliciousPhishing attacker = new MaliciousPhishing(address(token));

        vm.prank(alice);
        attacker.attack(carol);

        assertEq(token.delegates(alice), address(0));
        assertEq(token.delegatedPower(carol), 0);
    }

    function test_Revert_DelegateToSelf() public {
        vm.expectRevert("Cannot delegate to self");
        vm.prank(alice);
        token.delegateVote(alice);
    }

    function test_Revert_DelegateToZeroAddress() public {
        vm.expectRevert("Cannot delegate to zero address");
        vm.prank(alice);
        token.delegateVote(address(0));
    }

    function test_Revert_RevokeNoDelegate() public {
        vm.expectRevert("No delegate");
        vm.prank(alice);
        token.revokeDelegate();
    }

    function test_Snapshot_OnlyOwner() public {
        token.snapshot();

        vm.expectRevert();
        vm.prank(alice);
        token.snapshot();
    }

    function test_CreateProposalAndVote() public {
        vm.prank(alice);
        uint256 proposalId = token.createProposal("Test Proposal", 1 days);

        vm.prank(alice);
        token.delegateVote(bob);

        vm.prank(bob);
        token.vote(proposalId, true);

        (, uint256 forVotes, , , ) = token.proposals(proposalId);
        assertEq(forVotes, 150_000 ether);
    }

    function test_Revert_VoteEnded() public {
        vm.prank(alice);
        uint256 proposalId = token.createProposal("Short Proposal", 1 days);

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert("Voting ended");
        vm.prank(alice);
        token.vote(proposalId, true);
    }

    function test_Revert_AlreadyVoted() public {
        vm.prank(alice);
        uint256 proposalId = token.createProposal("Test", 1 days);

        vm.prank(alice);
        token.vote(proposalId, true);

        vm.expectRevert("Already voted");
        vm.prank(alice);
        token.vote(proposalId, false);
    }

    function test_Revert_NoVotingPower() public {
        address nobody = makeAddr("nobody");

        vm.prank(alice);
        uint256 proposalId = token.createProposal("Test", 1 days);

        vm.expectRevert("No voting power");
        vm.prank(nobody);
        token.vote(proposalId, true);
    }
}
