// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFlashLoan {
    function flashLoan(uint256 amount, bytes calldata data) external;
}

contract MockFlashBorrower {
    IFlashLoan public flashLoanContract;
    address public token;

    constructor(address _flashLoan) {
        flashLoanContract = IFlashLoan(_flashLoan);
    }

    function executeFlashLoan(address _token, uint256 amount, bytes calldata data) external {
        token = _token;
        IERC20(_token).approve(address(flashLoanContract), type(uint256).max);
        flashLoanContract.flashLoan(amount, data);
    }

    function onFlashLoan(address _token, uint256 amount, uint256 fee, bytes calldata data) external {
        // Repay loan + fee
        IERC20(_token).transfer(msg.sender, amount + fee);
    }
}
