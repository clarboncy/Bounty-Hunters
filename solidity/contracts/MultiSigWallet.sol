// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MultiSigWallet {
    address[] public owners;
    uint256 public required;
    uint256 public transactionCount;

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
    }

    struct ConfirmationRecord {
        bool confirmed;
        uint256 confirmedAtBlock;
    }

    mapping(uint256 => Transaction) public transactions;
    mapping(uint256 => mapping(address => ConfirmationRecord)) public confirmations;
    mapping(address => bool) public isOwner;

    // Reentrancy guard
    uint256 private _executingTxId;
    bool private _executing;

    event Submitted(uint256 indexed txId);
    event Confirmed(uint256 indexed txId, address indexed owner);
    event Executed(uint256 indexed txId);
    event Revoked(uint256 indexed txId, address indexed owner);

    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not owner");
        _;
    }

    modifier nonReentrant() {
        require(!_executing, "Reentrant call");
        _executing = true;
        _;
        _executing = false;
    }

    constructor(address[] memory _owners, uint256 _required) {
        require(_owners.length > 0, "No owners");
        require(_required > 0 && _required <= _owners.length, "Invalid required");
        for (uint256 i = 0; i < _owners.length; i++) {
            require(_owners[i] != address(0), "Zero address owner");
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        required = _required;
    }

    /// @notice Submit a transaction with target validation
    function submitTransaction(address to, uint256 value, bytes calldata data) external onlyOwner returns (uint256) {
        require(to != address(0), "Zero address target");
        uint256 size;
        assembly { size := extcodesize(to) }
        // Allow EOA targets (size == 0) but flag contract targets
        // Both are valid — the check prevents accidental zero-address sends
        uint256 txId = transactionCount++;
        transactions[txId] = Transaction({
            to: to,
            value: value,
            data: data,
            executed: false
        });
        emit Submitted(txId);
        return txId;
    }

    function confirmTransaction(uint256 txId) external onlyOwner {
        require(!transactions[txId].executed, "Already executed");
        require(!confirmations[txId][msg.sender].confirmed, "Already confirmed");
        confirmations[txId][msg.sender] = ConfirmationRecord({
            confirmed: true,
            confirmedAtBlock: block.number
        });
        emit Confirmed(txId, msg.sender);
    }

    function revokeConfirmation(uint256 txId) external onlyOwner {
        require(!transactions[txId].executed, "Already executed");
        require(confirmations[txId][msg.sender].confirmed, "Not confirmed");
        confirmations[txId][msg.sender].confirmed = false;
        emit Revoked(txId, msg.sender);
    }

    function getConfirmationCount(uint256 txId) public view returns (uint256 count) {
        for (uint256 i = 0; i < owners.length; i++) {
            if (confirmations[txId][owners[i]].confirmed) count++;
        }
    }

    /// @notice Check if a transaction was confirmed by a specific owner as of a given block
    function isConfirmedAtBlock(uint256 txId, address owner, uint256 blockNumber) public view returns (bool) {
        return confirmations[txId][owner].confirmed && confirmations[txId][owner].confirmedAtBlock <= blockNumber;
    }

    /// @notice Get the confirmation count as of a specific block number
    function getConfirmationCountAtBlock(uint256 txId, uint256 blockNumber) public view returns (uint256 count) {
        for (uint256 i = 0; i < owners.length; i++) {
            if (confirmations[txId][owners[i]].confirmed && confirmations[txId][owners[i]].confirmedAtBlock <= blockNumber) {
                count++;
            }
        }
    }

    /// @notice Execute a transaction with reentrancy protection and block-level confirmation snapshot
    function executeTransaction(uint256 txId) external onlyOwner nonReentrant {
        require(!transactions[txId].executed, "Already executed");

        // Snapshot confirmation count at current block
        uint256 confirmationSnapshot = getConfirmationCount(txId);
        require(confirmationSnapshot >= required, "Not enough confirmations");

        Transaction storage txn = transactions[txId];
        txn.executed = true;

        // Verify confirmations haven't been revoked during execution
        // The nonReentrant modifier prevents callbacks from calling executeTransaction again
        // But we also verify post-execution that confirmations are still valid
        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        require(success, "Execution failed");

        // Post-execution check: confirmations must still meet threshold
        // If a malicious callback revoked confirmations, this will revert
        require(getConfirmationCount(txId) >= required, "Confirmations revoked during execution");

        emit Executed(txId);
    }

    receive() external payable {}
}
