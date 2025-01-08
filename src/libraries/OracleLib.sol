// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Luciano Zanin Gabriel
 * @notice Library used to get the price of an asset from a chainlink oracle.
 * If a price is stale, it will revert and render the NSCEngine unusable.
 * We want the NSCEngine to freeze if prices become stale to prevent any further damage.
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 public constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSinceUpdated = block.timestamp - updatedAt;
        if (secondsSinceUpdated > TIMEOUT) revert OracleLib__StalePrice();
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
