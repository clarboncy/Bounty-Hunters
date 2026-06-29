// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/MultiSigWallet.sol";

contract AttackerContract {
    MultiSigWallet public wallet;
    uint256 public targetTxId;

    constructor(address _wallet) {
        wallet = MultiSigWallet(payable(_wallet));
    }

    function setTarget(uint256 _txId) external {
        targetTxId = _txId;
    }

    receive() external payable {
        wallet.revokeConfirmation(targetTxId);
    }
}

contract MultiSigWalletTest is Test {
    MultiSigWallet public wallet;
    address public owner1;
    address public owner2;
    address public owner3;
    address[] public owners;
    uint256 public required = 2;

    function setUp() public {
        owner1 = makeAddr("owner1");
        owner2 = makeAddr("owner2");
        owner3 = makeAddr("owner3");
        owners.push(owner1);
        owners.push(owner2);
        owners.push(owner3);

        wallet = new MultiSigWallet(owners, required);
        vm.deal(address(wallet), 10 ether);
    }

    function test_SubmitAndExecute() public {
        vm.startPrank(owner1);
        uint256 txId = wallet.submitTransaction(owner2, 1 ether, "");
        wallet.confirmTransaction(txId);
        vm.stopPrank();

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        assertEq(wallet.getConfirmationCount(txId), 2);

        vm.prank(owner1);
        wallet.executeTransaction(txId);

        assertEq(owner2.balance, 1 ether);
    }

    function test_Revert_ZeroAddressTarget() public {
        vm.prank(owner1);
        vm.expectRevert("Zero address target");
        wallet.submitTransaction(address(0), 1 ether, "");
    }

    function test_Revert_NotEnoughConfirmations() public {
        vm.startPrank(owner1);
        uint256 txId = wallet.submitTransaction(owner2, 1 ether, "");
        wallet.confirmTransaction(txId);
        vm.stopPrank();

        vm.expectRevert("Not enough confirmations");
        vm.prank(owner1);
        wallet.executeTransaction(txId);
    }

    function test_Revert_AlreadyExecuted() public {
        vm.startPrank(owner1);
        uint256 txId = wallet.submitTransaction(owner2, 1 ether, "");
        wallet.confirmTransaction(txId);
        vm.stopPrank();

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        vm.prank(owner1);
        wallet.executeTransaction(txId);

        vm.expectRevert("Already executed");
        vm.prank(owner1);
        wallet.executeTransaction(txId);
    }

    function test_RevokeConfirmation() public {
        vm.startPrank(owner1);
        uint256 txId = wallet.submitTransaction(owner2, 1 ether, "");
        wallet.confirmTransaction(txId);
        vm.stopPrank();

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        vm.prank(owner1);
        wallet.revokeConfirmation(txId);

        assertEq(wallet.getConfirmationCount(txId), 1);

        vm.expectRevert("Not enough confirmations");
        vm.prank(owner2);
        wallet.executeTransaction(txId);
    }

    function test_Reentrancy_PreventsRevocationDuringCallback() public {
        AttackerContract attacker = new AttackerContract(address(wallet));

        address[] memory ownersWithAttacker = new address[](3);
        ownersWithAttacker[0] = owner1;
        ownersWithAttacker[1] = owner2;
        ownersWithAttacker[2] = address(attacker);

        MultiSigWallet wallet2 = new MultiSigWallet(ownersWithAttacker, 2);
        vm.deal(address(wallet2), 10 ether);

        vm.startPrank(owner1);
        uint256 txId = wallet2.submitTransaction(address(attacker), 1 ether, "");
        wallet2.confirmTransaction(txId);
        vm.stopPrank();

        vm.prank(owner2);
        wallet2.confirmTransaction(txId);

        attacker.setTarget(txId);

        vm.prank(owner1);
        wallet2.executeTransaction(txId);

        assertEq(address(attacker).balance, 1 ether);
    }

    function test_ConfirmationAtBlock() public {
        vm.startPrank(owner1);
        uint256 txId = wallet.submitTransaction(owner2, 1 ether, "");
        wallet.confirmTransaction(txId);
        vm.stopPrank();

        uint256 confirmBlock = block.number;
        vm.roll(block.number + 10);

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        assertTrue(wallet.isConfirmedAtBlock(txId, owner1, confirmBlock));
        assertTrue(wallet.isConfirmedAtBlock(txId, owner1, confirmBlock + 5));
        assertFalse(wallet.isConfirmedAtBlock(txId, owner2, confirmBlock));
        assertTrue(wallet.isConfirmedAtBlock(txId, owner2, block.number));
    }

    function test_GetConfirmationCountAtBlock() public {
        vm.startPrank(owner1);
        uint256 txId = wallet.submitTransaction(owner2, 1 ether, "");
        wallet.confirmTransaction(txId);
        vm.stopPrank();

        uint256 block1 = block.number;
        vm.roll(block.number + 5);

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        assertEq(wallet.getConfirmationCountAtBlock(txId, block1), 1);
        assertEq(wallet.getConfirmationCountAtBlock(txId, block.number), 2);
    }

    function test_Revert_RevokeNotConfirmed() public {
        vm.startPrank(owner1);
        uint256 txId = wallet.submitTransaction(owner2, 1 ether, "");
        vm.stopPrank();

        vm.expectRevert("Not confirmed");
        vm.prank(owner1);
        wallet.revokeConfirmation(txId);
    }

    function test_Revert_ConfirmAlreadyConfirmed() public {
        vm.startPrank(owner1);
        uint256 txId = wallet.submitTransaction(owner2, 1 ether, "");
        wallet.confirmTransaction(txId);
        vm.stopPrank();

        vm.expectRevert("Already confirmed");
        vm.prank(owner1);
        wallet.confirmTransaction(txId);
    }

    function test_Revert_NotOwner() public {
        address notOwner = makeAddr("notOwner");

        vm.expectRevert("Not owner");
        vm.prank(notOwner);
        wallet.submitTransaction(owner2, 1 ether, "");
    }

    function test_Revert_ZeroAddressOwnerInConstructor() public {
        address[] memory badOwners = new address[](2);
        badOwners[0] = address(0);
        badOwners[1] = owner2;

        vm.expectRevert("Zero address owner");
        new MultiSigWallet(badOwners, 1);
    }
}
