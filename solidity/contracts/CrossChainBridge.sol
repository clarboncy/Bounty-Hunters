// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrossChainBridge {
    IERC20 public bridgeToken;
    address public validator;
    uint256 public nonce;

    mapping(bytes32 => bool) public processedTransfers;
    mapping(address => uint256) public senderNonces;

    // EIP-712 domain separator components
    string public constant EIP712_NAME = "CrossChainBridge";
    string public constant EIP712_VERSION = "1";
    bytes32 public constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 public constant TRANSFER_TYPEHASH = keccak256(
        "Transfer(address recipient,uint256 amount,uint256 transferNonce,uint256 senderNonce)"
    );

    bytes32 public immutable domainSeparator;

    event TransferInitiated(address indexed sender, uint256 amount, uint256 targetChain, uint256 nonce);
    event TransferProcessed(bytes32 indexed transferHash, address indexed recipient, uint256 amount);

    constructor(address _bridgeToken, address _validator) {
        bridgeToken = IERC20(_bridgeToken);
        validator = _validator;
        domainSeparator = keccak256(abi.encode(
            EIP712_DOMAIN_TYPEHASH,
            keccak256(bytes(EIP712_NAME)),
            keccak256(bytes(EIP712_VERSION)),
            block.chainid,
            address(this)
        ));
    }

    function initiateTransfer(uint256 amount, uint256 targetChain) external {
        require(amount > 0, "Amount must be > 0");
        bridgeToken.transferFrom(msg.sender, address(this), amount);
        emit TransferInitiated(msg.sender, amount, targetChain, nonce++);
    }

    /// @notice Process a cross-chain transfer with replay protection
    /// @dev Includes chain ID, contract address, and per-sender nonce in the signed hash
    function processTransfer(
        address recipient,
        uint256 amount,
        uint256 transferNonce,
        bytes calldata signature
    ) external {
        uint256 senderNonce = senderNonces[recipient];

        // EIP-712 structured hash includes chain ID (via domain separator),
        // contract address (via domain separator), and per-sender nonce
        bytes32 structHash = keccak256(abi.encode(
            TRANSFER_TYPEHASH,
            recipient,
            amount,
            transferNonce,
            senderNonce
        ));

        bytes32 transferHash = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            structHash
        ));

        require(!processedTransfers[transferHash], "Already processed");
        require(verifySignature(transferHash, signature), "Invalid signature");

        processedTransfers[transferHash] = true;
        senderNonces[recipient] = senderNonce + 1;

        bridgeToken.transfer(recipient, amount);

        emit TransferProcessed(transferHash, recipient, amount);
    }

    /// @notice Verify a signature with ecrecover, rejecting zero-address results
    function verifySignature(bytes32 hash, bytes calldata signature) public view returns (bool) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (v < 27) v += 27;

        address recovered = ecrecover(hash, v, r, s);

        // Reject invalid signatures (ecrecover returns address(0) on failure)
        require(recovered != address(0), "Invalid signature: ecrecover returned zero address");
        return recovered == validator;
    }

    /// @notice Get the current nonce for a sender (for frontend integration)
    function getSenderNonce(address sender) external view returns (uint256) {
        return senderNonces[sender];
    }

    /// @notice Compute the transfer hash for off-chain signing
    function computeTransferHash(
        address recipient,
        uint256 amount,
        uint256 transferNonce
    ) external view returns (bytes32) {
        uint256 senderNonce = senderNonces[recipient];
        bytes32 structHash = keccak256(abi.encode(
            TRANSFER_TYPEHASH,
            recipient,
            amount,
            transferNonce,
            senderNonce
        ));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function getPoolBalance() external view returns (uint256) {
        return bridgeToken.balanceOf(address(this));
    }
}
