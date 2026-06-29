// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockChainlinkFeed {
    uint8 public decimals;
    int256 public price;
    uint256 public updatedAt;
    bool public roundComplete;
    uint80 public roundId = 1;

    constructor(uint8 _decimals, int256 _price, bool _roundComplete) {
        decimals = _decimals;
        price = _price;
        updatedAt = block.timestamp;
        roundComplete = _roundComplete;
    }

    function latestRoundData() external view returns (
        uint80, int256, uint256, uint256, uint80
    ) {
        return (roundId, price, block.timestamp - 100, updatedAt, roundComplete ? roundId : 0);
    }

    function setPrice(int256 _price) external { price = _price; }
    function setUpdatedAt(uint256 _ts) external { updatedAt = _ts; }
    function setRoundComplete(bool _complete) external { roundComplete = _complete; }
}
