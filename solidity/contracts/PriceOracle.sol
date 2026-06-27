// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

contract PriceOracle {
    AggregatorV3Interface public primaryFeed;
    AggregatorV3Interface public fallbackFeed;
    address public owner;
    uint256 public MAX_STALENESS = 3600;

    event PriceQueried(int256 price, uint256 timestamp, bool usedFallback);
    event FallbackFeedUpdated(address indexed newFallback);

    constructor(address _primaryFeed) {
        primaryFeed = AggregatorV3Interface(_primaryFeed);
        owner = msg.sender;
    }

    /// @notice Get latest price with full validation + fallback oracle
    function getLatestPrice() external view returns (int256) {
        (uint80 roundId, int256 price, , uint256 updatedAt, uint80 answeredInRound) =
            primaryFeed.latestRoundData();

        // Validate primary feed
        if (_isStaleOrInvalid(roundId, price, updatedAt, answeredInRound)) {
            // Use fallback if available
            if (address(fallbackFeed) != address(0)) {
                (uint80 fbRoundId, int256 fbPrice, , uint256 fbUpdatedAt, uint80 fbAnsweredInRound) =
                    fallbackFeed.latestRoundData();
                require(!_isStaleOrInvalid(fbRoundId, fbPrice, fbUpdatedAt, fbAnsweredInRound), "Both feeds invalid");
                emit PriceQueried(fbPrice, fbUpdatedAt, true);
                return fbPrice;
            }
            revert("Primary feed stale and no fallback");
        }

        emit PriceQueried(price, updatedAt, false);
        return price;
    }

    /// @notice Internal validation for round completeness, price positivity, and staleness
    function _isStaleOrInvalid(
        uint80 roundId,
        int256 price,
        uint256 updatedAt,
        uint80 answeredInRound
    ) internal view returns (bool) {
        if (price <= 0) return true;
        if (answeredInRound < roundId) return true;
        if (block.timestamp - updatedAt > MAX_STALENESS) return true;
        return false;
    }

    function getDecimals() external view returns (uint8) {
        return primaryFeed.decimals();
    }

    function setMaxStaleness(uint256 _maxStaleness) external {
        require(msg.sender == owner, "Not owner");
        MAX_STALENESS = _maxStaleness;
    }

    /// @notice Set fallback oracle feed
    function setFallbackFeed(address _fallbackFeed) external {
        require(msg.sender == owner, "Not owner");
        fallbackFeed = AggregatorV3Interface(_fallbackFeed);
        emit FallbackFeedUpdated(_fallbackFeed);
    }
}
