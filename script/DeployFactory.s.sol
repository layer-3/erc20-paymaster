pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ERC20PaymasterOnlyFactory, ERC20OracleOnlyFactory} from "../src/factory/ERC20PaymasterFactory.sol";

contract DeployFactory is Script {
  function run() public {
    string memory ownerStr = vm.envString("ERC20_FACTORY_OWNER");
    address owner = vm.parseAddress(ownerStr);

    vm.startBroadcast(); // start broadcasting transactions to the blockchain
    ERC20PaymasterOnlyFactory paymasterFactory = new ERC20PaymasterOnlyFactory(owner);
    ERC20OracleOnlyFactory oracleFactory = new ERC20OracleOnlyFactory(owner);
    vm.stopBroadcast();

    console.log("owner wallet address: %s", owner);
    console.log("Paymaster factory address: %s", address(paymasterFactory));
    console.log("Oracle factory address: %s", address(oracleFactory));
  }
}
