// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/CrossChainBridge.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor() ERC20("Test Token", "TT") {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }
}

contract CrossChainBridgeTest is Test {
    CrossChainBridge public bridge;
    TestToken public token;
    address public validator;
    uint256 public validatorPk;
    address public recipient;
    uint256 public recipientPk;

    function setUp() public {
        token = new TestToken();
        (validator, validatorPk) = makeAddrAndKey("validator");
        (recipient, recipientPk) = makeAddrAndKey("recipient");

        bridge = new CrossChainBridge(address(token), validator);

        // Fund the bridge
        token.transfer(address(bridge), 100_000 * 10 ** 18);
    }

    function _signTransfer(
        address _recipient,
        uint256 _amount,
        uint256 _transferNonce,
        uint256 _senderNonce,
        uint256 _pk
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
            bridge.TRANSFER_TYPEHASH(),
            _recipient,
            _amount,
            _transferNonce,
            _senderNonce
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", bridge.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_ProcessTransfer_Succeeds() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 transferNonce = 1;
        uint256 senderNonce = bridge.getSenderNonce(recipient);

        bytes memory sig = _signTransfer(recipient, amount, transferNonce, senderNonce, validatorPk);

        uint256 balBefore = token.balanceOf(recipient);
        bridge.processTransfer(recipient, amount, transferNonce, sig);
        uint256 balAfter = token.balanceOf(recipient);

        assertEq(balAfter - balBefore, amount);
        assertEq(bridge.getSenderNonce(recipient), 1);
    }

    function test_Revert_SameChainReplay() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 transferNonce = 1;
        uint256 senderNonce = bridge.getSenderNonce(recipient);

        bytes memory sig = _signTransfer(recipient, amount, transferNonce, senderNonce, validatorPk);

        bridge.processTransfer(recipient, amount, transferNonce, sig);

        // Replay the same message — should fail because nonce incremented
        vm.expectRevert("Already processed");
        bridge.processTransfer(recipient, amount, transferNonce, sig);
    }

    function test_Revert_SameChainReplay_NonceIncrement() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 transferNonce = 1;

        // First transfer with senderNonce=0
        bytes memory sig1 = _signTransfer(recipient, amount, transferNonce, 0, validatorPk);
        bridge.processTransfer(recipient, amount, transferNonce, sig1);

        // Try same transferNonce with old senderNonce — hash is different now
        // because senderNonce incremented to 1, so the old sig won't match
        vm.expectRevert("Invalid signature");
        bridge.processTransfer(recipient, amount, transferNonce, sig1);
    }

    function test_Revert_CrossChainReplay() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 transferNonce = 1;
        uint256 senderNonce = 0;

        // Sign with current chain ID
        bytes memory sig = _signTransfer(recipient, amount, transferNonce, senderNonce, validatorPk);

        // Fork to a different chain ID
        vm.chainId(999);

        // The domain separator was computed at construction with the original chain ID,
        // but the signature was also computed with the original chain ID.
        // On a new chain, the contract would be deployed with a different domain separator,
        // making the signature invalid. Simulate by deploying a new bridge.
        CrossChainBridge newBridge = new CrossChainBridge(address(token), validator);
        token.transfer(address(newBridge), 100_000 * 10 ** 18);

        // The signature from the old chain should not be valid on the new bridge
        // because the domain separator includes the contract address
        vm.expectRevert("Invalid signature");
        newBridge.processTransfer(recipient, amount, transferNonce, sig);
    }

    function test_Revert_PostUpgradeReplay() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 transferNonce = 1;
        uint256 senderNonce = 0;

        bytes memory sig = _signTransfer(recipient, amount, transferNonce, senderNonce, validatorPk);

        // Deploy a "new implementation" at a different address
        CrossChainBridge newImpl = new CrossChainBridge(address(token), validator);
        token.transfer(address(newImpl), 100_000 * 10 ** 18);

        // The signature includes the original contract address in the domain separator,
        // so it cannot be replayed on the new implementation
        vm.expectRevert("Invalid signature");
        newImpl.processTransfer(recipient, amount, transferNonce, sig);
    }

    function test_Revert_InvalidSignature_ZeroAddress() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 transferNonce = 1;

        // Craft a signature that will cause ecrecover to return address(0)
        // Using v=0 with arbitrary r,s can trigger this
        bytes memory badSig = abi.encodePacked(
            bytes32(uint256(1)),
            bytes32(uint256(1)),
            uint8(0)  // v=0, not 27 or 28
        );

        vm.expectRevert("Invalid signature: ecrecover returned zero address");
        bridge.processTransfer(recipient, amount, transferNonce, badSig);
    }

    function test_EIP712_DomainSeparator() public view {
        bytes32 expectedDomain = keccak256(abi.encode(
            bridge.EIP712_DOMAIN_TYPEHASH(),
            keccak256(bytes("CrossChainBridge")),
            keccak256(bytes("1")),
            block.chainid,
            address(bridge)
        ));
        assertEq(bridge.domainSeparator(), expectedDomain);
    }

    function test_EIP712_Verification() public {
        // Verify that EIP-712 structured signing works end-to-end
        uint256 amount = 50 * 10 ** 18;
        uint256 transferNonce = 42;
        uint256 senderNonce = bridge.getSenderNonce(recipient);

        // Compute hash using the contract's own function
        bytes32 expectedHash = bridge.computeTransferHash(recipient, amount, transferNonce);

        // Sign with the same method used in _signTransfer
        bytes32 structHash = keccak256(abi.encode(
            bridge.TRANSFER_TYPEHASH(),
            recipient,
            amount,
            transferNonce,
            senderNonce
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", bridge.domainSeparator(), structHash));

        assertEq(expectedHash, digest);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        bridge.processTransfer(recipient, amount, transferNonce, sig);
        assertEq(token.balanceOf(recipient), amount);
    }

    function test_NonceQueryable() public {
        assertEq(bridge.getSenderNonce(recipient), 0);

        uint256 amount = 10 * 10 ** 18;
        bytes memory sig = _signTransfer(recipient, amount, 1, 0, validatorPk);
        bridge.processTransfer(recipient, amount, 1, sig);

        assertEq(bridge.getSenderNonce(recipient), 1);
    }

    function test_Revert_InvalidSignatureLength() public {
        bytes memory shortSig = new bytes(64);
        vm.expectRevert("Invalid signature length");
        bridge.processTransfer(recipient, 100, 1, shortSig);
    }

    function test_Revert_WrongValidator() public {
        (address wrongValidator, uint256 wrongPk) = makeAddrAndKey("wrong");
        // Deploy bridge with wrong validator
        CrossChainBridge wrongBridge = new CrossChainBridge(address(token), wrongValidator);
        token.transfer(address(wrongBridge), 100_000 * 10 ** 18);

        // Sign with the correct validator key but the bridge expects wrongValidator
        bytes memory sig = _signTransfer(recipient, 100 * 10 ** 18, 1, 0, validatorPk);

        vm.expectRevert("Invalid signature");
        wrongBridge.processTransfer(recipient, 100 * 10 ** 18, 1, sig);
    }
}
