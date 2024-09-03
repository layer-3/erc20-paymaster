// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./OracleFactory.sol";

import "@openzeppelin-v5.0.0/contracts/access/Ownable.sol";


contract ERC20OracleOnlyFactory is OracleFactory {
    constructor(
        address _owner
    ) Ownable(_owner) {}
}

