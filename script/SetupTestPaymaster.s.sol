// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {ERC20PaymasterOnlyFactory} from "../src/factory/ERC20PaymasterOnlyFactory.sol";
import {FixedOracle} from "../src/oracles/FixedOracle.sol";
import {ManualOracle} from "../src/oracles/ManualOracle.sol";
import {ERC20PaymasterOnlyFactory} from "../src/factory/ERC20PaymasterOnlyFactory.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PaymasterVersion} from "../src/factory/ERC20PaymasterFactory.sol";
import {IOracle} from "../src/interfaces/oracles/IOracle.sol";
import {BasePaymaster} from "../src/base/BasePaymaster.sol";

contract SetupTestPaymaster is Script {
    error EmptyERC20Address();
    error EmptyEthToTokenRatio();

    address public constant ENTRY_POINT = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    bytes32 public constant SALT = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

    function run() external {
        address deployer = msg.sender;

        console.log("executing with:", deployer);

        address paymasterFactoryAddress = vm.envOr("PAYMASTER_FACTORY_ADDRESS", address(0));
        address fixedOracleAddress = vm.envOr("FIXED_ORACLE_ADDRESS", address(0));

        string memory tokenAddressString = vm.envString("ERC20_TOKEN_ADDRESS");
        address tokenAddress = vm.parseAddress(tokenAddressString);
        if (tokenAddress == address(0)) {
            revert EmptyERC20Address();
        }

        string memory ethToTokenRatioString = vm.envString("ETH_TO_TOKEN_RATIO");
        int256 ethToTokenRatio = vm.parseInt(ethToTokenRatioString);
        if (ethToTokenRatio == 0) {
            revert EmptyEthToTokenRatio();
        }

        uint256 valueToDeposit = vm.envOr("VALUE_TO_DEPOSIT", uint256(0));

        vm.startBroadcast();
        if (paymasterFactoryAddress == address(0)) {
            paymasterFactoryAddress = address(new ERC20PaymasterOnlyFactory(deployer));
            console.log("Paymaster factory address:", address(paymasterFactoryAddress));
        }

        if (fixedOracleAddress == address(0)) {
            fixedOracleAddress = address(new FixedOracle(100000000));
            console.log("Fixed Oracle address:", address(fixedOracleAddress));
        }

        ManualOracle manualOracle = new ManualOracle(ethToTokenRatio, deployer);
        console.log("Manual Oracle address:", address(manualOracle));

        address paymaster = ERC20PaymasterOnlyFactory(paymasterFactoryAddress).deployPaymaster(
            SALT,
            PaymasterVersion.V06,
            IERC20Metadata(tokenAddress),
            ENTRY_POINT,
            FixedOracle(fixedOracleAddress),
            manualOracle,
            172800,
            deployer,
            1200000,
            1000000,
            30000,
            50000
        );
        console.log("Paymaster address:", paymaster);

        if (valueToDeposit == 0) {
            return;
        }

        BasePaymaster(paymaster).deposit{value: valueToDeposit}();
        console.log("Deposited:", valueToDeposit);
    }
}
