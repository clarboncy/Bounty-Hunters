// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/CrossChainBridge.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor(uint256 supply) ERC20("Test", "TST") {
        _mint(msg.sender, supply);
    }
}

contract CrossChainBridgeTest is Test {
    CrossChainBridge public bridge;
    TestToken public token;
    address public validator;
    address public alice;
    uint256 public validatorPk;

    function setUp() public {
        validatorPk = 0xA1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1;
        validator = vm.addr(validatorPk);
        alice = makeAddr("alice");

        token = new TestToken(1_000_000 ether);
        bridge = new CrossChainBridge(address(token), validator);

        token.transfer(alice, 100_000 ether);
        vm.prank(alice);
        token.approve(address(bridge), type(uint256).max);
    }

    function _signTransfer(address recipient, uint256 amount, uint256 transferNonce, uint256 chainId, address contractAddr)
        internal
        view
        returns (bytes memory)
    {
        bytes32 typeHash = keccak256("Transfer(address recipient,uint256 amount,uint256 transferNonce,uint256 sourceChainId,address contractAddress)");
        bytes32 structHash = keccak256(abi.encode(
            typeHash,
            recipient,
            amount,
            transferNonce,
            chainId,
            contractAddr
        ));
        bytes32 domainSep = bridge.domainSeparator();
        bytes32 typedDataHash = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPk, typedDataHash);
        return abi.encodePacked(r, s, v);
    }

    function test_InitiateAndProcessTransfer() public {
        vm.prank(alice);
        bridge.initiateTransfer(1000 ether, 2);

        bytes memory sig = _signTransfer(alice, 1000 ether, 0, block.chainid, address(bridge));
        bridge.processTransfer(alice, 1000 ether, 0, sig);

        assertEq(token.balanceOf(alice), 100_000 ether);
    }

    function test_Revert_SameChainReplay() public {
        vm.prank(alice);
        bridge.initiateTransfer(1000 ether, 2);

        bytes memory sig = _signTransfer(alice, 1000 ether, 0, block.chainid, address(bridge));
        bridge.processTransfer(alice, 1000 ether, 0, sig);

        vm.expectRevert("Already processed");
        bridge.processTransfer(alice, 1000 ether, 0, sig);
    }

    function test_Revert_CrossChainReplay() public {
        bytes memory sig = _signTransfer(alice, 1000 ether, 0, 999, address(bridge));
        vm.expectRevert("Invalid signature");
        bridge.processTransfer(alice, 1000 ether, 0, sig);
    }

    function test_Revert_PostUpgradeReplay() public {
        address wrongContract = makeAddr("wrong");
        bytes memory sig = _signTransfer(alice, 1000 ether, 0, block.chainid, wrongContract);
        vm.expectRevert("Invalid signature");
        bridge.processTransfer(alice, 1000 ether, 0, sig);
    }

    function test_Revert_InvalidSignature() public {
        bytes memory badSig = new bytes(65);
        vm.expectRevert("Invalid signature");
        bridge.processTransfer(alice, 1000 ether, 0, badSig);
    }

    function test_Revert_SignatureTooShort() public {
        bytes memory shortSig = new bytes(64);
        vm.expectRevert("Invalid signature length");
        bridge.processTransfer(alice, 1000 ether, 0, shortSig);
    }

    function test_Revert_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("Amount must be > 0");
        bridge.initiateTransfer(0, 2);
    }

    function test_GetTransferHash() public {
        bytes32 hash = bridge.getTransferHash(alice, 1000 ether, 0);
        assertTrue(hash != bytes32(0));
    }

    function test_DomainSeparator() public {
        bytes32 ds = bridge.domainSeparator();
        assertTrue(ds != bytes32(0));
    }

    function test_GetSenderNonce() public {
        assertEq(bridge.getSenderNonce(alice), 0);
    }
}
