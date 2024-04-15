// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IOracle} from "./../interfaces/IOracle.sol";


contract FixedPriceOracle is IOracle {
    int256 public constant ORACLE_DECIMALS = 1e8;

    function decimals() external override pure returns (uint8) {
        return 8;
    }

    function latestRoundData() external override view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (uint80(0), ORACLE_DECIMALS, 0, block.timestamp - 1, uint80(0));
    }
}