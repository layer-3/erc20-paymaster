pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ERC20PaymasterOnlyFactory, ERC20OracleOnlyFactory, PaymasterVersion} from "../src/factory/ERC20PaymasterFactory.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IOracle} from "../src/interfaces/oracles/IOracle.sol";

contract DeployPaymaster is Script {
  address public constant ENTRY_POINT = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
  bytes32 public constant SALT = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

  error EmptyPaymasterOnlyFactoryAddress();
  error EmptyOracleOnlyFactoryAddress();
  error EmptyOwnerAddress();
  error EmptyTokenAddress();
  error EmptyTokenPoolAddress();
  error EmptyNativePoolAddress();
  error EmptyNativePoolBaseTokenAddress();

  // Function to generate a pseudo-random bytes32 value
  function getRandomBytes32() public view returns (bytes32) {
    // Use block.timestamp, block.prevrandao, and the address of the sender to generate a pseudo-random value
    return keccak256(
      abi.encodePacked(
        block.timestamp,
        block.prevrandao,
        msg.sender
      )
    );
  }

  function run() public {

    string memory paymasterFactoryStr = vm.envString("ERC20_PAYMASTER_FACTORY");
    address paymasterFactoryAddr = vm.parseAddress(paymasterFactoryStr);
    if (address(paymasterFactoryAddr) == address(0)) {
      revert EmptyPaymasterOnlyFactoryAddress();
    }
    ERC20PaymasterOnlyFactory paymasterFactory = ERC20PaymasterOnlyFactory(paymasterFactoryAddr);

    string memory oracleFactoryStr = vm.envString("ERC20_ORACLE_FACTORY");
    address oracleFactoryAddr = vm.parseAddress(oracleFactoryStr);
    if (address(oracleFactoryAddr) == address(0)) {
      revert EmptyOracleOnlyFactoryAddress();
    }
    ERC20OracleOnlyFactory oracleFactory = ERC20OracleOnlyFactory(oracleFactoryAddr);

    // Parse params

    string memory ownerStr = vm.envString("ERC20_PAYMASTER_OWNER");
    address owner = vm.parseAddress(ownerStr);
    if (owner == address(0)) {
      revert EmptyOwnerAddress();
    }

    string memory tokenStr = vm.envString("ERC20_TOKEN");
    address token = vm.parseAddress(tokenStr);
    if (token == address(0)) {
      revert EmptyTokenAddress();
    }

    string memory tokenPoolStr = vm.envString("ERC20_TOKEN_POOL");
    address tokenPool = vm.parseAddress(tokenPoolStr);
    if (tokenPool == address(0)) {
      revert EmptyTokenPoolAddress();
    }

    string memory nativePoolStr = vm.envString("ERC20_NATIVE_POOL");
    address nativePool = vm.parseAddress(nativePoolStr);
    if (nativePool == address(0)) {
      revert EmptyNativePoolAddress();
    }

    string memory nativePoolBaseTokenStr = vm.envString("ERC20_NATIVE_POOL_BASE_TOKEN");
    address nativePoolBaseToken = vm.parseAddress(nativePoolBaseTokenStr);
    if (nativePoolBaseToken == address(0)) {
      revert EmptyNativePoolBaseTokenAddress();
    }

    string memory twapAgeStr = vm.envString("ERC20_TWAP_AGE");
    uint32 twapAge = uint32(vm.parseUint(twapAgeStr));
    if (twapAge == 0) {
      twapAge = 3600;
    }

    // Deploy paymaster

    // e.g. KAYEN / USDC.e
    address tokenOracle = oracleFactory.deployTwapOracle(
      getRandomBytes32(),
      tokenPool,
      twapAge,
      token
    );

    // e.g. USDC.e / ETH
    address nativeOracle = oracleFactory.deployTwapOracle(
      getRandomBytes32(),
      nativePool,
      twapAge,
      nativePoolBaseToken
    );

    address paymaster = paymasterFactory.deployPaymaster(
      SALT,
      PaymasterVersion.V06,
      IERC20Metadata(token),
      ENTRY_POINT,
      IOracle(tokenOracle),
      IOracle(nativeOracle),
      172800,
      owner,
      1200000,
      1200000,
      30000,
      50000
    );

    console.log("Token oracle address: %s", tokenOracle);
    console.log("Native oracle address: %s", nativeOracle);
    console.log("Paymaster address: %s", paymaster);
  }
}
