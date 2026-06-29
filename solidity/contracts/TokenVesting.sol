// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenVesting {
    IERC20 public token;
    address public beneficiary;
    address public owner;

    uint256 public totalAllocation;
    uint256 public start;
    uint256 public cliff;
    uint256 public duration;
    uint256 public claimed;
    bool public revoked;

    event TokensClaimed(address indexed beneficiary, uint256 amount);
    event VestingRevoked(address indexed beneficiary, uint256 unvested);

    constructor(
        address _token,
        address _beneficiary,
        uint256 _totalAllocation,
        uint256 _start,
        uint256 _cliffDuration,
        uint256 _vestingDuration
    ) {
        token = IERC20(_token);
        beneficiary = _beneficiary;
        owner = msg.sender;
        totalAllocation = _totalAllocation;
        start = _start;
        cliff = _start + _cliffDuration;
        duration = _vestingDuration;
    }

    /// @notice Calculates vested amount using divide-before-multiply to prevent overflow
    /// @dev For 1 billion tokens (1e27) with 18 decimals, totalAllocation * elapsed would
    ///      overflow uint256. By dividing first, we avoid the intermediate overflow.
    function vestedAmount() public view returns (uint256) {
        if (block.timestamp < cliff) return 0;
        if (block.timestamp >= start + duration) return totalAllocation;

        uint256 elapsed = block.timestamp - start;

        // Divide before multiply to prevent intermediate overflow
        // totalAllocation / duration * elapsed
        uint256 vested = (totalAllocation / duration) * elapsed;

        // Handle remainder to avoid losing tokens due to integer truncation
        // remainder = totalAllocation % duration
        // We distribute the remainder proportionally based on elapsed time
        uint256 remainder = totalAllocation % duration;
        if (remainder > 0) {
            // Add proportional remainder: remainder * elapsed / duration
            // This is safe because remainder < duration, so remainder * elapsed < duration * duration
            // which is well within uint256 range
            vested += (remainder * elapsed) / duration;
        }

        return vested;
    }

    function claimable() public view returns (uint256) {
        return vestedAmount() - claimed;
    }

    function claim() external {
        require(msg.sender == beneficiary, "Not beneficiary");
        require(!revoked, "Vesting revoked");
        uint256 amount = claimable();
        require(amount > 0, "Nothing to claim");
        claimed += amount;
        token.transfer(beneficiary, amount);
        emit TokensClaimed(beneficiary, amount);
    }

    /// @notice Revoke vesting and return unvested tokens to owner
    /// @dev Unvested = totalAllocation - claimed (not totalAllocation - vested)
    ///      This ensures during cliff period (vested=0, claimed=0), all tokens go back to owner
    function revoke() external {
        require(msg.sender == owner, "Not owner");
        require(!revoked, "Already revoked");
        revoked = true;

        uint256 vested = vestedAmount();

        // Transfer any vested but unclaimed tokens to beneficiary
        if (vested > claimed) {
            token.transfer(beneficiary, vested - claimed);
        }

        // Unvested = totalAllocation - claimed (everything not yet claimed goes back to owner)
        // This is correct because: vested - claimed already sent to beneficiary above
        // So remaining = totalAllocation - claimed - (vested - claimed) = totalAllocation - vested
        // But we use totalAllocation - claimed to account for the edge case where
        // claimed > vested (shouldn't happen but defensive)
        uint256 unvested = totalAllocation - claimed;
        if (vested > claimed) {
            unvested = totalAllocation - vested;
        }

        token.transfer(owner, unvested);
        emit VestingRevoked(beneficiary, unvested);
    }
}
