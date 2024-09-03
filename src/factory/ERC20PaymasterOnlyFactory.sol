// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./PaymasterFactory.sol";

import "@openzeppelin-v5.0.0/contracts/access/Ownable.sol";


contract ERC20PaymasterOnlyFactory is PaymasterFactory {
    constructor(
        address _owner
    ) Ownable(_owner) {}
}

