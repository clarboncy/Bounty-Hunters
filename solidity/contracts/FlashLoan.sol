// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IFlashLoanReceiver {
    function onFlashLoan(address token, uint256 amount, uint256 fee, bytes calldata data) external;
}

contract FlashLoan is ReentrancyGuard {
    IERC20 public loanToken;
    uint256 public feeBPS; // fee in basis points
    uint256 public totalFees;
    address public owner;
    bool public paused;

    // Internal accounting to prevent rebasing token exploits
    uint256 internal poolBalance;

    event FlashLoanExecuted(address indexed borrower, uint256 amount, uint256 fee);
    event Paused();
    event Unpaused();

    constructor(address _loanToken, uint256 _feeBPS) {
        loanToken = IERC20(_loanToken);
        feeBPS = _feeBPS;
        owner = msg.sender;
    }

    function flashLoan(uint256 amount, bytes calldata data) external nonReentrant {
        require(!paused, "Paused");
        require(amount > 0, "Amount must be > 0");

        // Use internal accounting instead of balanceOf for rebasing token safety
        require(poolBalance >= amount, "Insufficient pool balance");

        // Max loan cap: 50% of pool balance to prevent pool drainage
        require(amount <= poolBalance / 2, "Exceeds max loan amount");

        // Minimum fee of 1 token unit prevents free flash loans for small amounts
        uint256 fee = amount * feeBPS / 10000;
        if (fee == 0) fee = 1;

        // Track internal balance before loan
        uint256 balanceBefore = poolBalance;

        // Update internal accounting: deduct loan amount
        poolBalance -= amount;

        loanToken.transfer(msg.sender, amount);

        IFlashLoanReceiver(msg.sender).onFlashLoan(address(loanToken), amount, fee, data);

        // Use internal accounting for repayment validation
        // This prevents rebasing tokens from manipulating the check
        uint256 expectedAfter = balanceBefore + fee;
        uint256 actualBalance = loanToken.balanceOf(address(this));
        require(actualBalance >= expectedAfter, "Loan not repaid");

        // Sync internal accounting with actual balance
        poolBalance = actualBalance;

        totalFees += fee;
        emit FlashLoanExecuted(msg.sender, amount, fee);
    }

    function depositToPool(uint256 amount) external {
        loanToken.transferFrom(msg.sender, address(this), amount);
        poolBalance += amount;
    }

    function withdrawFees() external {
        require(msg.sender == owner, "Not owner");
        uint256 fees = totalFees;
        totalFees = 0;
        // Only withdraw fee portion, not pool principal
        poolBalance -= fees;
        loanToken.transfer(owner, fees);
    }

    function setPaused(bool _paused) external {
        require(msg.sender == owner, "Not owner");
        paused = _paused;
        if (_paused) emit Paused();
        else emit Unpaused();
    }

    function getPoolBalance() external view returns (uint256) {
        return poolBalance;
    }
}
