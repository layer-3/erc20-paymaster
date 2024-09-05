# ERC20 paymaster deployment

This document describes the deployment process of the ERC20 paymaster and the accompanying infrastructure.

## Prerequisites

### Foundry

Deployments are done using the `foundry` toolchain. Make sure you have it installed.

Read more about installation [on their official documentation](https://book.getfoundry.sh/getting-started/installation).

### Dependencies

ERC20 paymaster uses standalone contracts for its operation:

- 2 Oracles, that provide the price feed for the paymaster
- Uniswap-v3-compatible liquidity pool
- ERC20Paymaster itself

#### Oracles

Note that 2 oracles provide the Token <> USD and USD <> ETH price feeds, which require 2 corresponding liquidity pools.
However, it is possible to operate with only 1 liquidity pool, Token <> ETH. In this case, one oracle will provide the Token <> ETH price, and the other should state the exchange rate of USD <> USD, and therefore can be a fixed oracle.

#### Liqiudity pool

Token <> ETH liquidity pool is required for the operation of the ERC20 paymaster. It is used by the TwapOracle to provide the price feed for the ERC20 paymaster.
Liqiudity pool deployment is outside the scope of this document.

### Factories

Deployment of the paymaster and its infrastructure happens through the corresponding factory contracts on each chain.

Note that for security purposes, both factories are ownerful, and only the owner can deploy new instances of the paymaster and its infrastructure.
Therefore, you need to specify the owner address when deploying the factory. You should store the owner address to `$FACTORY_OWNER_ADDRESS` and private key for further usage to `$FACTORY_OWNER_PRIVATE_KEY`.
You can deploy the factory with any account, so specify its private key in `$DEPLOYER_PRIVATE_KEY`.

To deploy the Oracle factory, run the following command:

```shell
forge create --optimizer-runs 100 -via-ir src/factory/ERC20OracleOnlyFactory.sol:ERC20OracleOnlyFactory --constructor-args $FACTORY_OWNER_ADDRESS --private-key $DEPLOYER_PRIVATE_KEY -r $PROVIDER_URL -c <chain_id>
```

The command will return the address of the deployed factory, that you should save to `$ORACLE_FACTORY_ADDRESS`.

---

To deploy the Paymaster factory, run the following command:

```shell
forge create --optimizer-runs 100 -via-ir src/factory/ERC20PaymasterOnlyFactory.sol:ERC20PaymasterOnlyFactory --constructor-args $FACTORY_OWNER_ADDRESS --private-key $DEPLOYER_PRIVATE_KEY -r $PROVIDER_URL -c <chain_id>
```

The command will return the address of the deployed factory, that you should save to `$PAYMASTER_FACTORY_ADDRESS`.

## Deployment

Below commands require some parameters and environment variables:

- <salt> - the random bytes32 value that is used to derive the address of the deployed contract. It can be unique for each deployment.
- <chain_id> - the chain id of the network where the contract will be deployed.
- `$NATIVE_POOL_ADDRESS` - the address of the Token <> ETH liquidity pool.
- `$POOL_NATIVE_TOKEN_ADDRESS` - the address of the native token FROM THE LIQUIDITY POOL.
- `$TOKEN_ADDRESS` - the address of the token that the paymaster will operate with.
- `$PAYMASTER_OWNER_ADDRESS` - the address of the paymaster owner, that will be able to change the price markup.
- <price_markup> - the price markup, where 1000000 means 100%. It is used to calculate the price of the token in the paymaster. For example, 100% markup and that the user will pay at the actual price, and 120% means the user pays 20% more. Possible values are from 0 to 4294967295.
- <max_price_markup> - the maximum price markup that the paymaster owner can set.

To deploy FixedOracle: run:

```shell
cast send $ORACLE_FACTORY_ADDRESS "deployFixedOracle(bytes32 salt, int256 _price)" <salt> 100000000 --private-key $FACTORY_OWNER_PRIVATE_KEY -r $PROVIDER_URL -c <chain_id>
```

The command will return the address of the deployed oracle, that you should save to `$FIXED_ORACLE_ADDRESS`.

---

To deploy TwapOracle: run:

```shell
cast send $ORACLE_FACTORY_ADDRESS "deployTwapOracle(bytes32,address,uint32,address)" <salt> $NATIVE_POOL_ADDRESS 61 POOL_NATIVE_TOKEN_ADDRESS --private-key $FACTORY_OWNER_PRIVATE_KEY -r $PROVIDER_URL -c <chain_id>
```

The command will return the address of the deployed oracle, that you should save to `$TWAP_ORACLE_ADDRESS`.

---

To deploy ERC20PaymasterV6 run:

```shell
cast send $PAYMASTER_FACTORY_ADDRESS "deployPaymaster(bytes32,uint8,address,address,address,address,uint32,address,uint32,uint32,uint256,uint256)" <salt> 0 $TOKEN_ADDRESS 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789 $FIXED_ORACLE_ADDRESS $TWAP_ORACLE_ADDRESS 172800 $PAYMASTER_OWNER_ADDRESS <price_markup> <max_price_markup> 30000 50000 --private-key $OWNER_PRIVATE_KEY -r $PROVIDER_URL -c <chain_id>
```

The command will return the address of the deployed paymaster, that you should save to `$PAYMASTER_ADDRESS`.

## Changes to Wallet settings

Now you should have the paymaster deployed. The next step would be to change the settings of the Wallet so that paymaster can be used.

For each chain you have deployed the paymaster to, you need to modify the `wallet.json` file in the corresponding `networks/<chain_id>` directory in the `clearsync` repository.

You need to add fee token address as key and paymaster address as a value to `paymasters` mapping:

```json
{
  "paymaster": [
    {
      "<fee_token_address>": "<paymaster_address>"
    }
  ]
}
```

Where `<fee_token_address>` is the address of the token that the paymaster will operate with, and `<paymaster_address>` is the address of the deployed ERC20 paymaster.

## Operation

### EntryPoint deposit

The paymaster requires a deposit on the EntryPoint to operate. During UserOp execution, EntryPoint will check the paymaster deposit and deduct the required amount from it.

To check the paymaster deposit, run:

```shell
cast call 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789 "balanceOf(address account)" $PAYMASTER_ADDRESS -r $PROVIDER_URL -c <chain_id>
```

---

Any account can deposit funds to the paymaster, therefore you can use private key of any account with funds (specify it in `$PRIVATE_KEY`).

An amount to top-up the deposit should be specified in <amount>.

To top-up the paymaster deposit, run:

```shell
cast send 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789 "depositTo(address account)" $PAYMASTER_ADDRESS --value <amount> --private-key $PRIVATE_KEY -r $PROVIDER_URL -c <chain_id>
```

### Withdraw funds from Paymaster

While in operation, the paymaster can accumulate funds that can be withdrawn by the owner.

You can specify any address to withdraw the token to in <to>, and the amount to withdraw in <amount>.

To withdraw the token from the paymaster, run:

```shell
cast send $PAYMASTER_ADDRESS "withdrawToken(address to, uint256 amount)" <to> <amount> --private-key $PAYMASTER_OWNER_ADDRESS -r $PROVIDER_URL -c <chain_id>
```

### Paymaster Markup

The paymaster owner can change the price markup by calling the `updateMarkup` function on the paymaster contract:

```shell
cast send $PAYMASTER_ADDRESS "updateMarkup(uint32 _priceMarkup)" <price_markup> --private-key $PAYMASTER_OWNER_ADDRESS -r $PROVIDER_URL -c <chain_id>
```

Remember that the paymaster owner can set the price markup only within the range of the maximum price markup that was set during the deployment.
