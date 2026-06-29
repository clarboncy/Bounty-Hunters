// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract CrossChainBridge is EIP712 {
    using ECDSA for bytes32;

    IERC20 public bridgeToken;
    address public validator;

    uint256 public nonce;
    mapping(address => uint256) public senderNonces;
    mapping(bytes32 => bool) public processedTransfers;

    bytes32 private constant TRANSFER_TYPEHASH =
        keccak256("Transfer(address recipient,uint256 amount,uint256 transferNonce,uint256 sourceChainId,address contractAddress)");

    event TransferInitiated(address indexed sender, uint256 amount, uint256 targetChain, uint256 nonce);
    event TransferProcessed(bytes32 indexed transferHash, address indexed recipient, uint256 amount);

    constructor(address _bridgeToken, address _validator)
        EIP712("CrossChainBridge", "1.0")
    {
        bridgeToken = IERC20(_bridgeToken);
        validator = _validator;
    }

    function initiateTransfer(uint256 amount, uint256 targetChain) external {
        require(amount > 0, "Amount must be > 0");
        bridgeToken.transferFrom(msg.sender, address(this), amount);
        emit TransferInitiated(msg.sender, amount, targetChain, nonce++);
    }

    /// @notice Process a cross-chain transfer with replay protection
    /// @param recipient The address receiving tokens
    /// @param amount The amount of tokens
    /// @param transferNonce Unique nonce for this transfer
    /// @param signature Validator's EIP-712 signature
    function processTransfer(
        address recipient,
        uint256 amount,
        uint256 transferNonce,
        bytes calldata signature
    ) external {
        bytes32 transferHash = _hashTransfer(recipient, amount, transferNonce);

        require(!processedTransfers[transferHash], "Already processed");
        require(verifySignature(transferHash, signature), "Invalid signature");

        processedTransfers[transferHash] = true;
        bridgeToken.transfer(recipient, amount);

        emit TransferProcessed(transferHash, recipient, amount);
    }

    /// @notice EIP-712 structured hash including chainId, nonce, and contract address
    function _hashTransfer(address recipient, uint256 amount, uint256 transferNonce) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            TRANSFER_TYPEHASH,
            recipient,
            amount,
            transferNonce,
            block.chainid,
            address(this)
        )));
    }

    /// @notice Verify validator signature with ecrecover zero-address check
    function verifySignature(bytes32 hash, bytes calldata signature) public view returns (bool) {
        require(signature.length == 65, "Invalid signature length");

        address recovered = hash.recover(signature);
        require(recovered != address(0), "Invalid signature: zero address");

        return recovered == validator;
    }

    /// @notice Get the EIP-712 domain separator
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Get the current nonce for a sender (frontend integration)
    function getSenderNonce(address sender) external view returns (uint256) {
        return senderNonces[sender];
    }

    /// @notice Get the typed data hash for off-chain signing
    function getTransferHash(address recipient, uint256 amount, uint256 transferNonce) external view returns (bytes32) {
        return _hashTransfer(recipient, amount, transferNonce);
    }

    function getPoolBalance() external view returns (uint256) {
        return bridgeToken.balanceOf(address(this));
    }
}
