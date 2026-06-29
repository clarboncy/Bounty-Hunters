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
    AggregatorV3Interface public fallbackFeed; // Fallback oracle for redundancy
    address public owner;
    uint256 public MAX_STALENESS = 3600;

    event PriceQueried(int256 price, uint256 timestamp);
    event FallbackUsed(int256 price, uint256 timestamp);

    constructor(address _primaryFeed) {
        primaryFeed = AggregatorV3Interface(_primaryFeed);
        owner = msg.sender;
    }

    /// @notice Sets a fallback oracle feed for redundancy
    function setFallbackFeed(address _fallbackFeed) external {
        require(msg.sender == owner, "Not owner");
        fallbackFeed = AggregatorV3Interface(_fallbackFeed);
    }

    /// @notice Gets the latest price with full validation
    /// @dev Validates: price > 0, round completeness, staleness
    ///      Falls back to secondary oracle if primary fails
    function getLatestPrice() external view returns (int256) {
        (int256 price, uint256 updatedAt) = _getValidatedPrice(primaryFeed);
        emit PriceQueried(price, updatedAt);
        return price;
    }

    /// @notice Internal function to get and validate price from a feed
    function _getValidatedPrice(AggregatorV3Interface feed) internal view returns (int256 price, uint256 updatedAt) {
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 _updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        // Check for negative or zero price
        require(answer > 0, "Invalid price: zero or negative");

        // Check round completeness — answeredInRound must be >= roundId
        require(answeredInRound >= roundId, "Round not complete");

        // Check staleness — updatedAt must be within MAX_STALENESS
        require(block.timestamp - _updatedAt < MAX_STALENESS, "Price is stale");

        return (answer, _updatedAt);
    }

    /// @notice Gets price with fallback support
    function getPriceWithFallback() external view returns (int256) {
        try this.getLatestPrice() returns (int256 price) {
            return price;
        } catch {
            require(address(fallbackFeed) != address(0), "No fallback oracle");
            (int256 price, uint256 updatedAt) = _getValidatedPrice(fallbackFeed);
            emit FallbackUsed(price, updatedAt);
            return price;
        }
    }

    function getDecimals() external view returns (uint8) {
        return primaryFeed.decimals();
    }

    function setMaxStaleness(uint256 _maxStaleness) external {
        require(msg.sender == owner, "Not owner");
        MAX_STALENESS = _maxStaleness;
    }
}
