// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;


import {IEntryPoint} from "@account-abstraction-v6/contracts/interfaces/IEntryPoint.sol";
import {UserOperationLib, UserOperation} from "@account-abstraction-v6/contracts/interfaces/UserOperation.sol";
import {_packValidationData, calldataKeccak} from "@account-abstraction-v6/contracts/core/Helpers.sol";

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {BaseERC20Paymaster} from "./base/BaseERC20Paymaster.sol";
import {IPaymaster} from "./interfaces/paymasters/IPaymasterV06.sol";
import {IOracle} from "./interfaces/oracles/IOracle.sol";


using UserOperationLib for UserOperation;


/// @title ERC20PaymasterV06
/// @author Pimlico (https://github.com/pimlicolabs/erc20-paymaster/blob/main/src/ERC20PaymasterV06.sol)
/// @author Using Solady (https://github.com/vectorized/solady)
/// @notice An ERC-4337 Paymaster contract which is able to sponsor gas fees in exchange for ERC-20 tokens.
/// The contract refunds excess tokens. It also allows updating price configuration and withdrawing tokens by the contract owner.
/// The contract uses oracles to fetch the latest token prices.
/// The paymaster supports standard and up-rebasing ERC-20 tokens. It does not support down-rebasing and fee-on-transfer tokens.
/// @dev Inherits from BaseERC20Paymaster.
/// @custom:security-contact security@pimlico.io
contract ERC20PaymasterV06 is BaseERC20Paymaster, IPaymaster {
    constructor(
        IERC20Metadata _token,
        address _entryPoint,
        IOracle _tokenOracle,
        IOracle _nativeAssetOracle,
        uint32 _stalenessThreshold,
        address _owner,
        uint32 _priceMarkupLimit,
        uint32 _priceMarkup,
        uint256 _refundPostOpCost,
        uint256 _refundPostOpCostWithGuarantor
    ) BaseERC20Paymaster(
        _token,
        _entryPoint,
        _tokenOracle,
        _nativeAssetOracle,
        _stalenessThreshold,
        _owner,
        _priceMarkupLimit,
        _priceMarkup,
        _refundPostOpCost,
        _refundPostOpCostWithGuarantor
    ) {}

    /// @inheritdoc IPaymaster
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external override returns (bytes memory context, uint256 validationData) {
         _requireFromEntryPoint();
        return _validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    /// @inheritdoc IPaymaster
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) external override {
        _requireFromEntryPoint();
        _postOp(mode, context, actualGasCost);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-4337 PAYMASTER FUNCTIONS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        internal
        returns (bytes memory context, uint256 validationResult)
    {
        (uint8 mode, bytes calldata paymasterConfig) = _parsePaymasterAndData(userOp.paymasterAndData);

        // valid modes are 0, 1, 2, 3
        if (mode >= 4) {
            revert PaymasterDataModeInvalid();
        }

        uint192 tokenPrice = getPrice();
        uint256 tokenAmount;
        {
            uint256 maxFeePerGas = userOp.maxFeePerGas;
            if (mode == 0 || mode == 1) {
                tokenAmount = Math.mulDiv(
                    (maxCost + (refundPostOpCost) * maxFeePerGas) * priceMarkup,
                    tokenPrice,
                    1e18 * PRICE_DENOMINATOR,
                    Math.Rounding.Ceil
                );
            } else {
                tokenAmount = Math.mulDiv(
                    (maxCost + (refundPostOpCostWithGuarantor) * maxFeePerGas) * priceMarkup,
                    tokenPrice,
                    1e18 * PRICE_DENOMINATOR,
                    Math.Rounding.Ceil
                );
            }
        }

        if (mode == 0) {
            if (paymasterConfig.length != 0) {
                revert PaymasterDataLengthInvalid();
            }

            SafeTransferLib.safeTransferFrom(address(token), userOp.sender, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, tokenPrice, userOp.sender, userOpHash, getUserOpGasPrice(userOp));
            validationResult = 0;
        } else if (mode == 1) {
            if (paymasterConfig.length != 32) {
                revert PaymasterDataLengthInvalid();
            }
            uint256 tokenLimit = uint256(bytes32(paymasterConfig[0:32]));
            if (tokenLimit == 0) {
                revert TokenLimitZero();
            }
            if (tokenAmount > tokenLimit) {
                revert TokenAmountTooHigh();
            }
            SafeTransferLib.safeTransferFrom(address(token), userOp.sender, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, tokenPrice, userOp.sender, userOpHash, getUserOpGasPrice(userOp));
            validationResult = 0;
        } else if (mode == 2) {
            if (paymasterConfig.length < 32) {
                revert PaymasterDataLengthInvalid();
            }

            address guarantor = address(bytes20(paymasterConfig[0:20]));

            bool signatureValid = SignatureChecker.isValidSignatureNow(
                guarantor,
                getHash(userOp, uint48(bytes6(paymasterConfig[20:26])), uint48(bytes6(paymasterConfig[26:32])), type(uint256).max),
                paymasterConfig[32:]
            );

            SafeTransferLib.safeTransferFrom(address(token), guarantor, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, tokenPrice, userOp.sender, userOpHash, getUserOpGasPrice(userOp), guarantor);
            validationResult = _packValidationData(
                !signatureValid, uint48(bytes6(paymasterConfig[20:26])), uint48(bytes6(paymasterConfig[26:32]))
            );
        } else {
            if (paymasterConfig.length < 64) {
                revert PaymasterDataLengthInvalid();
            }

            uint256 tokenLimit = uint256(bytes32(paymasterConfig[0:32]));
            address guarantor = address(bytes20(paymasterConfig[32:52]));

            if (tokenLimit == 0) {
                revert TokenLimitZero();
            }
            if (tokenAmount > tokenLimit) {
                revert TokenAmountTooHigh();
            }

            bool signatureValid = SignatureChecker.isValidSignatureNow(
                guarantor,
                getHash(
                    userOp,
                    uint48(bytes6(paymasterConfig[52:58])),
                    uint48(bytes6(paymasterConfig[58:64])),
                    tokenLimit
                ),
                paymasterConfig[64:]
            );

            SafeTransferLib.safeTransferFrom(address(token), guarantor, address(this), tokenAmount);
            context = abi.encodePacked(tokenAmount, tokenPrice, userOp.sender, userOpHash, getUserOpGasPrice(userOp), guarantor);
            validationResult = _packValidationData(
                !signatureValid, uint48(bytes6(paymasterConfig[52:58])), uint48(bytes6(paymasterConfig[58:64]))
            );
        }
    }

    /**
     * post-operation handler.
     * (verified to be called only through the entryPoint)
     * @dev if subclass returns a non-empty context from validatePaymasterUserOp, it must also implement this method.
     * @param context - the context value returned by validatePaymasterUserOp
     * @param actualGasCost - actual gas used so far (without this postOp call).
     */
    function _postOp(PostOpMode, bytes calldata context, uint256 actualGasCost)
        internal
    {
        uint256 prefundTokenAmount = uint256(bytes32(context[0:32]));
        uint192 tokenPrice = uint192(bytes24(context[32:56]));
        address sender = address(bytes20(context[56:76]));
        bytes32 userOpHash = bytes32(context[76:108]);
        uint256 gasPrice = uint256(bytes32(context[108:140]));

        if (context.length == 160) {
            // A guarantor is used
            uint256 actualTokenNeeded = Math.mulDiv(
                (actualGasCost + (refundPostOpCostWithGuarantor) * gasPrice) * priceMarkup,
                tokenPrice,
                1e18 * PRICE_DENOMINATOR,
                Math.Rounding.Ceil
            );
            address guarantor = address(bytes20(context[140:160]));

            bool success = SafeTransferLib.trySafeTransferFrom(address(token), sender, address(this), actualTokenNeeded);
            if (success) {
                // If the token transfer is successful, transfer the held tokens back to the guarantor
                SafeTransferLib.safeTransfer(address(token), guarantor, prefundTokenAmount);
                emit UserOperationSponsored(userOpHash, sender, guarantor, actualTokenNeeded, tokenPrice, false);
            } else {
                // If the token transfer fails, the guarantor is deemed responsible for the token payment
                SafeTransferLib.safeTransfer(address(token), guarantor, prefundTokenAmount - actualTokenNeeded);
                emit UserOperationSponsored(userOpHash, sender, guarantor, actualTokenNeeded, tokenPrice, true);
            }
        } else {
            uint256 actualTokenNeeded = Math.mulDiv(
                (actualGasCost + (refundPostOpCost) * gasPrice) * priceMarkup,
                tokenPrice,
                1e18 * PRICE_DENOMINATOR,
                Math.Rounding.Ceil
            );

            SafeTransferLib.safeTransfer(address(token), sender, prefundTokenAmount - actualTokenNeeded);
            emit UserOperationSponsored(userOpHash, sender, address(0), actualTokenNeeded, tokenPrice, false);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INTERNAL HELPERS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Parses the paymasterAndData field of the user operation and returns the paymaster mode and data.
    /// @param _paymasterAndData The paymasterAndData field of the user operation.
    /// @return mode The paymaster mode.
    /// @return paymasterConfig The paymaster configuration data.
    function _parsePaymasterAndData(bytes calldata _paymasterAndData) internal pure override returns (uint8, bytes calldata) {
        if (_paymasterAndData.length < 21) {
            return (0, msg.data[0:0]);
        }
        return (uint8(_paymasterAndData[20]), _paymasterAndData[21:]);
    }

    function getUserOpGasPrice(UserOperation calldata userOp) internal view returns (uint256) {
        unchecked {
            uint256 maxFeePerGas = userOp.maxFeePerGas;
            uint256 maxPriorityFeePerGas = userOp.maxPriorityFeePerGas;
            if (maxFeePerGas == maxPriorityFeePerGas) {
                //legacy mode (for networks that don't support basefee opcode)
                return maxFeePerGas;
            }
            return min(maxFeePerGas, maxPriorityFeePerGas + block.basefee);
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC HELPERS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function getHash(
        UserOperation calldata userOp,
        uint48 validUntil,
        uint48 validAfter,
        uint256 tokenLimit
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                userOp.sender,
                userOp.nonce,
                calldataKeccak(userOp.initCode),
                calldataKeccak(userOp.callData),
                userOp.callGasLimit,
                userOp.verificationGasLimit,
                userOp.preVerificationGas,
                userOp.maxFeePerGas,
                userOp.maxPriorityFeePerGas,
                block.chainid,
                address(this),
                validUntil,
                validAfter,
                tokenLimit
            )
        );
    }
}